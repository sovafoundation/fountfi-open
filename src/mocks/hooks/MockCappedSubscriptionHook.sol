// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {MockHook} from "./MockHook.sol";
import {IHook} from "../../hooks/IHook.sol";

/**
 * @title MockCappedSubscriptionHook
 * @notice Mock hook that implements subscription caps
 */
contract MockCappedSubscriptionHook is MockHook {
    uint256 public maxSubscriptionSize;
    mapping(address => uint256) public subscriptions;
    uint256 public totalSubscriptions;

    constructor(uint256 _maxSubscriptionSize, bool initialApprove, string memory rejectReason)
        MockHook(initialApprove, rejectReason)
    {
        maxSubscriptionSize = _maxSubscriptionSize;
    }

    function setMaxSubscriptionSize(uint256 _maxSubscriptionSize) external {
        maxSubscriptionSize = _maxSubscriptionSize;
    }

    function onBeforeDeposit(address token, address user, uint256 assets, address receiver)
        public
        override
        returns (IHook.HookOutput memory)
    {
        emit HookCalled("deposit", token, user, assets, receiver);

        // Check if subscription would exceed max size
        if (totalSubscriptions + assets > maxSubscriptionSize) {
            return IHook.HookOutput({approved: false, reason: "Subscription would exceed maximum capacity"});
        }

        // If we get here, approve the operation
        subscriptions[receiver] += assets;
        totalSubscriptions += assets;

        return IHook.HookOutput({approved: true, reason: ""});
    }

    function onBeforeWithdraw(address token, address by, uint256 assets, address to, address owner)
        public
        override
        returns (IHook.HookOutput memory)
    {
        emit WithdrawHookCalled(token, by, assets, to, owner);

        // Update subscription amounts
        if (subscriptions[owner] >= assets) {
            subscriptions[owner] -= assets;
            totalSubscriptions -= assets;
        }

        // Return success instead of calling super which may not be properly implemented
        return IHook.HookOutput({approved: approveOperations, reason: approveOperations ? "" : rejectReason});
    }
}
