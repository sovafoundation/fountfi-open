// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {tRWA} from "./tRWA.sol";
import {IHook} from "../hooks/IHook.sol";
import {IRegistry} from "../registry/IRegistry.sol";
import {RoleManaged} from "../auth/RoleManaged.sol";
import {Conduit} from "../conduit/Conduit.sol";
import {GatedMintEscrow} from "../strategy/GatedMintEscrow.sol";

/**
 * FIXME: Add slippage protection before using in production!
 */

/**
 * @title GatedMintRWA
 * @notice Extension of tRWA that implements a two-phase deposit process using an Escrow
 * @dev Deposits are first collected and stored in Escrow; shares are only minted upon acceptance
 */
contract GatedMintRWA is tRWA {
    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotEscrow();
    error EscrowNotSet();
    error InvalidExpirationPeriod();
    error InvalidArrayLengths();

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event DepositPending(
        bytes32 indexed depositId, address indexed depositor, address indexed recipient, uint256 assets
    );

    event DepositExpirationPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);

    event BatchSharesMinted(uint256 totalAssets, uint256 totalShares);

    /*//////////////////////////////////////////////////////////////
                            STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit tracking (IDs only - Escrow has full state)
    bytes32[] public depositIds;

    /// @notice Mapping of user addresses to their deposit IDs
    mapping(address => bytes32[]) public userDepositIds;

    /// @notice Monotonically-increasing sequence number to guarantee unique depositIds
    uint256 private sequenceNum;

    /// @notice Deposit expiration time (in seconds) - default to 7 days
    uint256 public depositExpirationPeriod = 7 days;

    /// @notice Maximum deposit expiration period
    uint256 public constant MAX_DEPOSIT_EXPIRATION_PERIOD = 30 days;

    /// @notice The escrow contract that holds assets and manages deposits
    address public immutable escrow;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructor
     * @param name_ The name of the token
     * @param symbol_ The symbol of the token
     * @param asset_ The address of the asset
     * @param assetDecimals_ The decimals of the asset
     * @param strategy_ The address of the strategy
     */
    constructor(string memory name_, string memory symbol_, address asset_, uint8 assetDecimals_, address strategy_)
        tRWA(name_, symbol_, asset_, assetDecimals_, strategy_)
    {
        // Deploy the GatedMintEscrow contract with this token as the controller
        escrow = address(new GatedMintEscrow(address(this), asset_, strategy_));
    }

    /*//////////////////////////////////////////////////////////////
                        CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the period after which deposits expire and can be reclaimed
     * @param newExpirationPeriod New expiration period in seconds
     */
    function setDepositExpirationPeriod(uint256 newExpirationPeriod) external onlyStrategy {
        if (newExpirationPeriod == 0) revert InvalidExpirationPeriod();
        if (newExpirationPeriod > MAX_DEPOSIT_EXPIRATION_PERIOD) revert InvalidExpirationPeriod();

        uint256 oldPeriod = depositExpirationPeriod;
        depositExpirationPeriod = newExpirationPeriod;

        emit DepositExpirationPeriodUpdated(oldPeriod, newExpirationPeriod);
    }

    /*//////////////////////////////////////////////////////////////
                           ERC4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Override of _deposit to store deposit info instead of minting immediately
     * @param by Address of the sender
     * @param to Address of the recipient
     * @param assets Amount of assets to deposit
     */
    function _deposit(
        address by,
        address to,
        uint256 assets,
        uint256 // shares
    ) internal override nonReentrant {
        // Run hooks (same as in tRWA)
        HookInfo[] storage opHooks = operationHooks[OP_DEPOSIT];
        for (uint256 i = 0; i < opHooks.length;) {
            IHook.HookOutput memory hookOutput = opHooks[i].hook.onBeforeDeposit(address(this), by, assets, to);
            if (!hookOutput.approved) {
                revert HookCheckFailed(hookOutput.reason);
            }

            unchecked {
                ++i;
            }
        }

        // Generate a unique deposit ID
        bytes32 depositId = keccak256(abi.encodePacked(by, to, assets, block.timestamp, address(this), sequenceNum++));

        // Record the deposit ID for lookup
        depositIds.push(depositId);
        userDepositIds[by].push(depositId);

        // Transfer assets to escrow
        Conduit(IRegistry(RoleManaged(strategy).registry()).conduit()).collectDeposit(asset(), by, escrow, assets);

        // Register the deposit with the escrow
        uint256 expTime = block.timestamp + depositExpirationPeriod;
        GatedMintEscrow(escrow).handleDepositReceived(depositId, by, to, assets, expTime);

        // Emit a custom event for the pending deposit
        emit DepositPending(depositId, by, to, assets);
    }

    /*//////////////////////////////////////////////////////////////
                            MINT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mint shares for an accepted deposit (called by Escrow)
     * @param recipient The recipient of shares
     * @param assetAmount The asset amount
     */
    function mintShares(address recipient, uint256 assetAmount) external {
        // Only escrow can call this
        if (msg.sender != escrow) revert NotEscrow();

        // Calculate shares based on current exchange rate
        uint256 shares = previewDeposit(assetAmount);

        // Mint shares to the recipient
        _mint(recipient, shares);
    }

    /**
     * @notice Mint shares for a batch of accepted deposits with equal share pricing
     * @param recipients Array of recipient addresses
     * @param assetAmounts Array of asset amounts aligned with recipients
     * @param totalAssets Total assets in the batch (sum of assetAmounts)
     */
    function batchMintShares(address[] calldata recipients, uint256[] calldata assetAmounts, uint256 totalAssets)
        external
    {
        // Only escrow can call this
        if (msg.sender != escrow) revert NotEscrow();

        // Validate array lengths match
        if (recipients.length != assetAmounts.length) {
            revert InvalidArrayLengths();
        }

        // Calculate total shares based on the sum of all assets in the batch
        // This ensures all deposits get the same exchange rate
        uint256 totalShares = previewDeposit(totalAssets);

        // Determine shares to be minted for each recipient
        uint256[] memory sharesToMint = new uint256[](recipients.length);
        for (uint256 i = 0; i < recipients.length;) {
            sharesToMint[i] = previewDeposit(assetAmounts[i]);

            unchecked {
                ++i;
            }
        }

        // Distribute shares proportionally to each recipient based on their contribution
        for (uint256 i = 0; i < recipients.length;) {
            // Mint shares to the recipient
            _mint(recipients[i], sharesToMint[i]);

            unchecked {
                ++i;
            }
        }

        emit BatchSharesMinted(totalAssets, totalShares);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get all pending deposit IDs for a specific user
     * @param user The user address
     * @return Array of deposit IDs that are still pending
     */
    function getUserPendingDeposits(address user) external view returns (bytes32[] memory) {
        uint256 numUserDeposits = userDepositIds[user].length;
        bytes32[] memory userDeposits = new bytes32[](numUserDeposits);
        uint256 count = 0;

        bytes32[] memory allUserDeposits = userDepositIds[user];

        for (uint256 i = 0; i < numUserDeposits;) {
            bytes32 depositId = allUserDeposits[i];

            // Query the escrow for deposit status
            (,,,, GatedMintEscrow.DepositState state) = getDepositDetails(depositId);

            // Only include if state is PENDING
            if (state == GatedMintEscrow.DepositState.PENDING) {
                userDeposits[count] = depositId;
                count++;
            }

            unchecked {
                ++i;
            }
        }

        // Use assembly to resize the array in-place
        assembly {
            mstore(userDeposits, count)
        }

        return userDeposits;
    }

    /**
     * @notice Get details for a specific deposit (from Escrow)
     * @param depositId The unique identifier of the deposit
     * @return depositor The address that initiated the deposit
     * @return recipient The address that will receive shares if approved
     * @return assetAmount The amount of assets deposited
     * @return expirationTime The timestamp after which deposit can be reclaimed
     * @return state The current state of the deposit (0=PENDING, 1=ACCEPTED, 2=REFUNDED)
     */
    function getDepositDetails(bytes32 depositId)
        public
        view
        returns (
            address depositor,
            address recipient,
            uint256 assetAmount,
            uint256 expirationTime,
            GatedMintEscrow.DepositState state
        )
    {
        GatedMintEscrow.PendingDeposit memory deposit = GatedMintEscrow(escrow).getPendingDeposit(depositId);
        return (deposit.depositor, deposit.recipient, deposit.assetAmount, deposit.expirationTime, deposit.state);
    }
}
