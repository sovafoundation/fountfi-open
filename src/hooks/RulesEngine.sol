// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {RoleManaged} from "../auth/RoleManaged.sol";
import {BaseHook} from "./BaseHook.sol";
import {IHook} from "./IHook.sol";

/**
 * @title RulesEngine
 * @notice Implementation of a hook that manages and evaluates a collection of sub-hooks
 * @dev Manages a collection of hooks that determine if operations are allowed
 */
contract RulesEngine is BaseHook, RoleManaged {
    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidHookAddress();
    error HookAlreadyExists(bytes32 hookId);
    error HookNotFound(bytes32 hookId);
    error HookEvaluationFailed(bytes32 hookId, bytes4 reasonSelector);

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    // Events
    event HookAdded(bytes32 indexed hookId, address indexed hookAddress, uint256 priority);
    event HookRemoved(bytes32 indexed hookId);
    event HookPriorityChanged(bytes32 indexed hookId, uint256 newPriority);
    event HookEnabled(bytes32 indexed hookId);
    event HookDisabled(bytes32 indexed hookId);

    /*//////////////////////////////////////////////////////////////
                            STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Hook information
    struct HookInfo {
        address hookAddress;
        uint256 priority;
        bool active;
    }

    /// @notice All hooks by ID
    mapping(bytes32 => HookInfo) private _hooks;

    /// @notice All hook IDs
    bytes32[] private _hookIds;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructor
     * @param _roleManager Address of the role manager
     */
    constructor(address _roleManager) BaseHook("RulesEngine-1.0") RoleManaged(_roleManager) {}

    /*//////////////////////////////////////////////////////////////
                            HOOK MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add a new hook to the engine
     * @param hookAddress Address of the hook contract implementing IHook
     * @param priority Priority of the hook (lower numbers execute first)
     * @return hookId Identifier of the added hook
     */
    function addHook(address hookAddress, uint256 priority)
        external
        onlyRoles(roleManager.RULES_ADMIN())
        returns (bytes32)
    {
        // Assuming RULES_ADMIN is appropriate
        if (hookAddress == address(0)) revert InvalidHookAddress();

        // Get hook ID from the hook contract (namehash of its name and version)
        bytes32 id = IHook(hookAddress).hookId();

        if (_hooks[id].hookAddress != address(0)) revert HookAlreadyExists(id);

        _hooks[id] = HookInfo({hookAddress: hookAddress, priority: priority, active: true});

        _hookIds.push(id);
        // TODO: Consider sorting _hookIds here or when retrieving if performance is an issue for many hooks.

        emit HookAdded(id, hookAddress, priority);

        return id;
    }

    /**
     * @notice Remove a hook from the engine
     * @param hookId Identifier of the hook to remove
     */
    function removeHook(bytes32 hookId) external onlyRoles(roleManager.RULES_ADMIN()) {
        if (_hooks[hookId].hookAddress == address(0)) revert HookNotFound(hookId);

        delete _hooks[hookId];

        uint256 hookIdsLength = _hookIds.length;
        for (uint256 i = 0; i < hookIdsLength;) {
            if (_hookIds[i] == hookId) {
                // Only perform assignment if not removing the last element
                if (i != hookIdsLength - 1) {
                    _hookIds[i] = _hookIds[hookIdsLength - 1];
                }
                _hookIds.pop();
                break;
            }

            unchecked {
                ++i;
            }
        }

        emit HookRemoved(hookId);
    }

    /**
     * @notice Change the priority of a hook
     * @param hookId Identifier of the hook
     * @param newPriority New priority for the hook
     */
    function changeHookPriority(bytes32 hookId, uint256 newPriority) external onlyRoles(roleManager.RULES_ADMIN()) {
        HookInfo storage hook = _hooks[hookId];
        if (hook.hookAddress == address(0)) revert HookNotFound(hookId);

        hook.priority = newPriority;

        emit HookPriorityChanged(hookId, newPriority);
    }

    /**
     * @notice Enable a hook
     * @param hookId Identifier of the hook to enable
     */
    function enableHook(bytes32 hookId) external onlyRoles(roleManager.RULES_ADMIN()) {
        HookInfo storage hook = _hooks[hookId];
        if (hook.hookAddress == address(0)) revert HookNotFound(hookId);

        hook.active = true;

        emit HookEnabled(hookId);
    }

    /**
     * @notice Disable a hook
     * @param hookId Identifier of the hook to disable
     */
    function disableHook(bytes32 hookId) external onlyRoles(roleManager.RULES_ADMIN()) {
        HookInfo storage hook = _hooks[hookId];
        if (hook.hookAddress == address(0)) revert HookNotFound(hookId);

        hook.active = false;

        emit HookDisabled(hookId);
    }

    /**
     * @notice Check if a hook is active
     * @param hookId Identifier of the hook
     * @return Whether the hook is active
     */
    function isHookActive(bytes32 hookId) external view returns (bool) {
        return _hooks[hookId].active;
    }

    /**
     * @notice Get all registered hook identifiers
     * @return Array of hook identifiers
     */
    function getAllHookIds() external view returns (bytes32[] memory) {
        return _hookIds;
    }

    /**
     * @notice Get all active hook identifiers, sorted by priority
     * @return Array of hook identifiers
     */
    function getAllActiveHookIdsSorted() public view returns (bytes32[] memory) {
        return _getSortedActiveHookIds();
    }

    /**
     * @notice Get hook address by ID
     * @param hookId Identifier of the hook
     * @return Hook contract address
     */
    function getHookAddress(bytes32 hookId) external view returns (address) {
        return _hooks[hookId].hookAddress;
    }

    /**
     * @notice Get hook priority
     * @param hookId Identifier of the hook
     * @return Priority value
     */
    function getHookPriority(bytes32 hookId) external view returns (uint256) {
        return _hooks[hookId].priority;
    }

    /*//////////////////////////////////////////////////////////////
                            HOOK IMPLEMENTATION (as an aggregate hook)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Evaluate transfer operation against registered hooks
     */
    function onBeforeTransfer(address token, address from, address to, uint256 amount)
        public
        override
        returns (HookOutput memory)
    {
        bytes memory callData = abi.encodeCall(IHook.onBeforeTransfer, (token, from, to, amount));
        return _evaluateSubHooks(callData);
    }

    /**
     * @notice Evaluate deposit operation against registered hooks
     */
    function onBeforeDeposit(address token, address user, uint256 assets, address receiver)
        public
        override
        returns (HookOutput memory)
    {
        bytes memory callData = abi.encodeCall(IHook.onBeforeDeposit, (token, user, assets, receiver));
        return _evaluateSubHooks(callData);
    }

    /**
     * @notice Evaluate withdraw operation against registered hooks
     */
    function onBeforeWithdraw(address token, address user, uint256 assets, address receiver, address owner)
        public
        override
        returns (HookOutput memory)
    {
        bytes memory callData = abi.encodeCall(IHook.onBeforeWithdraw, (token, user, assets, receiver, owner));
        return _evaluateSubHooks(callData);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal method to evaluate an operation against all applicable sub-hooks
     * @param callData Encoded call data for the hook evaluation function (e.g., onBeforeTransfer)
     * @return resultSelector Bytes4 selector indicating success or failure reason
     */
    function _evaluateSubHooks(bytes memory callData) internal returns (IHook.HookOutput memory) {
        bytes32[] memory sortedHookIds = _getSortedActiveHookIds();

        uint256 sortedHookIdsLength = sortedHookIds.length;
        for (uint256 i = 0; i < sortedHookIdsLength;) {
            bytes32 hookId = sortedHookIds[i];
            HookInfo memory hook = _hooks[hookId];

            // Call the sub-hook with the appropriate evaluation function - use call instead of staticcall
            // to allow hooks to modify state (emit events, track interactions, etc.)
            (bool success, bytes memory returnData) = hook.hookAddress.call(callData);

            if (!success) {
                // Sub-hook execution failed (reverted without a known bytes4 selector)
                // Attempt to decode a string reason if possible, otherwise generic failure.
                // This part is tricky as revert reasons are not always returned or standard.
                // For now, let's assume a specific error selector if the call itself fails.
                revert HookEvaluationFailed(hookId, bytes4(0)); // Generic failure selector
            }

            // Decode the hook output from response
            IHook.HookOutput memory hookOutput = abi.decode(returnData, (IHook.HookOutput));

            if (!hookOutput.approved) {
                return hookOutput;
            }

            unchecked {
                ++i;
            }
        }

        // If we made it through all hooks, operation is allowed
        return IHook.HookOutput({approved: true, reason: ""});
    }

    /**
     * @notice Get active hook IDs sorted by priority (lower goes first)
     * @return Sorted array of active hook IDs
     */
    function _getSortedActiveHookIds() private view returns (bytes32[] memory) {
        uint256 activeHooksCount = 0;
        uint256 numHooks = _hookIds.length;
        bytes32[] memory sortedActiveIds = new bytes32[](numHooks);
        uint256 currentIndex = 0;

        // Count active hooks
        for (uint256 i = 0; i < numHooks;) {
            if (_hooks[_hookIds[i]].active) {
                unchecked {
                    activeHooksCount++;
                }
                sortedActiveIds[currentIndex++] = _hookIds[i];
            }

            unchecked {
                ++i;
            }
        }

        // Simple insertion sort by priority on the active hooks
        for (uint256 i = 1; i < activeHooksCount;) {
            bytes32 key = sortedActiveIds[i];
            uint256 keyPriority = _hooks[key].priority;
            uint256 j = i;

            while (j > 0 && _hooks[sortedActiveIds[j - 1]].priority > keyPriority) {
                sortedActiveIds[j] = sortedActiveIds[j - 1];

                unchecked {
                    --j;
                }
            }
            sortedActiveIds[j] = key;

            unchecked {
                ++i;
            }
        }

        // Truncate array length to the actual number of active hooks
        assembly {
            mstore(sortedActiveIds, activeHooksCount)
        }

        return sortedActiveIds;
    }
}
