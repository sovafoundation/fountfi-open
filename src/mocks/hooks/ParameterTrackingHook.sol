// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IHook} from "../../hooks/IHook.sol";

/**
 * @title ParameterTrackingHook
 * @notice Mock hook that tracks all parameters passed to it for testing verification
 */
contract ParameterTrackingHook is IHook {
    enum Operation {
        Deposit,
        Withdraw,
        Transfer
    }

    struct TrackedCall {
        address token;
        address operator;
        Operation operation;
        uint256 assets;
        address receiver;
        address owner;
    }

    TrackedCall[] public calls;

    /**
     * @notice Tracks deposit parameters and returns approval
     * @return HookOutput with approved=true and empty message
     */
    function onBeforeDeposit(address token, address user, uint256 assets, address receiver)
        external
        returns (HookOutput memory)
    {
        calls.push(
            TrackedCall({
                token: token,
                operator: user,
                operation: Operation.Deposit,
                assets: assets,
                receiver: receiver,
                owner: user
            })
        );
        return HookOutput(true, "");
    }

    /**
     * @notice Tracks withdraw parameters and returns approval
     * @return HookOutput with approved=true and empty message
     */
    function onBeforeWithdraw(address token, address by, uint256 assets, address to, address owner)
        external
        returns (HookOutput memory)
    {
        calls.push(
            TrackedCall({
                token: token,
                operator: by,
                operation: Operation.Withdraw,
                assets: assets,
                receiver: to,
                owner: owner
            })
        );
        return HookOutput(true, "");
    }

    /**
     * @notice Tracks transfer parameters and returns approval
     * @return HookOutput with approved=true and empty message
     */
    function onBeforeTransfer(address token, address from, address to, uint256 amount)
        external
        returns (HookOutput memory)
    {
        calls.push(
            TrackedCall({
                token: token,
                operator: from,
                operation: Operation.Transfer,
                assets: amount,
                receiver: to,
                owner: from
            })
        );
        return HookOutput(true, "");
    }

    /**
     * @notice Returns the human readable name of this hook
     * @return Hook name
     */
    function name() external pure returns (string memory) {
        return "ParameterTrackingHook";
    }

    /**
     * @notice Returns the unique identifier for this hook
     * @return bytes32 The hook identifier
     */
    function hookId() external pure returns (bytes32) {
        return keccak256("ParameterTrackingHook");
    }

    /**
     * @notice Returns the number of tracked calls
     * @return uint256 The number of calls tracked
     */
    function getCallCount() external view returns (uint256) {
        return calls.length;
    }

    /**
     * @notice Clears all tracked calls for test cleanup
     */
    function clearCalls() external {
        delete calls;
    }
}
