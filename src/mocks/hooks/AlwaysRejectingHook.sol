// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IHook} from "../../hooks/IHook.sol";

/**
 * @title AlwaysRejectingHook
 * @notice Mock hook that always rejects all operations with a custom message for testing
 */
contract AlwaysRejectingHook is IHook {
    string public rejectMessage;

    /**
     * @notice Constructor to set the rejection message
     * @param _message The message to return when rejecting operations
     */
    constructor(string memory _message) {
        rejectMessage = _message;
    }

    /**
     * @notice Always rejects deposit operations
     * @return HookOutput with approved=false and the rejection message
     */
    function onBeforeDeposit(address, address, uint256, address) external view returns (HookOutput memory) {
        return HookOutput(false, rejectMessage);
    }

    /**
     * @notice Always rejects withdraw operations
     * @return HookOutput with approved=false and the rejection message
     */
    function onBeforeWithdraw(address, address, uint256, address, address) external view returns (HookOutput memory) {
        return HookOutput(false, rejectMessage);
    }

    /**
     * @notice Always rejects transfer operations
     * @return HookOutput with approved=false and the rejection message
     */
    function onBeforeTransfer(address, address, address, uint256) external view returns (HookOutput memory) {
        return HookOutput(false, rejectMessage);
    }

    /**
     * @notice Returns the human readable name of this hook
     * @return Hook name
     */
    function name() external pure returns (string memory) {
        return "AlwaysRejectingHook";
    }

    /**
     * @notice Returns the unique identifier for this hook
     * @return bytes32 The hook identifier
     */
    function hookId() external pure returns (bytes32) {
        return keccak256("AlwaysRejectingHook");
    }
}
