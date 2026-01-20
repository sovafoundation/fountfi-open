// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IHook} from "../../hooks/IHook.sol";

/**
 * @title AlwaysApprovingHook
 * @notice Mock hook that always approves all operations for testing
 */
contract AlwaysApprovingHook is IHook {
    /**
     * @notice Always approves deposit operations
     * @return HookOutput with approved=true and empty message
     */
    function onBeforeDeposit(address, address, uint256, address) external pure returns (HookOutput memory) {
        return HookOutput(true, "");
    }

    /**
     * @notice Always approves withdraw operations
     * @return HookOutput with approved=true and empty message
     */
    function onBeforeWithdraw(address, address, uint256, address, address) external pure returns (HookOutput memory) {
        return HookOutput(true, "");
    }

    /**
     * @notice Always approves transfer operations
     * @return HookOutput with approved=true and empty message
     */
    function onBeforeTransfer(address, address, address, uint256) external pure returns (HookOutput memory) {
        return HookOutput(true, "");
    }

    /**
     * @notice Returns the human readable name of this hook
     * @return Hook name
     */
    function name() external pure returns (string memory) {
        return "AlwaysApprovingHook";
    }

    /**
     * @notice Returns the unique identifier for this hook
     * @return bytes32 The hook identifier
     */
    function hookId() external pure returns (bytes32) {
        return keccak256("AlwaysApprovingHook");
    }
}
