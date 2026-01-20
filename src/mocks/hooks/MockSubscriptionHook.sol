// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BaseHook} from "../../hooks/BaseHook.sol";
import {IHook} from "../../hooks/IHook.sol";

/**
 * @title MockSubscriptionHook
 * @notice Mock implementation of a subscription hook for testing
 */
contract MockSubscriptionHook is BaseHook {
    // Subscription status
    bool public subscriptionsOpen; // Whether subscriptions are open
    bool public enforceApproval; // Whether to enforce approval

    // Approved subscribers
    mapping(address => bool) public isSubscriber;

    // Events
    event SubscriberStatusChanged(address indexed subscriber, bool indexed approved);
    event SubscriptionStatusChanged(bool indexed open);
    event ApprovalEnforcementChanged(bool indexed enforced);
    event BatchSubscribersChanged(uint256 count, bool status);

    // Errors
    error Unauthorized();
    error InvalidArrayLength();

    /**
     * @notice Constructor
     * @param _manager Address of the manager
     * @param _enforceApproval Whether to enforce approval
     * @param _subscriptionsOpen Whether subscriptions are open
     */
    constructor(address _manager, bool _enforceApproval, bool _subscriptionsOpen) BaseHook("MockSubscriptionHook") {
        manager = _manager;
        enforceApproval = _enforceApproval;
        subscriptionsOpen = _subscriptionsOpen;
    }

    // Manager address that can configure the subscription rules
    address public manager;

    /**
     * @notice Set subscriber status
     * @param subscriber Address of the subscriber
     * @param status Whether the subscriber is approved
     */
    function setSubscriber(address subscriber, bool status) external {
        if (msg.sender != manager) revert Unauthorized();
        isSubscriber[subscriber] = status;
        emit SubscriberStatusChanged(subscriber, status);
    }

    /**
     * @notice Set subscription status
     * @param open Whether subscriptions are open
     */
    function setSubscriptionStatus(bool open) external {
        if (msg.sender != manager) revert Unauthorized();
        subscriptionsOpen = open;
        emit SubscriptionStatusChanged(open);
    }

    /**
     * @notice Set whether to enforce approval
     * @param enforce Whether to enforce approval
     */
    function setEnforceApproval(bool enforce) external {
        if (msg.sender != manager) revert Unauthorized();
        enforceApproval = enforce;
        emit ApprovalEnforcementChanged(enforce);
    }

    /**
     * @notice Batch set subscriber statuses
     * @param subscribers Array of subscriber addresses
     * @param status Whether the subscribers are approved
     */
    function batchSetSubscribers(address[] calldata subscribers, bool status) external {
        if (msg.sender != manager) revert Unauthorized();

        uint256 length = subscribers.length;
        if (length == 0) revert InvalidArrayLength();

        for (uint256 i = 0; i < length; i++) {
            isSubscriber[subscribers[i]] = status;
            emit SubscriberStatusChanged(subscribers[i], status);
        }

        emit BatchSubscribersChanged(length, status);
    }

    /**
     * @notice Hook called before deposit
     * @param receiver Address of the receiver
     * @return output Hook output
     */
    function onBeforeDeposit(address, address, uint256, address receiver)
        public
        view
        override
        returns (IHook.HookOutput memory output)
    {
        // First check if subscriptions are open
        if (!subscriptionsOpen) {
            return IHook.HookOutput({approved: false, reason: "Subscriptions are closed"});
        }

        // Then check if user is approved (if enforcement is enabled)
        if (enforceApproval && !isSubscriber[receiver]) {
            return IHook.HookOutput({approved: false, reason: "Address is not approved for subscription"});
        }

        // All checks passed
        return IHook.HookOutput({approved: true, reason: ""});
    }
}
