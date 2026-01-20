// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {ECDSA} from "solady/utils/ECDSA.sol";
import {ManagedWithdrawRWA} from "../token/ManagedWithdrawRWA-multicollateral.sol";
import {ReportedStrategy} from "./ReportedStrategy.sol";
import {IMultiCollateralStrategy} from "../interfaces/IMultiCollateralStrategy.sol";
import {IMultiCollateralRegistry} from "../interfaces/IMultiCollateralRegistry.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/**
 * @title ManagedWithdrawMultiCollateralStrategy
 * @notice Multi-collateral strategy with managed withdrawals and EIP-712 signatures
 */
contract ManagedWithdrawMultiCollateralStrategy is ReportedStrategy {
    using SafeTransferLib for address;

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error WithdrawalRequestExpired();
    error WithdrawNonceReuse();
    error WithdrawInvalidSignature();
    error InvalidArrayLengths();
    error OnlyVault();
    error ZeroAmount();
    error NotAllowed();

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event WithdrawalNonceUsed(address indexed owner, uint96 nonce);
    event CollateralDeposited(address indexed token, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            EIP-712 DATA
    //////////////////////////////////////////////////////////////*/

    /// @notice Signature argument struct
    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    // EIP-712 Type Hash Constants
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 private constant WITHDRAWAL_REQUEST_TYPEHASH = keccak256(
        "WithdrawalRequest(address owner,address to,uint256 shares,uint256 minAssets,uint96 nonce,uint96 expirationTime)"
    );

    /*//////////////////////////////////////////////////////////////
                            STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Struct to track withdrawal requests
    struct WithdrawalRequest {
        uint256 shares;
        uint256 minAssets;
        address owner;
        uint96 nonce;
        address to;
        uint96 expirationTime;
    }

    // Tracking of used nonces
    mapping(address => mapping(uint96 => bool)) public usedNonces;

    // Multi-collateral state
    address public collateralRegistry;
    address public sovaBTC;
    mapping(address => uint256) public collateralBalances;
    address[] public heldCollateralTokens;
    mapping(address => bool) public isHeldCollateral;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the strategy with ManagedWithdrawRWA token
     * @param name_ Name of the token
     * @param symbol_ Symbol of the token
     * @param roleManager_ Address of the role manager
     * @param manager_ Address of the manager
     * @param asset_ Address of the underlying asset (SovaBTC for redemptions)
     * @param assetDecimals_ Decimals of the asset
     * @param initData Additional initialization data containing registry and sovaBTC addresses
     */
    function initialize(
        string calldata name_,
        string calldata symbol_,
        address roleManager_,
        address manager_,
        address asset_,
        uint8 assetDecimals_,
        bytes memory initData
    ) public override {
        super.initialize(name_, symbol_, roleManager_, manager_, asset_, assetDecimals_, initData);
        
        // Decode multi-collateral configuration from initData
        if (initData.length > 0) {
            (address registry, address sovaBTCAddr) = abi.decode(initData, (address, address));
            collateralRegistry = registry;
            sovaBTC = sovaBTCAddr;
        } else {
            sovaBTC = asset_;
        }
        
        // Pre-approve the vault to pull SovaBTC for withdrawals
        if (sovaBTC != address(0) && sToken != address(0)) {
            sovaBTC.safeApprove(sToken, type(uint256).max);
        }
        
        // Also approve for the underlying asset if different from SovaBTC
        if (asset_ != sovaBTC && asset_ != address(0) && sToken != address(0)) {
            asset_.safeApprove(sToken, type(uint256).max);
        }
    }

    /**
     * @notice Deploy a new ManagedWithdrawRWA token with multi-collateral support
     * @param name_ Name of the token
     * @param symbol_ Symbol of the token
     * @param asset_ Address of the underlying asset
     * @param assetDecimals_ Decimals of the asset
     */
    function _deployToken(string calldata name_, string calldata symbol_, address asset_, uint8 assetDecimals_)
        internal
        virtual
        override
        returns (address)
    {
        return address(new ManagedWithdrawRWA(
            name_,
            symbol_,
            asset_,
            assetDecimals_,
            address(this),
            sovaBTC != address(0) ? sovaBTC : asset_
        ));
    }

    /*//////////////////////////////////////////////////////////////
                        MULTI-COLLATERAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the collateral registry address
     * @param _registry The new registry address
     */
    function setCollateralRegistry(address _registry) external onlyManager {
        collateralRegistry = _registry;
    }

    /**
     * @notice Deposit collateral tokens from the vault
     * @param token The collateral token to deposit
     * @param amount The amount to deposit
     */
    function depositCollateral(address token, uint256 amount) external {
        if (msg.sender != sToken) revert OnlyVault();
        if (amount == 0) revert ZeroAmount();
        
        IMultiCollateralRegistry registry = IMultiCollateralRegistry(collateralRegistry);
        if (!registry.isAllowedCollateral(token)) revert NotAllowed();
        
        collateralBalances[token] += amount;
        
        if (!isHeldCollateral[token]) {
            heldCollateralTokens.push(token);
            isHeldCollateral[token] = true;
        }
        
        emit CollateralDeposited(token, amount);
    }

    /**
     * @notice Deposit SovaBTC redemption funds
     * @param amount The amount of SovaBTC to deposit
     */
    function depositRedemptionFunds(uint256 amount) external onlyManager {
        sovaBTC.safeTransferFrom(msg.sender, address(this), amount);
    }

    function balance() external view override returns (uint256) {
        return _totalCollateralValue();
    }
    
    function totalCollateralValue() external view returns (uint256) {
        return _totalCollateralValue();
    }
    
    function _totalCollateralValue() internal view returns (uint256 total) {
        IMultiCollateralRegistry registry = IMultiCollateralRegistry(collateralRegistry);
        
        for (uint256 i = 0; i < heldCollateralTokens.length; i++) {
            address token = heldCollateralTokens[i];
            uint256 tokenBalance = collateralBalances[token];
            if (tokenBalance > 0) {
                total += registry.convertToSovaBTC(token, tokenBalance);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            REDEMPTION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Process a user-requested withdrawal
     * @param request The withdrawal request
     * @param userSig The signature of the request
     * @return assets The amount of assets received
     */
    function redeem(WithdrawalRequest calldata request, Signature calldata userSig)
        external
        onlyManager
        returns (uint256)
    {
        _validateAndVerify(request, userSig);
        return ManagedWithdrawRWA(sToken).redeem(request.shares, request.to, request.owner, request.minAssets);
    }

    /**
     * @notice Process a batch of user-requested withdrawals
     * @param requests The withdrawal requests
     * @param signatures The signatures of the requests
     * @return assets The amount of assets received
     */
    function batchRedeem(WithdrawalRequest[] calldata requests, Signature[] calldata signatures)
        external
        onlyManager
        returns (uint256[] memory assets)
    {
        if (requests.length != signatures.length) revert InvalidArrayLengths();

        uint256[] memory shares = new uint256[](requests.length);
        address[] memory recipients = new address[](requests.length);
        address[] memory owners = new address[](requests.length);
        uint256[] memory minAssets = new uint256[](requests.length);

        for (uint256 i = 0; i < requests.length;) {
            _validateAndVerify(requests[i], signatures[i]);
            shares[i] = requests[i].shares;
            recipients[i] = requests[i].to;
            owners[i] = requests[i].owner;
            minAssets[i] = requests[i].minAssets;
            unchecked { ++i; }
        }

        assets = ManagedWithdrawRWA(sToken).batchRedeemShares(shares, recipients, owners, minAssets);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _validateAndVerify(WithdrawalRequest calldata request, Signature calldata signature) internal {
        if (request.expirationTime < block.timestamp) revert WithdrawalRequestExpired();
        
        mapping(uint96 => bool) storage userNonces = usedNonces[request.owner];
        if (userNonces[request.nonce]) revert WithdrawNonceReuse();
        userNonces[request.nonce] = true;
        emit WithdrawalNonceUsed(request.owner, request.nonce);
        
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            _domainSeparator(),
            keccak256(abi.encode(
                WITHDRAWAL_REQUEST_TYPEHASH,
                request.owner,
                request.to,
                request.shares,
                request.minAssets,
                request.nonce,
                request.expirationTime
            ))
        ));

        if (ECDSA.recover(digest, signature.v, signature.r, signature.s) != request.owner) {
            revert WithdrawInvalidSignature();
        }
    }

    /**
     * @notice Calculate the EIP-712 domain separator
     * @return The domain separator
     */
    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256("MWMCS"), // Shortened name
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }
}