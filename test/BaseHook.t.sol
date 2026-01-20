// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {BaseHook} from "../src/hooks/BaseHook.sol";
import {IHook} from "../src/hooks/IHook.sol";

/**
 * @title ConcreteHook
 * @notice Concrete implementation of BaseHook for testing
 */
contract ConcreteHook is BaseHook {
    bool private _shouldApprove;
    string private _rejectionReason;

    /**
     * @notice Constructor
     * @param name_ The name of the hook
     * @param shouldApprove_ Whether the hook should approve operations
     * @param rejectionReason_ The reason for rejection if not approving
     */
    constructor(string memory name_, bool shouldApprove_, string memory rejectionReason_) BaseHook(name_) {
        _shouldApprove = shouldApprove_;
        _rejectionReason = rejectionReason_;
    }

    /**
     * @notice Override to test custom behavior
     */
    function onBeforeDeposit(address token, address user, uint256 assets, address receiver)
        public
        view
        override
        returns (IHook.HookOutput memory)
    {
        // Custom logic that uses the parameters to ensure they're passed correctly
        if (token == address(0) || user == address(0) || assets == 0 || receiver == address(0)) {
            return IHook.HookOutput({approved: false, reason: "Invalid parameters"});
        }

        return IHook.HookOutput({approved: _shouldApprove, reason: _shouldApprove ? "" : _rejectionReason});
    }

    /**
     * @notice Override to test custom behavior
     */
    function onBeforeWithdraw(address token, address by, uint256 assets, address to, address owner)
        public
        view
        override
        returns (IHook.HookOutput memory)
    {
        // Custom logic that uses the parameters to ensure they're passed correctly
        if (token == address(0) || by == address(0) || assets == 0 || to == address(0) || owner == address(0)) {
            return IHook.HookOutput({approved: false, reason: "Invalid parameters"});
        }

        return IHook.HookOutput({approved: _shouldApprove, reason: _shouldApprove ? "" : _rejectionReason});
    }

    /**
     * @notice Override to test custom behavior
     */
    function onBeforeTransfer(address token, address from, address to, uint256 amount)
        public
        view
        override
        returns (IHook.HookOutput memory)
    {
        // Custom logic that uses the parameters to ensure they're passed correctly
        if (token == address(0) || from == address(0) || to == address(0) || amount == 0) {
            return IHook.HookOutput({approved: false, reason: "Invalid parameters"});
        }

        return IHook.HookOutput({approved: _shouldApprove, reason: _shouldApprove ? "" : _rejectionReason});
    }

    /**
     * @notice Helper to test configuration
     */
    function getShouldApprove() external view returns (bool) {
        return _shouldApprove;
    }

    /**
     * @notice Helper to test configuration
     */
    function getRejectionReason() external view returns (string memory) {
        return _rejectionReason;
    }
}

/**
 * @title DefaultBaseHook
 * @notice Implementation of BaseHook that doesn't override methods
 */
contract DefaultBaseHook is BaseHook {
    constructor(string memory name_) BaseHook(name_) {}
}

/**
 * @title BaseHookTest
 * @notice Comprehensive tests for BaseHook to achieve 100% coverage
 */
contract BaseHookTest is Test {
    // Test instances
    ConcreteHook public approveHook;
    ConcreteHook public rejectHook;
    DefaultBaseHook public defaultHook;

    // Test addresses
    address public constant TOKEN = address(0x1);
    address public constant USER = address(0x2);
    address public constant RECEIVER = address(0x3);
    address public constant OWNER = address(0x4);
    uint256 public constant AMOUNT = 1000;

    function setUp() public {
        // Create hook implementations
        approveHook = new ConcreteHook("ApproveHook", true, "");
        rejectHook = new ConcreteHook("RejectHook", false, "Operation rejected by hook");
        defaultHook = new DefaultBaseHook("DefaultHook");
    }

    /*//////////////////////////////////////////////////////////////
                              NAME TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Name() public view {
        // Test that name returns the correct name
        assertEq(approveHook.name(), "ApproveHook", "name should return the name");
        assertEq(rejectHook.name(), "RejectHook", "name should return the name");
        assertEq(defaultHook.name(), "DefaultHook", "name should return the name");
    }

    /*//////////////////////////////////////////////////////////////
                              ID TESTS
    //////////////////////////////////////////////////////////////*/

    function test_HookId() public view {
        // Test that hookId returns the correct ID (keccak256 hash of the name)
        bytes32 expectedApproveId = keccak256(abi.encodePacked("ApproveHook", address(approveHook)));
        bytes32 expectedRejectId = keccak256(abi.encodePacked("RejectHook", address(rejectHook)));
        bytes32 expectedDefaultId = keccak256(abi.encodePacked("DefaultHook", address(defaultHook)));

        assertEq(approveHook.hookId(), expectedApproveId, "Hook ID should be hash of name and address");
        assertEq(rejectHook.hookId(), expectedRejectId, "Hook ID should be hash of name and address");
        assertEq(defaultHook.hookId(), expectedDefaultId, "Hook ID should be hash of name and address");
    }

    /*//////////////////////////////////////////////////////////////
                       DEFAULT OPERATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_DefaultOnBeforeDeposit() public {
        // Test that the default implementation always returns approved
        IHook.HookOutput memory output = defaultHook.onBeforeDeposit(TOKEN, USER, AMOUNT, RECEIVER);
        assertTrue(output.approved, "Default onBeforeDeposit should approve");
        assertEq(output.reason, "", "Default onBeforeDeposit should have empty reason");
    }

    function test_DefaultOnBeforeWithdraw() public {
        // Test that the default implementation always returns approved
        IHook.HookOutput memory output = defaultHook.onBeforeWithdraw(TOKEN, USER, AMOUNT, RECEIVER, OWNER);
        assertTrue(output.approved, "Default onBeforeWithdraw should approve");
        assertEq(output.reason, "", "Default onBeforeWithdraw should have empty reason");
    }

    function test_DefaultOnBeforeTransfer() public {
        // Test that the default implementation always returns approved
        IHook.HookOutput memory output = defaultHook.onBeforeTransfer(TOKEN, USER, RECEIVER, AMOUNT);
        assertTrue(output.approved, "Default onBeforeTransfer should approve");
        assertEq(output.reason, "", "Default onBeforeTransfer should have empty reason");
    }

    /*//////////////////////////////////////////////////////////////
                      CONCRETE DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ConcreteOnBeforeDeposit_Approve() public view {
        // Test approving hook
        IHook.HookOutput memory output = approveHook.onBeforeDeposit(TOKEN, USER, AMOUNT, RECEIVER);
        assertTrue(output.approved, "Concrete onBeforeDeposit should approve when configured to");
        assertEq(output.reason, "", "Concrete onBeforeDeposit should have empty reason when approving");
    }

    function test_ConcreteOnBeforeDeposit_Reject() public view {
        // Test rejecting hook
        IHook.HookOutput memory output = rejectHook.onBeforeDeposit(TOKEN, USER, AMOUNT, RECEIVER);
        assertFalse(output.approved, "Concrete onBeforeDeposit should reject when configured to");
        assertEq(output.reason, "Operation rejected by hook", "Concrete onBeforeDeposit should have rejection reason");
    }

    function test_ConcreteOnBeforeDeposit_InvalidParams() public view {
        // Test with invalid parameters
        IHook.HookOutput memory output = approveHook.onBeforeDeposit(address(0), USER, AMOUNT, RECEIVER);
        assertFalse(output.approved, "Should reject with zero token address");
        assertEq(output.reason, "Invalid parameters", "Should have appropriate error message");

        output = approveHook.onBeforeDeposit(TOKEN, address(0), AMOUNT, RECEIVER);
        assertFalse(output.approved, "Should reject with zero user address");
        assertEq(output.reason, "Invalid parameters", "Should have appropriate error message");

        output = approveHook.onBeforeDeposit(TOKEN, USER, 0, RECEIVER);
        assertFalse(output.approved, "Should reject with zero amount");
        assertEq(output.reason, "Invalid parameters", "Should have appropriate error message");

        output = approveHook.onBeforeDeposit(TOKEN, USER, AMOUNT, address(0));
        assertFalse(output.approved, "Should reject with zero receiver address");
        assertEq(output.reason, "Invalid parameters", "Should have appropriate error message");
    }

    /*//////////////////////////////////////////////////////////////
                     CONCRETE WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ConcreteOnBeforeWithdraw_Approve() public view {
        // Test approving hook
        IHook.HookOutput memory output = approveHook.onBeforeWithdraw(TOKEN, USER, AMOUNT, RECEIVER, OWNER);
        assertTrue(output.approved, "Concrete onBeforeWithdraw should approve when configured to");
        assertEq(output.reason, "", "Concrete onBeforeWithdraw should have empty reason when approving");
    }

    function test_ConcreteOnBeforeWithdraw_Reject() public view {
        // Test rejecting hook
        IHook.HookOutput memory output = rejectHook.onBeforeWithdraw(TOKEN, USER, AMOUNT, RECEIVER, OWNER);
        assertFalse(output.approved, "Concrete onBeforeWithdraw should reject when configured to");
        assertEq(output.reason, "Operation rejected by hook", "Concrete onBeforeWithdraw should have rejection reason");
    }

    function test_ConcreteOnBeforeWithdraw_InvalidParams() public view {
        // Test with invalid parameters
        IHook.HookOutput memory output = approveHook.onBeforeWithdraw(address(0), USER, AMOUNT, RECEIVER, OWNER);
        assertFalse(output.approved, "Should reject with zero token address");
        assertEq(output.reason, "Invalid parameters", "Should have appropriate error message");

        output = approveHook.onBeforeWithdraw(TOKEN, address(0), AMOUNT, RECEIVER, OWNER);
        assertFalse(output.approved, "Should reject with zero by address");
        assertEq(output.reason, "Invalid parameters", "Should have appropriate error message");

        output = approveHook.onBeforeWithdraw(TOKEN, USER, 0, RECEIVER, OWNER);
        assertFalse(output.approved, "Should reject with zero amount");
        assertEq(output.reason, "Invalid parameters", "Should have appropriate error message");

        output = approveHook.onBeforeWithdraw(TOKEN, USER, AMOUNT, address(0), OWNER);
        assertFalse(output.approved, "Should reject with zero to address");
        assertEq(output.reason, "Invalid parameters", "Should have appropriate error message");

        output = approveHook.onBeforeWithdraw(TOKEN, USER, AMOUNT, RECEIVER, address(0));
        assertFalse(output.approved, "Should reject with zero owner address");
        assertEq(output.reason, "Invalid parameters", "Should have appropriate error message");
    }

    /*//////////////////////////////////////////////////////////////
                     CONCRETE TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ConcreteOnBeforeTransfer_Approve() public view {
        // Test approving hook
        IHook.HookOutput memory output = approveHook.onBeforeTransfer(TOKEN, USER, RECEIVER, AMOUNT);
        assertTrue(output.approved, "Concrete onBeforeTransfer should approve when configured to");
        assertEq(output.reason, "", "Concrete onBeforeTransfer should have empty reason when approving");
    }

    function test_ConcreteOnBeforeTransfer_Reject() public view {
        // Test rejecting hook
        IHook.HookOutput memory output = rejectHook.onBeforeTransfer(TOKEN, USER, RECEIVER, AMOUNT);
        assertFalse(output.approved, "Concrete onBeforeTransfer should reject when configured to");
        assertEq(output.reason, "Operation rejected by hook", "Concrete onBeforeTransfer should have rejection reason");
    }

    function test_ConcreteOnBeforeTransfer_InvalidParams() public view {
        // Test with invalid parameters
        IHook.HookOutput memory output = approveHook.onBeforeTransfer(address(0), USER, RECEIVER, AMOUNT);
        assertFalse(output.approved, "Should reject with zero token address");
        assertEq(output.reason, "Invalid parameters", "Should have appropriate error message");

        output = approveHook.onBeforeTransfer(TOKEN, address(0), RECEIVER, AMOUNT);
        assertFalse(output.approved, "Should reject with zero from address");
        assertEq(output.reason, "Invalid parameters", "Should have appropriate error message");

        output = approveHook.onBeforeTransfer(TOKEN, USER, address(0), AMOUNT);
        assertFalse(output.approved, "Should reject with zero to address");
        assertEq(output.reason, "Invalid parameters", "Should have appropriate error message");

        output = approveHook.onBeforeTransfer(TOKEN, USER, RECEIVER, 0);
        assertFalse(output.approved, "Should reject with zero amount");
        assertEq(output.reason, "Invalid parameters", "Should have appropriate error message");
    }
}
