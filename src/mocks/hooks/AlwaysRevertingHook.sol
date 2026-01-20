// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IHook} from "../../hooks/IHook.sol";

/**
 * @title AlwaysRevertingHook
 * @notice Mock hook that always reverts with a custom error message for testing error handling
 */
contract AlwaysRevertingHook is IHook {
    string public revertMessage;

    /**
     * @notice Constructor to set the revert message
     * @param _message The message to revert with
     */
    constructor(string memory _message) {
        revertMessage = _message;
    }

    /**
     * @notice Always reverts on deposit operations
     * @dev This function will never return successfully
     */
    function onBeforeDeposit(address, address, uint256, address) external view returns (HookOutput memory) {
        revert(revertMessage);
    }

    /**
     * @notice Always reverts on withdraw operations
     * @dev This function will never return successfully
     */
    function onBeforeWithdraw(address, address, uint256, address, address) external view returns (HookOutput memory) {
        revert(revertMessage);
    }

    /**
     * @notice Always reverts on transfer operations
     * @dev This function will never return successfully
     */
    function onBeforeTransfer(address, address, address, uint256) external view returns (HookOutput memory) {
        revert(revertMessage);
    }

    /**
     * @notice Returns the human readable name of this hook
     * @return Hook name
     */
    function name() external pure returns (string memory) {
        return "AlwaysRevertingHook";
    }

    /**
     * @notice Returns the unique identifier for this hook
     * @return bytes32 The hook identifier
     */
    function hookId() external pure returns (bytes32) {
        return keccak256("AlwaysRevertingHook");
    }
}
