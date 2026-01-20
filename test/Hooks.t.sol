// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseFountfiTest} from "./BaseFountfiTest.t.sol";
import {Test} from "forge-std/Test.sol";
import {RulesEngine} from "../src/hooks/RulesEngine.sol";
import {KycRulesHook} from "../src/hooks/KycRulesHook.sol";
import {MockSubscriptionHook} from "../src/mocks/hooks/MockSubscriptionHook.sol";
import {MockCappedSubscriptionHook} from "../src/mocks/hooks/MockCappedSubscriptionHook.sol";
import {IHook} from "../src/hooks/IHook.sol";
import {tRWA} from "../src/token/tRWA.sol";
import {MockStrategy} from "../src/mocks/MockStrategy.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {MockHook} from "../src/mocks/hooks/MockHook.sol";
import {ReportedStrategy} from "../src/strategy/ReportedStrategy.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockReporter} from "../src/mocks/MockReporter.sol";
import {Registry} from "../src/registry/Registry.sol";

contract HooksTest is BaseFountfiTest {
    RulesEngine public rulesEngine;
    KycRulesHook public kycRules;
    MockSubscriptionHook public subHook;
    MockCappedSubscriptionHook public cappedHook;

    RoleManager public roleManager;

    // Additional state for hook removal tests
    tRWA public removalTestToken;
    ReportedStrategy public removalTestStrategy;
    MockHook public hook1;
    MockHook public hook2;
    MockERC20 public removalTestAsset;
    MockReporter public reporter;
    Registry public removalTestRegistry;
    RoleManager public removalTestRoleManager;

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);

        roleManager = new RoleManager();
        roleManager.initializeRegistry(address(this));

        roleManager.grantRole(owner, roleManager.STRATEGY_OPERATOR());
        roleManager.grantRole(owner, roleManager.KYC_OPERATOR());

        rulesEngine = new RulesEngine(address(roleManager));
        kycRules = new KycRulesHook(address(roleManager));

        subHook = new MockSubscriptionHook(owner, true, true);
        cappedHook = new MockCappedSubscriptionHook(10_000 * 10 ** 6, true, "Test rejection");

        // Set up additional infrastructure for hook removal tests
        removalTestRoleManager = new RoleManager();
        removalTestRegistry = new Registry(address(removalTestRoleManager));
        removalTestRoleManager.initializeRegistry(address(removalTestRegistry));

        removalTestRoleManager.grantRole(owner, removalTestRoleManager.STRATEGY_OPERATOR());
        removalTestRoleManager.grantRole(owner, removalTestRoleManager.KYC_OPERATOR());

        // Deploy asset and register it
        removalTestAsset = new MockERC20("Test Asset", "TEST", 18);
        removalTestRegistry.setAsset(address(removalTestAsset), 18);

        // Deploy reporter and strategy
        reporter = new MockReporter(1e18);
        ReportedStrategy strategyImpl = new ReportedStrategy();
        removalTestRegistry.setStrategy(address(strategyImpl), true);

        // Deploy strategy and token through registry
        bytes memory initData = abi.encode(address(reporter));
        (address strategyAddr, address tokenAddr) = removalTestRegistry.deploy(
            address(strategyImpl), "Test Token", "TEST", address(removalTestAsset), manager, initData
        );

        removalTestStrategy = ReportedStrategy(payable(strategyAddr));
        removalTestToken = tRWA(tokenAddr);

        // Deploy test hooks for removal tests
        hook1 = new MockHook(true, "");
        hook2 = new MockHook(true, "");

        vm.stopPrank();
    }

    // === KYC Rules Tests ===

    function test_KycRules_AllowDeny() public {
        // Verify default is deny
        assertFalse(kycRules.isAllowed(alice));

        // Allow Alice
        vm.prank(owner);
        kycRules.allow(alice);

        // Verify Alice is allowed
        assertTrue(kycRules.isAllowed(alice));

        // Deny Alice
        vm.prank(owner);
        kycRules.deny(alice);

        // Verify Alice is denied
        assertFalse(kycRules.isAllowed(alice));

        // Reset address
        vm.prank(owner);
        kycRules.reset(alice);

        // Verify Alice is back to default (deny)
        assertFalse(kycRules.isAllowed(alice));
    }

    function test_KycRules_TransferRules() public {
        // Setup KYC status
        vm.startPrank(owner);
        kycRules.allow(alice);
        kycRules.allow(bob);
        vm.stopPrank();

        // Test transfer between allowed addresses
        IHook.HookOutput memory result = kycRules.onBeforeTransfer(address(0), alice, bob, 100);

        assertTrue(result.approved);
        assertEq(result.reason, "");

        // Deny Charlie
        vm.prank(owner);
        kycRules.deny(charlie);

        // Test transfer to denied address
        result = kycRules.onBeforeTransfer(address(0), alice, charlie, 100);

        assertFalse(result.approved);
        assertEq(result.reason, "KycRules: receiver");

        // Test transfer from denied address
        result = kycRules.onBeforeTransfer(address(0), charlie, alice, 100);

        assertFalse(result.approved);
        assertEq(result.reason, "KycRules: sender");
    }

    // === Subscription Hook Tests ===

    function test_SubscriptionHook_Approval() public {
        // Test initial state
        IHook.HookOutput memory result = subHook.onBeforeDeposit(address(0), alice, 100, alice);

        // Should fail because alice is not approved
        assertFalse(result.approved);
        assertEq(result.reason, "Address is not approved for subscription");

        // Approve alice
        vm.prank(owner);
        subHook.setSubscriber(alice, true);

        // Try deposit again
        result = subHook.onBeforeDeposit(address(0), alice, 100, alice);

        // Should succeed now
        assertTrue(result.approved);

        // Close subscriptions
        vm.prank(owner);
        subHook.setSubscriptionStatus(false);

        // Try deposit again
        result = subHook.onBeforeDeposit(address(0), alice, 100, alice);

        // Should fail because subscriptions closed
        assertFalse(result.approved);
        assertEq(result.reason, "Subscriptions are closed");

        // Disable approval enforcement
        vm.startPrank(owner);
        subHook.setSubscriptionStatus(true); // Open again
        subHook.setEnforceApproval(false);
        vm.stopPrank();

        // Try with unapproved user
        result = subHook.onBeforeDeposit(address(0), bob, 100, bob);

        // Should succeed because enforcement is off
        assertTrue(result.approved);
    }

    function test_SubscriptionHook_BatchApproval() public {
        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;

        // Batch approve
        vm.prank(owner);
        subHook.batchSetSubscribers(users, true);

        // Check all are approved
        IHook.HookOutput memory result;

        result = subHook.onBeforeDeposit(address(0), alice, 100, alice);
        assertTrue(result.approved);

        result = subHook.onBeforeDeposit(address(0), bob, 100, bob);
        assertTrue(result.approved);

        result = subHook.onBeforeDeposit(address(0), charlie, 100, charlie);
        assertTrue(result.approved);
    }

    // === Capped Subscription Hook Tests ===

    function test_CappedHook_Limits() public {
        // For the MockCappedSubscriptionHook, we'll test the basic cap management functions

        // Initial cap should be 10_000 * 10**6
        assertEq(cappedHook.maxSubscriptionSize(), 10_000 * 10 ** 6);

        // Update cap
        cappedHook.setMaxSubscriptionSize(20_000 * 10 ** 6);

        // Verify cap was updated
        assertEq(cappedHook.maxSubscriptionSize(), 20_000 * 10 ** 6);
    }

    function test_CappedHook_Deposit() public {
        // Initial cap is 10_000 * 10**6

        // Test deposit within cap
        IHook.HookOutput memory result = cappedHook.onBeforeDeposit(address(0), bob, 5_000 * 10 ** 6, bob);

        assertTrue(result.approved);

        // Check used cap
        assertEq(cappedHook.totalSubscriptions(), 5_000 * 10 ** 6);

        // Test deposit that exceeds cap
        result = cappedHook.onBeforeDeposit(address(0), bob, 6_000 * 10 ** 6, bob);

        assertFalse(result.approved);
        assertEq(result.reason, "Subscription would exceed maximum capacity");

        // Total subscriptions should be unchanged
        assertEq(cappedHook.totalSubscriptions(), 5_000 * 10 ** 6);
    }

    // === Rules Engine Tests ===

    function test_RulesEngine_Management() public {
        // Create custom hook implementations that will have unique hookIds
        vm.prank(owner);
        MockHook uniqueHook1 = new MockHook(true, "");

        vm.prank(owner);
        MockHook uniqueHook2 = new MockHook(true, "");

        // Modify their names to ensure unique hookIds
        vm.prank(owner);
        uniqueHook1.setName("UniqueHook1");

        vm.prank(owner);
        uniqueHook2.setName("UniqueHook2");

        // Add hooks to the RulesEngine
        vm.prank(owner);
        rulesEngine.addHook(address(uniqueHook1), 0);

        vm.prank(owner);
        rulesEngine.addHook(address(uniqueHook2), 1);

        // Get all hook IDs
        bytes32[] memory hookIds = rulesEngine.getAllHookIds();
        assertEq(hookIds.length, 2, "Should have 2 hooks registered");

        // Disable a hook
        vm.prank(owner);
        rulesEngine.disableHook(hookIds[0]);
        assertFalse(rulesEngine.isHookActive(hookIds[0]), "Hook should be disabled");

        // Enable a hook
        vm.prank(owner);
        rulesEngine.enableHook(hookIds[0]);
        assertTrue(rulesEngine.isHookActive(hookIds[0]), "Hook should be enabled");

        // Change priority
        vm.prank(owner);
        rulesEngine.changeHookPriority(hookIds[0], 2);
        assertEq(rulesEngine.getHookPriority(hookIds[0]), 2, "Priority should be updated");

        // Remove a hook
        vm.prank(owner);
        rulesEngine.removeHook(hookIds[1]);
        hookIds = rulesEngine.getAllHookIds();
        assertEq(hookIds.length, 1, "Should have 1 hook after removal");
    }

    function test_RulesEngine_Evaluation() public {
        // Create hooks with unique IDs
        vm.prank(owner);
        MockHook kycMockHook = new MockHook(true, "");

        vm.prank(owner);
        MockHook subMockHook = new MockHook(true, "");

        // Set unique names to avoid hook ID collisions
        vm.prank(owner);
        kycMockHook.setName("KycMockHook");

        vm.prank(owner);
        subMockHook.setName("SubMockHook");

        // Set subMockHook to reject bob
        vm.prank(owner);
        subMockHook.setApproveStatus(true, "");

        // Add hooks to the RulesEngine
        vm.prank(owner);
        rulesEngine.addHook(address(kycMockHook), 0);

        vm.prank(owner);
        rulesEngine.addHook(address(subMockHook), 1);

        // Test evaluation for alice (should pass both hooks)
        IHook.HookOutput memory result = rulesEngine.onBeforeDeposit(address(0), alice, 100, alice);
        assertTrue(result.approved, "Alice should pass both hooks");

        // Now set the second hook to reject
        vm.prank(owner);
        subMockHook.setApproveStatus(false, "Sub hook rejects bob");

        // Test evaluation (should now fail due to second hook)
        result = rulesEngine.onBeforeDeposit(address(0), bob, 100, bob);
        assertFalse(result.approved, "Should fail when a hook rejects");
        assertTrue(bytes(result.reason).length > 0, "Reason should be provided");
    }

    // === Hook Removal Tests ===

    function test_AddAndRemoveHookBeforeOperations() public {
        vm.startPrank(address(removalTestStrategy));

        // Add a hook
        removalTestToken.addOperationHook(removalTestToken.OP_DEPOSIT(), address(hook1));

        // Verify hook was added
        address[] memory hooks = removalTestToken.getHooksForOperation(removalTestToken.OP_DEPOSIT());
        assertEq(hooks.length, 1);
        assertEq(hooks[0], address(hook1));

        // Should be able to remove hook since no operations have occurred
        removalTestToken.removeOperationHook(removalTestToken.OP_DEPOSIT(), 0);

        // Verify hook was removed
        hooks = removalTestToken.getHooksForOperation(removalTestToken.OP_DEPOSIT());
        assertEq(hooks.length, 0);

        vm.stopPrank();
    }

    function test_CannotRemoveHookAfterOperations() public {
        vm.startPrank(address(removalTestStrategy));

        // Add a hook
        removalTestToken.addOperationHook(removalTestToken.OP_DEPOSIT(), address(hook1));

        vm.stopPrank();

        // Perform a deposit operation
        vm.prank(owner);
        removalTestAsset.mint(alice, 1000e18);
        vm.startPrank(alice);
        removalTestAsset.approve(removalTestRegistry.conduit(), 1000e18);
        removalTestToken.deposit(1000e18, alice);
        vm.stopPrank();

        // Now try to remove the hook - should fail
        vm.startPrank(address(removalTestStrategy));
        bytes32 depositOp = removalTestToken.OP_DEPOSIT();
        vm.expectRevert(abi.encodeWithSelector(tRWA.HookHasProcessedOperations.selector));
        removalTestToken.removeOperationHook(depositOp, 0);

        vm.stopPrank();
    }

    function test_CanRemoveUnusedHookEvenIfOthersUsed() public {
        vm.startPrank(address(removalTestStrategy));

        // Add two hooks
        removalTestToken.addOperationHook(removalTestToken.OP_DEPOSIT(), address(hook1));
        removalTestToken.addOperationHook(removalTestToken.OP_WITHDRAW(), address(hook2));

        vm.stopPrank();

        // Perform only a deposit operation (uses hook1 but not hook2)
        vm.prank(owner);
        removalTestAsset.mint(alice, 1000e18);
        vm.startPrank(alice);
        removalTestAsset.approve(removalTestRegistry.conduit(), 1000e18);
        removalTestToken.deposit(1000e18, alice);
        vm.stopPrank();

        vm.startPrank(address(removalTestStrategy));

        // Should not be able to remove the deposit hook (it was used)
        bytes32 depositOp = removalTestToken.OP_DEPOSIT();
        vm.expectRevert(abi.encodeWithSelector(tRWA.HookHasProcessedOperations.selector));
        removalTestToken.removeOperationHook(depositOp, 0);

        // Should be able to remove the withdraw hook (it was not used)
        removalTestToken.removeOperationHook(removalTestToken.OP_WITHDRAW(), 0);

        // Verify withdraw hook was removed
        address[] memory withdrawHooks = removalTestToken.getHooksForOperation(removalTestToken.OP_WITHDRAW());
        assertEq(withdrawHooks.length, 0);

        vm.stopPrank();
    }

    function test_HookInfoTracking() public {
        vm.startPrank(address(removalTestStrategy));

        // Add a hook
        uint256 blockNumber = block.number;
        removalTestToken.addOperationHook(removalTestToken.OP_DEPOSIT(), address(hook1));

        // Check hook info
        tRWA.HookInfo[] memory hookInfos = removalTestToken.getHookInfoForOperation(removalTestToken.OP_DEPOSIT());
        assertEq(hookInfos.length, 1);
        assertEq(address(hookInfos[0].hook), address(hook1));
        assertEq(hookInfos[0].addedAtBlock, blockNumber);

        vm.stopPrank();

        // Perform operation
        vm.prank(owner);
        removalTestAsset.mint(alice, 1000e18);
        vm.startPrank(alice);
        removalTestAsset.approve(removalTestRegistry.conduit(), 1000e18);
        removalTestToken.deposit(1000e18, alice);
        vm.stopPrank();

        // Check that the operation type has been executed (lastExecutedBlock should be set)
        assertGt(removalTestToken.lastExecutedBlock(removalTestToken.OP_DEPOSIT()), 0);
    }

    function test_RemoveHookIndexValidation() public {
        vm.startPrank(address(removalTestStrategy));

        bytes32 depositOp = removalTestToken.OP_DEPOSIT();

        // Test 1: Try to remove hook from empty list
        vm.expectRevert(abi.encodeWithSelector(tRWA.HookIndexOutOfBounds.selector));
        removalTestToken.removeOperationHook(depositOp, 0);

        // Add one hook
        removalTestToken.addOperationHook(removalTestToken.OP_DEPOSIT(), address(hook1));

        // Test 2: Try to remove with invalid index
        vm.expectRevert(abi.encodeWithSelector(tRWA.HookIndexOutOfBounds.selector));
        removalTestToken.removeOperationHook(depositOp, 1);

        vm.stopPrank();
    }

    function test_AuthorizationCheck() public {
        // Test that non-strategy caller gets rejected
        vm.startPrank(alice);

        bytes32 depositOp = removalTestToken.OP_DEPOSIT();
        vm.expectRevert(abi.encodeWithSelector(tRWA.NotStrategyAdmin.selector));
        removalTestToken.removeOperationHook(depositOp, 0);

        vm.stopPrank();
    }
}
