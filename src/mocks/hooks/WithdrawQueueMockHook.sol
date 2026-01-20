// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {MockHook} from "./MockHook.sol";
import {IHook} from "../../hooks/IHook.sol";

/**
 * @title WithdrawQueueMockHook
 * @notice Mock hook that enables control over withdrawal responses for queue testing
 */
contract WithdrawQueueMockHook is MockHook {
    bool public withdrawalsQueued = false;

    constructor(bool initialApprove, string memory rejectReason) MockHook(initialApprove, rejectReason) {}

    function setWithdrawalsQueued(bool queued) external {
        withdrawalsQueued = queued;
    }

    function onBeforeWithdraw(address token, address by, uint256 assets, address to, address owner)
        public
        override
        returns (IHook.HookOutput memory)
    {
        emit WithdrawHookCalled(token, by, assets, to, owner);

        if (withdrawalsQueued) {
            return IHook.HookOutput({
                approved: false,
                reason: "Direct withdrawals not supported. Withdrawal request created in queue."
            });
        }
        // Return parent class result without using super
        return IHook.HookOutput({approved: approveOperations, reason: approveOperations ? "" : rejectReason});
    }
}
