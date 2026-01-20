// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {ERC4626} from "solady/tokens/ERC4626.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";

import {IHook} from "../hooks/IHook.sol";
import {IStrategy} from "../strategy/IStrategy.sol";
import {ItRWA} from "./ItRWA.sol";

import {Conduit} from "../conduit/Conduit.sol";
import {RoleManaged} from "../auth/RoleManaged.sol";
import {IRegistry} from "../registry/IRegistry.sol";

/**
 * @title tRWA
 * @notice Tokenized Real World Asset (tRWA) inheriting ERC4626 standard
 * @dev Each token represents a share in the underlying real-world fund
 */
contract tRWA is ERC4626, ItRWA, ReentrancyGuard {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for address;

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error HookCheckFailed(string reason);
    error NotStrategyAdmin();
    error HookAddressZero();
    error ReorderInvalidLength();
    error ReorderIndexOutOfBounds();
    error ReorderDuplicateIndex();
    error HookHasProcessedOperations();
    error HookIndexOutOfBounds();
    error InvalidDecimals();

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    // Events for operation hooks
    event HookAdded(bytes32 indexed operationType, address indexed hookAddress, uint256 index);
    event HookRemoved(bytes32 indexed operationType, address indexed hookAddress);
    event HooksReordered(bytes32 indexed operationType, uint256[] newIndices);

    /*//////////////////////////////////////////////////////////////
                            TOKEN STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Internal storage for token metadata
    string private _symbol;
    string private _name;
    address private immutable _asset;
    uint8 private immutable _assetDecimals;

    /// @notice The strategy contract
    address public immutable strategy;

    /*//////////////////////////////////////////////////////////////
                            HOOK STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Operation type identifiers
    bytes32 public constant OP_DEPOSIT = keccak256("DEPOSIT_OPERATION");
    bytes32 public constant OP_WITHDRAW = keccak256("WITHDRAW_OPERATION");
    bytes32 public constant OP_TRANSFER = keccak256("TRANSFER_OPERATION");

    /// @notice Hook information structure
    struct HookInfo {
        IHook hook;
        uint256 addedAtBlock;
    }

    /// @notice Mapping of operation type to hook information
    mapping(bytes32 => HookInfo[]) public operationHooks;

    /// @notice Mapping of operation type to the last block number it was executed
    mapping(bytes32 => uint256) public lastExecutedBlock;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Contract constructor
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param asset_ Asset address
     * @param assetDecimals_ Decimals of the asset token
     * @param strategy_ Strategy address
     */
    constructor(string memory name_, string memory symbol_, address asset_, uint8 assetDecimals_, address strategy_) {
        // Validate configuration parameters
        if (asset_ == address(0)) revert InvalidAddress();
        if (strategy_ == address(0)) revert InvalidAddress();
        if (assetDecimals_ > _DEFAULT_UNDERLYING_DECIMALS) revert InvalidDecimals();

        _name = name_;
        _symbol = symbol_;
        _asset = asset_;
        _assetDecimals = assetDecimals_;
        strategy = strategy_;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the name of the token
     * @return Name of the token
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @notice Returns the symbol of the token
     * @return Symbol of the token
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @notice Returns the asset of the token
     * @return Asset of the token
     */
    function asset() public view virtual override(ERC4626, ItRWA) returns (address) {
        return _asset;
    }

    /*//////////////////////////////////////////////////////////////
                    ERC4626 OVERRIDE VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns the decimals of the underlying asset token.
     */
    function _underlyingDecimals() internal view virtual override returns (uint8) {
        return _assetDecimals;
    }

    /**
     * @dev Returns the offset to adjust share decimals relative to asset decimals.
     * Ensures that `_underlyingDecimals() + _decimalsOffset()` equals `decimals()` (18 for tRWA shares).
     */
    function _decimalsOffset() internal view virtual override returns (uint8) {
        return _DEFAULT_UNDERLYING_DECIMALS - _assetDecimals;
    }

    /**
     * @notice Returns the total amount of the underlying asset managed by the Vault.
     * @dev This value is expected by the base ERC4626 implementation to be in terms of asset's native decimals.
     * @return Total assets in terms of _asset
     */
    function totalAssets() public view override returns (uint256) {
        // Use the strategy's balance which implements price-per-share calculation
        return IStrategy(strategy).balance();
    }

    /*//////////////////////////////////////////////////////////////
                    ERC4626 OVERRIDE LOGIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit assets into the token
     * @param by Address of the sender
     * @param to Address of the receiver
     * @param assets Amount of assets to deposit
     * @param shares Amount of shares to mint
     */
    function _deposit(address by, address to, uint256 assets, uint256 shares) internal virtual override nonReentrant {
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

        // Update last executed block for this operation type if hooks were called
        if (opHooks.length > 0) {
            lastExecutedBlock[OP_DEPOSIT] = block.number;
        }

        Conduit(IRegistry(RoleManaged(strategy).registry()).conduit()).collectDeposit(asset(), by, strategy, assets);

        _mint(to, shares);
        _afterDeposit(assets, shares);

        emit Deposit(by, to, assets, shares);
    }

    /**
     * @notice Withdraw assets from the token
     * @param by Address of the sender
     * @param to Address of the receiver
     * @param owner Address of the owner
     * @param assets Amount of assets to withdraw
     * @param shares Amount of shares to withdraw
     */
    function _withdraw(address by, address to, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
        nonReentrant
    {
        if (by != owner) _spendAllowance(owner, by, shares);
        _beforeWithdraw(assets, shares);
        _burn(owner, shares);

        // Get assets from strategy
        _collect(assets);

        // Call hooks after state changes but before final transfer
        HookInfo[] storage opHooks = operationHooks[OP_WITHDRAW];
        for (uint256 i = 0; i < opHooks.length;) {
            IHook.HookOutput memory hookOutput = opHooks[i].hook.onBeforeWithdraw(address(this), by, assets, to, owner);
            if (!hookOutput.approved) {
                revert HookCheckFailed(hookOutput.reason);
            }

            unchecked {
                ++i;
            }
        }

        // Update last executed block for this operation type if hooks were called
        if (opHooks.length > 0) {
            lastExecutedBlock[OP_WITHDRAW] = block.number;
        }

        // Transfer the assets to the recipient
        _asset.safeTransfer(to, assets);

        emit Withdraw(by, to, owner, assets, shares);
    }

    /*//////////////////////////////////////////////////////////////
                        HOOK MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds a new operation hook to the end of the list for a specific operation type.
     * @dev Callable only by the strategy contract.
     * @param operationType The type of operation this hook applies to (e.g., OP_DEPOSIT).
     * @param newHookAddress The address of the new hook contract to add.
     */
    function addOperationHook(bytes32 operationType, address newHookAddress) external onlyStrategy {
        if (newHookAddress == address(0)) revert HookAddressZero();

        HookInfo memory newHookInfo = HookInfo({hook: IHook(newHookAddress), addedAtBlock: block.number});

        HookInfo[] storage opHooks = operationHooks[operationType];
        opHooks.push(newHookInfo);
        emit HookAdded(operationType, newHookAddress, opHooks.length - 1);
    }

    /**
     * @notice Removes an operation hook from a specific operation type.
     * @dev Callable only by the strategy contract. Can only remove hooks that haven't processed operations.
     * @param operationType The type of operation to remove the hook from.
     * @param index The index of the hook to remove.
     */
    function removeOperationHook(bytes32 operationType, uint256 index) external onlyStrategy nonReentrant {
        HookInfo[] storage opHooks = operationHooks[operationType];
        uint256 opHooksLen = opHooks.length;

        if (index >= opHooksLen) revert HookIndexOutOfBounds();

        // Cache the hook info to avoid multiple storage reads
        HookInfo storage hookToRemove = opHooks[index];

        // Check if this hook was added before the last execution of this operation type
        if (hookToRemove.addedAtBlock <= lastExecutedBlock[operationType]) {
            revert HookHasProcessedOperations();
        }

        address removedHookAddress = address(hookToRemove.hook);

        // Remove by swapping with last element and popping (more gas efficient)
        if (index != opHooksLen - 1) {
            opHooks[index] = opHooks[opHooksLen - 1];
        }
        opHooks.pop();

        emit HookRemoved(operationType, removedHookAddress);
    }

    /**
     * @notice Reorders the existing operation hooks for a specific operation type.
     * @dev Callable only by the strategy contract. The newOrderIndices array must be a permutation
     *      of the current hook indices (0 to length-1) for the given operation type.
     * @param operationType The type of operation for which hooks are being reordered.
     * @param newOrderIndices An array where newOrderIndices[i] specifies the OLD index of the hook
     *                        that should now be at NEW position i.
     */
    function reorderOperationHooks(bytes32 operationType, uint256[] calldata newOrderIndices)
        external
        onlyStrategy
        nonReentrant
    {
        HookInfo[] storage opTypeHooks = operationHooks[operationType];
        uint256 numHooks = opTypeHooks.length;
        if (newOrderIndices.length != numHooks) revert ReorderInvalidLength();

        // Create a temporary copy of all hooks
        HookInfo[] memory tempHooks = new HookInfo[](numHooks);
        for (uint256 i = 0; i < numHooks;) {
            tempHooks[i] = opTypeHooks[i];

            unchecked {
                ++i;
            }
        }

        bool[] memory indexSeen = new bool[](numHooks);

        // Reorder by copying from temp array back to storage
        for (uint256 i = 0; i < numHooks;) {
            uint256 oldIndex = newOrderIndices[i];
            if (oldIndex >= numHooks) revert ReorderIndexOutOfBounds();
            if (indexSeen[oldIndex]) revert ReorderDuplicateIndex();

            opTypeHooks[i] = tempHooks[oldIndex];
            indexSeen[oldIndex] = true;

            unchecked {
                ++i;
            }
        }

        emit HooksReordered(operationType, newOrderIndices);
    }

    /*//////////////////////////////////////////////////////////////
                            HOOK VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets all registered hook addresses for a specific operation type.
     * @param operationType The type of operation.
     * @return An array of hook contract addresses.
     */
    function getHooksForOperation(bytes32 operationType) external view returns (address[] memory) {
        HookInfo[] storage opTypeHooks = operationHooks[operationType];
        address[] memory hookAddresses = new address[](opTypeHooks.length);
        for (uint256 i = 0; i < opTypeHooks.length;) {
            hookAddresses[i] = address(opTypeHooks[i].hook);

            unchecked {
                ++i;
            }
        }
        return hookAddresses;
    }

    /**
     * @notice Gets detailed information about all hooks for a specific operation type.
     * @param operationType The type of operation.
     * @return hookInfos Array of HookInfo structs containing hook details.
     */
    function getHookInfoForOperation(bytes32 operationType) external view returns (HookInfo[] memory) {
        return operationHooks[operationType];
    }

    /*//////////////////////////////////////////////////////////////
                        ERC20 HOOK OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Hook that is called before any token transfer, including mints and burns.
     * We use this to apply OP_TRANSFER hooks.
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        super._beforeTokenTransfer(from, to, amount); // Call to parent ERC20/ERC4626 _beforeTokenTransfer if it exists

        HookInfo[] storage opHooks = operationHooks[OP_TRANSFER];
        if (opHooks.length > 0) {
            // Optimization to save gas if no hooks registered for OP_TRANSFER
            for (uint256 i = 0; i < opHooks.length;) {
                IHook.HookOutput memory hookOutput = opHooks[i].hook.onBeforeTransfer(address(this), from, to, amount);
                if (!hookOutput.approved) {
                    revert HookCheckFailed(hookOutput.reason);
                }

                unchecked {
                    ++i;
                }
            }

            // Update last executed block for this operation type
            lastExecutedBlock[OP_TRANSFER] = block.number;
        }
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Collect assets from the strategy
     * @param assets The amount of assets to collect
     */
    function _collect(uint256 assets) internal {
        _asset.safeTransferFrom(strategy, address(this), assets);
    }

    modifier onlyStrategy() {
        if (msg.sender != strategy) revert NotStrategyAdmin();
        _;
    }
}
