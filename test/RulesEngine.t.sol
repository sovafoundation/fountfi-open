// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseFountfiTest} from "./BaseFountfiTest.t.sol";
import {RulesEngine} from "../src/hooks/RulesEngine.sol";
import {MockHook} from "../src/mocks/hooks/MockHook.sol";
import {AlwaysRevertingHook} from "../src/mocks/hooks/AlwaysRevertingHook.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {IHook} from "../src/hooks/IHook.sol";
import {RoleManaged} from "../src/auth/RoleManaged.sol";
import {LibRoleManaged} from "../src/auth/LibRoleManaged.sol";

/**
 * @title CustomMockHook
 * @notice Mock hook implementation with customizable name for unique hookId
 */
contract CustomMockHook is MockHook {
    constructor(bool initialApprove, string memory rejectReason, string memory hookName)
        MockHook(initialApprove, rejectReason)
    {
        name = hookName;
    }
}

/**
 * @title OperationSpecificMockHook
 * @notice Mock hook implementation that handles specific operations differently
 */
contract OperationSpecificMockHook is MockHook {
    uint256 private _operationType;

    constructor(uint256 operationType, bool initialApprove, string memory rejectReason)
        MockHook(initialApprove, rejectReason)
    {
        _operationType = operationType;

        // Set a unique name based on operation type to ensure unique hookId
        if (operationType == 1) {
            name = "DepositHook";
        } else if (operationType == 2) {
            name = "WithdrawHook";
        } else if (operationType == 3) {
            name = "TransferHook";
        } else {
            name = "GenericHook";
        }
    }

    // Override the deposit hook if this is a deposit hook
    function onBeforeDeposit(address token, address user, uint256 assets, address receiver)
        external
        override
        returns (IHook.HookOutput memory)
    {
        if (_operationType == 1) {
            // Deposit operation
            emit HookCalled("deposit", token, user, assets, receiver);
            return IHook.HookOutput({approved: true, reason: ""});
        } else {
            // For other operation types, return the default behavior based on approveOperations
            emit HookCalled("deposit", token, user, assets, receiver);
            return IHook.HookOutput({approved: approveOperations, reason: approveOperations ? "" : rejectReason});
        }
    }

    // Override the withdraw hook if this is a withdraw hook
    function onBeforeWithdraw(address token, address by, uint256 assets, address to, address owner)
        external
        override
        returns (IHook.HookOutput memory)
    {
        if (_operationType == 2) {
            // Withdraw operation
            emit WithdrawHookCalled(token, by, assets, to, owner);
            return IHook.HookOutput({approved: true, reason: ""});
        } else {
            // For other operation types, return the default behavior based on approveOperations
            emit WithdrawHookCalled(token, by, assets, to, owner);
            return IHook.HookOutput({approved: approveOperations, reason: approveOperations ? "" : rejectReason});
        }
    }

    // Override the transfer hook if this is a transfer hook
    function onBeforeTransfer(address token, address from, address to, uint256 amount)
        external
        override
        returns (IHook.HookOutput memory)
    {
        if (_operationType == 3) {
            // Transfer operation
            emit TransferHookCalled(token, from, to, amount);
            return IHook.HookOutput({approved: true, reason: ""});
        } else {
            // For other operation types, return the default behavior based on approveOperations
            emit TransferHookCalled(token, from, to, amount);
            return IHook.HookOutput({approved: approveOperations, reason: approveOperations ? "" : rejectReason});
        }
    }
}

// Unique hooks for RulesEngine test to avoid ID collision
contract UniqueHook1 is IHook {
    function hookId() external pure returns (bytes32) {
        return keccak256("UniqueHook1ForRulesEngine");
    }

    function name() external pure returns (string memory) {
        return "UniqueHook1";
    }

    function onBeforeDeposit(address, address, uint256, address) external pure returns (IHook.HookOutput memory) {
        return IHook.HookOutput(true, "");
    }

    function onBeforeWithdraw(address, address, uint256, address, address)
        external
        pure
        returns (IHook.HookOutput memory)
    {
        return IHook.HookOutput(true, "");
    }

    function onBeforeTransfer(address, address, address, uint256) external pure returns (IHook.HookOutput memory) {
        return IHook.HookOutput(true, "");
    }
}

contract UniqueHook2 is IHook {
    function hookId() external pure returns (bytes32) {
        return keccak256("UniqueHook2ForRulesEngine");
    }

    function name() external pure returns (string memory) {
        return "UniqueHook2";
    }

    function onBeforeDeposit(address, address, uint256, address) external pure returns (IHook.HookOutput memory) {
        return IHook.HookOutput(true, "");
    }

    function onBeforeWithdraw(address, address, uint256, address, address)
        external
        pure
        returns (IHook.HookOutput memory)
    {
        return IHook.HookOutput(true, "");
    }

    function onBeforeTransfer(address, address, address, uint256) external pure returns (IHook.HookOutput memory) {
        return IHook.HookOutput(true, "");
    }
}

contract UniqueHook3 is IHook {
    function hookId() external pure returns (bytes32) {
        return keccak256("UniqueHook3ForRulesEngine");
    }

    function name() external pure returns (string memory) {
        return "UniqueHook3";
    }

    function onBeforeDeposit(address, address, uint256, address) external pure returns (IHook.HookOutput memory) {
        return IHook.HookOutput(true, "");
    }

    function onBeforeWithdraw(address, address, uint256, address, address)
        external
        pure
        returns (IHook.HookOutput memory)
    {
        return IHook.HookOutput(true, "");
    }

    function onBeforeTransfer(address, address, address, uint256) external pure returns (IHook.HookOutput memory) {
        return IHook.HookOutput(true, "");
    }
}

/**
 * @title RulesEngineTests
 * @notice Test contract for the RulesEngine implementation
 */
contract RulesEngineTests is BaseFountfiTest {
    RulesEngine public rulesEngine;
    RoleManager public roleManager;

    // We'll create multiple hook instances with different configurations
    MockHook public allowHook;
    MockHook public denyHook;
    OperationSpecificMockHook public transferHook;
    OperationSpecificMockHook public depositHook;
    OperationSpecificMockHook public withdrawHook;

    // Hook IDs
    bytes32 public allowHookId;
    bytes32 public denyHookId;
    bytes32 public transferHookId;
    bytes32 public depositHookId;
    bytes32 public withdrawHookId;

    // Constants for operation types
    uint256 constant OPERATION_DEPOSIT = 1;
    uint256 constant OPERATION_WITHDRAW = 2;
    uint256 constant OPERATION_TRANSFER = 3;

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);

        // Deploy our custom role manager with RULES_ADMIN
        roleManager = new RoleManager();
        roleManager.initializeRegistry(address(this));

        // Grant RULES_ADMIN role to owner explicitly
        roleManager.grantRole(owner, roleManager.RULES_ADMIN());

        // Deploy rules engine
        rulesEngine = new RulesEngine(address(roleManager));

        // Create custom MockHook child contract that overrides hookName for uniqueness
        CustomMockHook allowHookTemp = new CustomMockHook(true, "", "AllowHook");
        CustomMockHook denyHookTemp = new CustomMockHook(false, "Hook denies operation", "DenyHook");

        // Store as MockHook reference
        allowHook = MockHook(address(allowHookTemp));
        denyHook = MockHook(address(denyHookTemp));

        // Create hooks for specific operations
        transferHook = new OperationSpecificMockHook(OPERATION_TRANSFER, true, "");
        depositHook = new OperationSpecificMockHook(OPERATION_DEPOSIT, true, "");
        withdrawHook = new OperationSpecificMockHook(OPERATION_WITHDRAW, true, "");

        vm.stopPrank();
    }

    function test_AddHook() public {
        vm.startPrank(owner);

        // Add a hook to the engine
        allowHookId = rulesEngine.addHook(address(allowHook), 100);

        // Verify hook was added
        assertEq(rulesEngine.getHookAddress(allowHookId), address(allowHook));
        assertEq(rulesEngine.getHookPriority(allowHookId), 100);
        assertTrue(rulesEngine.isHookActive(allowHookId));

        // Add another hook with different priority
        denyHookId = rulesEngine.addHook(address(denyHook), 50);

        // Verify both hooks are returned in getAllHookIds
        bytes32[] memory allHooks = rulesEngine.getAllHookIds();
        assertEq(allHooks.length, 2);

        vm.stopPrank();
    }

    function test_AddHookInvalidAddress() public {
        vm.startPrank(owner);

        // Try to add a hook with address zero
        vm.expectRevert(abi.encodeWithSelector(RulesEngine.InvalidHookAddress.selector)); // Should revert with InvalidHookAddress
        rulesEngine.addHook(address(0), 100);

        vm.stopPrank();
    }

    function test_AddHookAlreadyExists() public {
        vm.startPrank(owner);

        // Add a hook
        allowHookId = rulesEngine.addHook(address(allowHook), 100);

        // Try to add same hook again
        vm.expectRevert(abi.encodeWithSelector(RulesEngine.HookAlreadyExists.selector, allowHookId)); // Should revert with HookAlreadyExists
        rulesEngine.addHook(address(allowHook), 100);

        vm.stopPrank();
    }

    function test_RemoveHook() public {
        vm.startPrank(owner);

        // Add a hook
        allowHookId = rulesEngine.addHook(address(allowHook), 100);

        // Verify hook exists
        assertEq(rulesEngine.getHookAddress(allowHookId), address(allowHook));

        // Remove the hook
        rulesEngine.removeHook(allowHookId);

        // Verify hook is removed (address should be zero)
        assertEq(rulesEngine.getHookAddress(allowHookId), address(0));

        // Verify hook is no longer in getAllHookIds
        bytes32[] memory allHooks = rulesEngine.getAllHookIds();
        assertEq(allHooks.length, 0);

        vm.stopPrank();
    }

    function test_RemoveHookNotFound() public {
        vm.startPrank(owner);

        // Try to remove a non-existent hook
        bytes32 invalidHookId = bytes32(uint256(1));
        vm.expectRevert(abi.encodeWithSelector(RulesEngine.HookNotFound.selector, invalidHookId)); // Should revert with HookNotFound
        rulesEngine.removeHook(invalidHookId);

        vm.stopPrank();
    }

    function test_ChangeHookPriority() public {
        vm.startPrank(owner);

        // Add a hook
        allowHookId = rulesEngine.addHook(address(allowHook), 100);

        // Verify initial priority
        assertEq(rulesEngine.getHookPriority(allowHookId), 100);

        // Change priority
        rulesEngine.changeHookPriority(allowHookId, 50);

        // Verify new priority
        assertEq(rulesEngine.getHookPriority(allowHookId), 50);

        vm.stopPrank();
    }

    function test_EnableDisableHook() public {
        vm.startPrank(owner);

        // Add a hook
        allowHookId = rulesEngine.addHook(address(allowHook), 100);

        // Verify hook is active by default
        assertTrue(rulesEngine.isHookActive(allowHookId));

        // Disable hook
        rulesEngine.disableHook(allowHookId);

        // Verify hook is inactive
        assertFalse(rulesEngine.isHookActive(allowHookId));

        // Enable hook
        rulesEngine.enableHook(allowHookId);

        // Verify hook is active again
        assertTrue(rulesEngine.isHookActive(allowHookId));

        vm.stopPrank();
    }

    function test_HookEvaluationPriority() public {
        vm.startPrank(owner);

        // Create allow and deny hooks with different priorities
        // Lower priority executes first
        allowHookId = rulesEngine.addHook(address(allowHook), 100);
        denyHookId = rulesEngine.addHook(address(denyHook), 50);

        // Since deny hook has lower priority (50), it will execute first
        // and block the operation, so the result should be deny
        IHook.HookOutput memory result = rulesEngine.onBeforeTransfer(address(0), alice, bob, 100);

        // Check the result - operation should be denied
        assertFalse(result.approved);
        assertEq(result.reason, "Hook denies operation");

        // Change priorities so allow hook runs first
        rulesEngine.changeHookPriority(allowHookId, 25);

        // Now the allow hook has priority 25 (lower = first)
        // But it doesn't matter since all hooks must approve
        result = rulesEngine.onBeforeTransfer(address(0), alice, bob, 100);

        // Still denied because both hooks must approve
        assertFalse(result.approved);

        vm.stopPrank();
    }

    function test_HookEvaluationAllApprove() public {
        vm.startPrank(owner);

        // Add only the allowing hook
        allowHookId = rulesEngine.addHook(address(allowHook), 100);

        // Test transfer evaluation - should approve
        IHook.HookOutput memory result = rulesEngine.onBeforeTransfer(address(0), alice, bob, 100);

        // Check result - should be approved
        assertTrue(result.approved);
        assertEq(result.reason, "");

        // Test deposit evaluation - should approve
        result = rulesEngine.onBeforeDeposit(address(0), alice, 100, alice);

        // Check result - should be approved
        assertTrue(result.approved);
        assertEq(result.reason, "");

        // Test withdraw evaluation - should approve
        result = rulesEngine.onBeforeWithdraw(address(0), alice, 100, alice, alice);

        // Check result - should be approved
        assertTrue(result.approved);
        assertEq(result.reason, "");

        vm.stopPrank();
    }

    function test_InactiveHooksSkipped() public {
        vm.startPrank(owner);

        // Add a deny hook, then disable it
        denyHookId = rulesEngine.addHook(address(denyHook), 100);
        rulesEngine.disableHook(denyHookId);

        // Add an allow hook
        allowHookId = rulesEngine.addHook(address(allowHook), 200);

        // Run evaluation, deny hook should be skipped
        IHook.HookOutput memory result = rulesEngine.onBeforeTransfer(address(0), alice, bob, 100);

        // Only allow hook should be evaluated, so result is approved
        assertTrue(result.approved);

        // Re-enable deny hook
        rulesEngine.enableHook(denyHookId);

        // Now deny hook will be evaluated, so result is denied
        result = rulesEngine.onBeforeTransfer(address(0), alice, bob, 100);
        assertFalse(result.approved);

        vm.stopPrank();
    }

    function test_OperationSpecificHooks() public {
        vm.startPrank(owner);

        // Add operation-specific hooks
        transferHookId = rulesEngine.addHook(address(transferHook), 100);
        depositHookId = rulesEngine.addHook(address(depositHook), 100);
        withdrawHookId = rulesEngine.addHook(address(withdrawHook), 100);

        // Test transfer - should be approved by the transfer hook
        IHook.HookOutput memory result = rulesEngine.onBeforeTransfer(address(0), alice, bob, 100);

        // Transfer should be approved
        assertTrue(result.approved);

        // Now add a deny hook for all operations
        denyHookId = rulesEngine.addHook(address(denyHook), 50); // Lower priority so it runs first

        // Test transfer again - should be denied by deny hook
        result = rulesEngine.onBeforeTransfer(address(0), alice, bob, 100);

        // Should be denied
        assertFalse(result.approved);

        vm.stopPrank();
    }

    function test_NoHooks() public {
        vm.startPrank(owner);

        // No hooks added, everything should pass
        IHook.HookOutput memory result = rulesEngine.onBeforeTransfer(address(0), alice, bob, 100);

        // Should be approved by default when no hooks to check
        assertTrue(result.approved);

        vm.stopPrank();
    }

    function test_UnauthorizedRoleManagement() public {
        // Test hook management by non-owner
        vm.startPrank(alice);

        // Attempt to add a hook
        vm.expectRevert(
            abi.encodeWithSelector(LibRoleManaged.UnauthorizedRole.selector, alice, roleManager.RULES_ADMIN())
        );
        rulesEngine.addHook(address(allowHook), 100);

        vm.stopPrank();

        // Add a hook as owner
        vm.startPrank(owner);
        allowHookId = rulesEngine.addHook(address(allowHook), 100);
        vm.stopPrank();

        // Attempt to disable a hook as non-owner
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(LibRoleManaged.UnauthorizedRole.selector, alice, roleManager.RULES_ADMIN())
        );
        rulesEngine.disableHook(allowHookId);
        vm.stopPrank();
    }

    function test_constructor_setsRoleManager() public view {
        // Assert that the role manager was set correctly
        assertEq(address(rulesEngine.roleManager()), address(roleManager));
    }

    function test_addHook_success() public {
        vm.startPrank(owner); // Owner has RULES_ADMIN implicitly via PROTOCOL_ADMIN or explicitly granted above

        // Get hook ID from the hook contract itself to ensure we are checking the correct one
        bytes32 expectedHookId = allowHook.hookId();

        // Expect emit for HookAdded
        vm.expectEmit(true, true, true, true);
        emit RulesEngine.HookAdded(expectedHookId, address(allowHook), 0); // Use priority 0 for example

        bytes32 addedHookId = rulesEngine.addHook(address(allowHook), 0); // Use priority 0
        assertEq(addedHookId, expectedHookId, "Returned hookId mismatch");
        assertEq(rulesEngine.getHookAddress(addedHookId), address(allowHook), "Hook address mismatch after adding");
        vm.stopPrank();
    }

    function test_addHook_revert_notAdmin() public {
        vm.startPrank(alice); // Alice does not have RULES_ADMIN

        // Expect revert due to unauthorized access
        vm.expectRevert(
            abi.encodeWithSelector(LibRoleManaged.UnauthorizedRole.selector, alice, roleManager.RULES_ADMIN())
        );
        rulesEngine.addHook(address(allowHook), 0); // Use priority 0

        vm.stopPrank();
    }

    function test_addHook_revert_zeroAddress() public {
        vm.startPrank(owner);

        // Expect revert due to zero address
        vm.expectRevert(RulesEngine.InvalidHookAddress.selector); // Updated error selector
        rulesEngine.addHook(address(0), 0); // Use priority 0

        vm.stopPrank();
    }

    // Test for checking hook existence after adding (Corrected)
    function test_getHookAddress_after_addHook() public {
        vm.startPrank(owner);
        bytes32 addedHookId = rulesEngine.addHook(address(allowHook), 0); // Use priority 0
        assertEq(rulesEngine.getHookAddress(addedHookId), address(allowHook));
        vm.stopPrank();
    }

    function test_removeHook_success() public {
        vm.startPrank(owner);
        bytes32 addedHookId = rulesEngine.addHook(address(allowHook), 0); // First add the hook with priority 0
        // assertTrue(rulesEngine.isHookRegistered(allowHookId)); // Obsolete check

        // Expect emit for HookRemoved
        vm.expectEmit(true, true, true, false); // hookAddress and priority are not indexed for HookRemoved
        emit RulesEngine.HookRemoved(addedHookId);

        rulesEngine.removeHook(addedHookId); // Correct: remove by ID

        // After removal, the hook address should be address(0)
        assertEq(rulesEngine.getHookAddress(addedHookId), address(0));
        vm.stopPrank();
    }

    function test_removeHook_revert_notAdmin() public {
        vm.startPrank(owner);
        bytes32 addedHookId = rulesEngine.addHook(address(allowHook), 0); // Add hook first with priority 0
        vm.stopPrank();

        vm.startPrank(alice); // Alice does not have RULES_ADMIN
        // Expect revert due to unauthorized access
        vm.expectRevert(
            abi.encodeWithSelector(LibRoleManaged.UnauthorizedRole.selector, alice, roleManager.RULES_ADMIN())
        );
        rulesEngine.removeHook(addedHookId); // Call with hookId
        vm.stopPrank();
    }

    /**
     * @notice Test getAllActiveHookIdsSorted function (lines 165-166)
     * @dev This function was previously not covered
     */
    function test_GetAllActiveHookIdsSorted() public {
        // Create unique hooks for this test
        UniqueHook1 hook1 = new UniqueHook1();
        UniqueHook2 hook2 = new UniqueHook2();
        UniqueHook3 hook3 = new UniqueHook3();

        // Add hooks with different priorities
        vm.startPrank(owner);
        rulesEngine.addHook(address(hook1), 100);
        rulesEngine.addHook(address(hook2), 50);
        rulesEngine.addHook(address(hook3), 150);

        // Disable one hook
        rulesEngine.disableHook(keccak256("UniqueHook3ForRulesEngine"));
        vm.stopPrank();

        // Get all active hooks sorted
        bytes32[] memory sortedIds = rulesEngine.getAllActiveHookIdsSorted();

        // Should have 2 active hooks (hook3 is disabled)
        // After the fix, the array is truncated to only contain active hooks
        assertEq(sortedIds.length, 2);

        // Verify they are sorted by priority (ascending)
        // hook2 (50) < hook1 (100)
        assertEq(sortedIds[0], keccak256("UniqueHook2ForRulesEngine"));
        assertEq(sortedIds[1], keccak256("UniqueHook1ForRulesEngine"));
    }

    /**
     * @notice Test changeHookPriority with non-existent hook (line 113)
     * @dev This covers the uncovered branch BRDA:113,4,0,-
     */
    function test_ChangeHookPriority_HookNotFound() public {
        vm.startPrank(owner);

        bytes32 nonExistentHookId = keccak256("NonExistentHook");

        vm.expectRevert(abi.encodeWithSelector(RulesEngine.HookNotFound.selector, nonExistentHookId));
        rulesEngine.changeHookPriority(nonExistentHookId, 50);

        vm.stopPrank();
    }

    /**
     * @notice Test enableHook with non-existent hook (line 125)
     * @dev This covers the uncovered branch BRDA:125,5,0,-
     */
    function test_EnableHook_HookNotFound() public {
        vm.startPrank(owner);

        bytes32 nonExistentHookId = keccak256("NonExistentHook");

        vm.expectRevert(abi.encodeWithSelector(RulesEngine.HookNotFound.selector, nonExistentHookId));
        rulesEngine.enableHook(nonExistentHookId);

        vm.stopPrank();
    }

    /**
     * @notice Test disableHook with non-existent hook (line 137)
     * @dev This covers the uncovered branch BRDA:137,6,0,-
     */
    function test_DisableHook_HookNotFound() public {
        vm.startPrank(owner);

        bytes32 nonExistentHookId = keccak256("NonExistentHook");

        vm.expectRevert(abi.encodeWithSelector(RulesEngine.HookNotFound.selector, nonExistentHookId));
        rulesEngine.disableHook(nonExistentHookId);

        vm.stopPrank();
    }

    /**
     * @notice Test hook call failure in _evaluateSubHooks (line 251)
     * @dev This covers the uncovered branch BRDA:251,7,0,-
     */
    function test_HookCallFailure() public {
        // Create a hook that will revert when called
        AlwaysRevertingHook failingHook = new AlwaysRevertingHook("Hook intentionally fails");

        vm.startPrank(owner);

        // Add the failing hook
        bytes32 failingHookId = rulesEngine.addHook(address(failingHook), 100);

        vm.stopPrank();

        // Try to call onBeforeTransfer - should revert with HookEvaluationFailed
        vm.expectRevert(abi.encodeWithSelector(RulesEngine.HookEvaluationFailed.selector, failingHookId, bytes4(0)));
        rulesEngine.onBeforeTransfer(address(0), alice, bob, 100);
    }

    /**
     * @notice Test that array truncation works through getAllActiveHookIdsSorted
     * @dev This verifies the fix for the audit finding about zero-value entries
     */
    function test_ArrayTruncation_ProperlyTruncated() public {
        vm.startPrank(owner);

        // Add multiple hooks with unique names
        CustomMockHook hook1 = new CustomMockHook(true, "", "TruncateTest1");
        CustomMockHook hook2 = new CustomMockHook(true, "", "TruncateTest2");
        CustomMockHook hook3 = new CustomMockHook(true, "", "TruncateTest3");

        bytes32 hookId1 = rulesEngine.addHook(address(hook1), 10);
        bytes32 hookId2 = rulesEngine.addHook(address(hook2), 20);
        bytes32 hookId3 = rulesEngine.addHook(address(hook3), 30);

        // Disable one hook
        rulesEngine.disableHook(hookId2);

        // Get sorted active hook IDs through public function
        bytes32[] memory activeHookIds = rulesEngine.getAllActiveHookIdsSorted();

        // Should only have 2 active hooks, not 3
        assertEq(activeHookIds.length, 2, "Array should be truncated to active hooks only");

        // Verify the hooks are the active ones (hookId1 and hookId3)
        assertEq(activeHookIds[0], hookId1, "First hook should be hookId1");
        assertEq(activeHookIds[1], hookId3, "Second hook should be hookId3");

        // Verify no zero entries
        for (uint256 i = 0; i < activeHookIds.length; i++) {
            assertTrue(activeHookIds[i] != bytes32(0), "No zero entries should exist");
        }

        vm.stopPrank();
    }

    /**
     * @notice Test that hooks are properly sorted by priority
     * @dev This verifies the sorting still works correctly after truncation
     */
    function test_ArrayTruncation_CorrectlySorted() public {
        vm.startPrank(owner);

        // Add hooks with different priorities (add in reverse order)
        CustomMockHook hook1 = new CustomMockHook(true, "", "SortTest1");
        CustomMockHook hook2 = new CustomMockHook(true, "", "SortTest2");
        CustomMockHook hook3 = new CustomMockHook(true, "", "SortTest3");

        bytes32 hookId1 = rulesEngine.addHook(address(hook1), 30); // Highest priority
        bytes32 hookId2 = rulesEngine.addHook(address(hook2), 10); // Lowest priority
        bytes32 hookId3 = rulesEngine.addHook(address(hook3), 20); // Middle priority

        // Get sorted active hook IDs through public function
        bytes32[] memory activeHookIds = rulesEngine.getAllActiveHookIdsSorted();

        // Should have all 3 hooks sorted by priority (ascending)
        assertEq(activeHookIds.length, 3, "Should have all active hooks");
        assertEq(activeHookIds[0], hookId2, "First should be lowest priority (10)");
        assertEq(activeHookIds[1], hookId3, "Second should be middle priority (20)");
        assertEq(activeHookIds[2], hookId1, "Third should be highest priority (30)");

        vm.stopPrank();
    }

    /**
     * @notice Test edge case with all hooks disabled
     * @dev Ensures empty array is returned when no hooks are active
     */
    function test_ArrayTruncation_AllDisabled() public {
        vm.startPrank(owner);

        // Add hooks and disable them all
        CustomMockHook hook1 = new CustomMockHook(true, "", "DisableTest1");
        CustomMockHook hook2 = new CustomMockHook(true, "", "DisableTest2");

        bytes32 hookId1 = rulesEngine.addHook(address(hook1), 10);
        bytes32 hookId2 = rulesEngine.addHook(address(hook2), 20);

        rulesEngine.disableHook(hookId1);
        rulesEngine.disableHook(hookId2);

        // Get sorted active hook IDs through public function
        bytes32[] memory activeHookIds = rulesEngine.getAllActiveHookIdsSorted();

        // Should return empty array
        assertEq(activeHookIds.length, 0, "Should return empty array when no hooks are active");

        vm.stopPrank();
    }

    /**
     * @notice Test to ensure no repetitive evaluation of zero hook ID
     * @dev This specifically addresses the audit finding about zero-value entries
     */
    function test_NoZeroHookIdEvaluation() public {
        vm.startPrank(owner);

        // Add some hooks with one disabled
        CustomMockHook hook1 = new CustomMockHook(true, "", "ZeroTest1");
        CustomMockHook hook2 = new CustomMockHook(true, "", "ZeroTest2");
        CustomMockHook hook3 = new CustomMockHook(true, "", "ZeroTest3");

        rulesEngine.addHook(address(hook1), 10);
        bytes32 hookId2 = rulesEngine.addHook(address(hook2), 20);
        rulesEngine.addHook(address(hook3), 30);

        // Disable the middle hook
        rulesEngine.disableHook(hookId2);

        // Execute a hook evaluation
        IHook.HookOutput memory result = rulesEngine.onBeforeTransfer(address(0), alice, bob, 100);

        // Should pass because all active hooks approve
        assertTrue(result.approved);

        // With the fix, only active hooks are evaluated, so no zero entries exist
        // If there were zero entries, and a hook with ID 0 existed and was active,
        // it would be evaluated multiple times, which this fix prevents

        vm.stopPrank();
    }

    function test_RemoveHook_LastElement() public {
        vm.startPrank(owner);

        // Add multiple hooks to the engine
        bytes32 hookId1 = rulesEngine.addHook(address(allowHook), 100);
        bytes32 hookId2 = rulesEngine.addHook(address(denyHook), 200);
        bytes32 hookId3 = rulesEngine.addHook(address(transferHook), 300);

        // Verify all hooks are present
        bytes32[] memory allHookIds = rulesEngine.getAllHookIds();
        assertEq(allHookIds.length, 3);
        assertEq(allHookIds[0], hookId1);
        assertEq(allHookIds[1], hookId2);
        assertEq(allHookIds[2], hookId3);

        // Remove the last hook (hookId3) - this tests the new optimization branch
        rulesEngine.removeHook(hookId3);

        // Verify the hook was removed correctly
        allHookIds = rulesEngine.getAllHookIds();
        assertEq(allHookIds.length, 2);
        assertEq(allHookIds[0], hookId1);
        assertEq(allHookIds[1], hookId2);
        assertEq(rulesEngine.getHookAddress(hookId3), address(0));

        // Verify the remaining hooks still function correctly
        IHook.HookOutput memory result = rulesEngine.onBeforeTransfer(address(0), alice, bob, 100);
        assertFalse(result.approved); // denyHook should still deny

        vm.stopPrank();
    }

    function test_RemoveHook_MiddleElement() public {
        vm.startPrank(owner);

        // Add multiple hooks to the engine
        bytes32 hookId1 = rulesEngine.addHook(address(allowHook), 100);
        bytes32 hookId2 = rulesEngine.addHook(address(denyHook), 200);
        bytes32 hookId3 = rulesEngine.addHook(address(transferHook), 300);

        // Verify all hooks are present
        bytes32[] memory allHookIds = rulesEngine.getAllHookIds();
        assertEq(allHookIds.length, 3);

        // Remove the middle hook (hookId2) - this tests the swap-and-pop logic
        rulesEngine.removeHook(hookId2);

        // Verify the hook was removed correctly
        allHookIds = rulesEngine.getAllHookIds();
        assertEq(allHookIds.length, 2);

        // The last element (hookId3) should have been swapped to the middle position
        assertEq(allHookIds[0], hookId1);
        assertEq(allHookIds[1], hookId3); // hookId3 moved to where hookId2 was
        assertEq(rulesEngine.getHookAddress(hookId2), address(0));

        // Verify the remaining hooks still function correctly
        assertTrue(rulesEngine.isHookActive(hookId1));
        assertTrue(rulesEngine.isHookActive(hookId3));

        vm.stopPrank();
    }
}
