// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {BaseFountfiTest} from "./BaseFountfiTest.t.sol";
import {ManagedWithdrawRWA} from "../src/token/ManagedWithdrawRWA.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockManagedStrategy} from "../src/mocks/MockManagedStrategy.sol";
import {MockRegistry} from "../src/mocks/MockRegistry.sol";
import {MockConduit} from "../src/mocks/MockConduit.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {ERC4626} from "solady/tokens/ERC4626.sol";
import {tRWA} from "../src/token/tRWA.sol";
import {MockHook} from "../src/mocks/hooks/MockHook.sol";
import {IHook} from "../src/hooks/IHook.sol";

/**
 * @title TrackingHook
 * @notice Hook that tracks withdraw operations for testing
 */
contract TrackingHook is IHook {
    bool public wasWithdrawCalled;
    address public lastWithdrawToken;
    address public lastWithdrawOperator;
    uint256 public lastWithdrawAssets;
    address public lastWithdrawReceiver;
    address public lastWithdrawOwner;

    function onBeforeDeposit(address, address, uint256, address) external pure override returns (HookOutput memory) {
        return HookOutput(true, "");
    }

    function onBeforeWithdraw(address token, address operator, uint256 assets, address receiver, address owner)
        external
        override
        returns (HookOutput memory)
    {
        wasWithdrawCalled = true;
        lastWithdrawToken = token;
        lastWithdrawOperator = operator;
        lastWithdrawAssets = assets;
        lastWithdrawReceiver = receiver;
        lastWithdrawOwner = owner;
        return HookOutput(true, "");
    }

    function onBeforeTransfer(address, address, address, uint256) external pure override returns (HookOutput memory) {
        return HookOutput(true, "");
    }

    function name() external pure override returns (string memory) {
        return "TrackingHook";
    }

    function hookId() external pure override returns (bytes32) {
        return keccak256("TrackingHook");
    }
}

/**
 * @title ManagedWithdrawRWATest
 * @notice Comprehensive tests for ManagedWithdrawRWA contract to achieve 100% coverage
 */
contract ManagedWithdrawRWATest is BaseFountfiTest {
    ManagedWithdrawRWA internal managedToken;
    MockManagedStrategy internal strategy;
    MockRegistry internal mockRegistry;
    MockConduit internal mockConduit;
    RoleManager internal roleManager;

    // Test constants
    uint256 internal constant INITIAL_SUPPLY = 10000 * 10 ** 6; // 10,000 USDC
    uint256 internal constant REDEEM_AMOUNT = 1000 * 10 ** 6; // 1,000 USDC

    // Hook operation types
    bytes32 public constant OP_WITHDRAW = keccak256("WITHDRAW_OPERATION");

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);

        // Create mock registry and conduit
        mockRegistry = new MockRegistry();
        mockConduit = new MockConduit();
        mockRegistry.setConduit(address(mockConduit));
        mockRegistry.setAsset(address(usdc), 6);

        // Deploy RoleManager
        roleManager = new RoleManager();
        roleManager.initializeRegistry(address(mockRegistry));

        // Deploy strategy
        strategy = new MockManagedStrategy();
        strategy.initialize("Managed RWA", "MRWA", address(roleManager), manager, address(usdc), 6, "");

        // Deploy ManagedWithdrawRWA token
        managedToken = new ManagedWithdrawRWA("Managed RWA", "MRWA", address(usdc), 6, address(strategy));

        // Set the token in the strategy
        strategy.setSToken(address(managedToken));

        // Setup initial balances
        usdc.mint(alice, INITIAL_SUPPLY);
        usdc.mint(bob, INITIAL_SUPPLY);
        usdc.mint(charlie, INITIAL_SUPPLY);
        usdc.mint(address(strategy), INITIAL_SUPPLY * 3);

        vm.stopPrank();

        // Strategy needs to approve the ManagedWithdrawRWA to transfer assets during redemptions
        // This uses the BasicStrategy's setAllowance function
        vm.prank(manager);
        strategy.setAllowance(address(usdc), address(managedToken), type(uint256).max);

        // Don't setup initial deposits in setUp to avoid complications
        // Tests can set them up individually as needed
    }

    // ============ Hook Redeem Tests ============

    function test_Redeem_WithPassingHook() public {
        // Setup initial deposit
        _depositAsUser(alice, INITIAL_SUPPLY / 2);

        // Create a hook that passes withdraw operations
        MockHook passingHook = new MockHook(true, "");

        // Add hook to withdraw operations (redeem uses withdraw operations)
        vm.prank(address(strategy));
        managedToken.addOperationHook(OP_WITHDRAW, address(passingHook));

        uint256 userShares = managedToken.balanceOf(alice);
        uint256 sharesToRedeem = userShares / 2;
        uint256 expectedAssets = managedToken.previewRedeem(sharesToRedeem);

        // Alice must approve strategy to spend her shares
        vm.prank(alice);
        managedToken.approve(address(strategy), sharesToRedeem);

        uint256 aliceBalanceBefore = usdc.balanceOf(alice);

        vm.prank(address(strategy));
        uint256 assetsRedeemed = managedToken.redeem(sharesToRedeem, alice, alice);

        assertEq(assetsRedeemed, expectedAssets);
        assertEq(usdc.balanceOf(alice), aliceBalanceBefore + assetsRedeemed);
        assertEq(managedToken.balanceOf(alice), userShares - sharesToRedeem);
    }

    function test_Redeem_WithFailingHook() public {
        // Setup initial deposit
        _depositAsUser(alice, INITIAL_SUPPLY / 2);

        // Create a hook that rejects withdraw operations
        MockHook rejectingHook = new MockHook(false, "Redeem blocked by hook");

        // Add hook to withdraw operations (redeem uses withdraw operations)
        vm.prank(address(strategy));
        managedToken.addOperationHook(OP_WITHDRAW, address(rejectingHook));

        uint256 userShares = managedToken.balanceOf(alice);
        uint256 sharesToRedeem = userShares / 2;

        // Alice must approve strategy to spend her shares
        vm.prank(alice);
        managedToken.approve(address(strategy), sharesToRedeem);

        vm.prank(address(strategy));
        vm.expectRevert(abi.encodeWithSelector(tRWA.HookCheckFailed.selector, "Redeem blocked by hook"));
        managedToken.redeem(sharesToRedeem, alice, alice);
    }

    // ============ Constructor Tests ============

    function test_Constructor() public {
        // Create a new strategy for this test
        MockManagedStrategy newStrategy = new MockManagedStrategy();
        newStrategy.initialize("Test Token", "TEST", address(roleManager), manager, address(usdc), 6, "");

        ManagedWithdrawRWA newToken =
            new ManagedWithdrawRWA("Test Token", "TEST", address(usdc), 6, address(newStrategy));

        // Set the token in the strategy
        newStrategy.setSToken(address(newToken));

        assertEq(newToken.name(), "Test Token");
        assertEq(newToken.symbol(), "TEST");
        assertEq(newToken.asset(), address(usdc));
        assertEq(newToken.decimals(), 18); // ERC4626 always uses 18 decimals
        assertEq(newToken.strategy(), address(newStrategy));
    }

    // ============ Withdrawal Restriction Tests ============

    function test_Withdraw_AlwaysReverts() public {
        uint256 assets = 1000 * 10 ** 6;

        vm.prank(address(strategy));
        vm.expectRevert(ManagedWithdrawRWA.UseRedeem.selector);
        managedToken.withdraw(assets, alice, alice);
    }

    function test_Withdraw_AlwaysRevertsWithDifferentParams() public {
        uint256 assets = 500 * 10 ** 6;

        vm.prank(address(strategy));
        vm.expectRevert(ManagedWithdrawRWA.UseRedeem.selector);
        managedToken.withdraw(assets, bob, charlie);
    }

    // ============ Redemption Tests ============

    function test_Redeem_Success() public {
        // Setup initial deposit
        _depositAsUser(alice, INITIAL_SUPPLY / 2);

        uint256 userShares = managedToken.balanceOf(alice);
        uint256 sharesToRedeem = userShares / 2;
        uint256 expectedAssets = managedToken.previewRedeem(sharesToRedeem);

        // Alice must approve strategy to spend her shares
        vm.prank(alice);
        managedToken.approve(address(strategy), sharesToRedeem);

        uint256 aliceBalanceBefore = usdc.balanceOf(alice);

        vm.prank(address(strategy));
        uint256 assetsRedeemed = managedToken.redeem(sharesToRedeem, alice, alice);

        assertEq(assetsRedeemed, expectedAssets);
        assertEq(usdc.balanceOf(alice), aliceBalanceBefore + assetsRedeemed);
        assertEq(managedToken.balanceOf(alice), userShares - sharesToRedeem);
    }

    function test_Redeem_ExceedsMaxRedeem() public {
        // Setup initial deposit
        _depositAsUser(alice, INITIAL_SUPPLY / 2);

        uint256 maxRedeemable = managedToken.maxRedeem(alice);
        uint256 excessiveShares = maxRedeemable + 1;

        vm.prank(alice);
        managedToken.approve(address(strategy), excessiveShares);

        vm.prank(address(strategy));
        vm.expectRevert(abi.encodeWithSelector(ERC4626.RedeemMoreThanMax.selector));
        managedToken.redeem(excessiveShares, alice, alice);
    }

    function test_Redeem_UnauthorizedCaller() public {
        uint256 sharesToRedeem = 1000;

        vm.prank(alice); // Not strategy
        vm.expectRevert(abi.encodeWithSelector(tRWA.NotStrategyAdmin.selector)); // Should revert - only strategy can call
        managedToken.redeem(sharesToRedeem, alice, alice);
    }

    function test_Redeem_WithMinAssets_Success() public {
        // Setup initial deposit
        _depositAsUser(alice, INITIAL_SUPPLY / 2);

        uint256 userShares = managedToken.balanceOf(alice);
        uint256 sharesToRedeem = userShares / 3;
        uint256 expectedAssets = managedToken.previewRedeem(sharesToRedeem);
        uint256 minAssets = expectedAssets - 100; // Set minimum slightly below expected

        vm.prank(alice);
        managedToken.approve(address(strategy), sharesToRedeem);

        uint256 aliceBalanceBefore = usdc.balanceOf(alice);

        vm.prank(address(strategy));
        uint256 assetsRedeemed = managedToken.redeem(sharesToRedeem, alice, alice, minAssets);

        assertEq(assetsRedeemed, expectedAssets);
        assertEq(usdc.balanceOf(alice), aliceBalanceBefore + assetsRedeemed);
        assertEq(managedToken.balanceOf(alice), userShares - sharesToRedeem);
    }

    function test_Redeem_WithMinAssets_InsufficientAssets() public {
        // Setup initial deposit
        _depositAsUser(alice, INITIAL_SUPPLY / 2);

        uint256 userShares = managedToken.balanceOf(alice);
        uint256 sharesToRedeem = userShares / 3;
        uint256 expectedAssets = managedToken.previewRedeem(sharesToRedeem);
        uint256 minAssets = expectedAssets + 1000; // Set minimum above expected

        vm.prank(alice);
        managedToken.approve(address(strategy), sharesToRedeem);

        vm.prank(address(strategy));
        vm.expectRevert(ManagedWithdrawRWA.InsufficientOutputAssets.selector);
        managedToken.redeem(sharesToRedeem, alice, alice, minAssets);
    }

    function test_Redeem_WithMinAssets_ExceedsMaxRedeem() public {
        // Setup initial deposit
        _depositAsUser(alice, INITIAL_SUPPLY / 2);

        uint256 maxRedeemable = managedToken.maxRedeem(alice);
        uint256 excessiveShares = maxRedeemable + 1;
        uint256 minAssets = 0;

        vm.prank(alice);
        managedToken.approve(address(strategy), excessiveShares);

        vm.prank(address(strategy));
        vm.expectRevert(abi.encodeWithSelector(ERC4626.RedeemMoreThanMax.selector)); // Should revert with RedeemMoreThanMax
        managedToken.redeem(excessiveShares, alice, alice, minAssets);
    }

    // ============ Batch Redemption Tests ============

    function test_BatchRedeemShares_Success() public {
        // Setup initial deposits for all users
        _depositAsUser(alice, INITIAL_SUPPLY / 2);
        _depositAsUser(bob, INITIAL_SUPPLY / 3);
        _depositAsUser(charlie, INITIAL_SUPPLY / 4);

        // Setup batch redemption for multiple users
        uint256[] memory shares = new uint256[](3);
        address[] memory recipients = new address[](3);
        address[] memory owners = new address[](3);
        uint256[] memory minAssets = new uint256[](3);

        shares[0] = managedToken.balanceOf(alice) / 2;
        shares[1] = managedToken.balanceOf(bob) / 3;
        shares[2] = managedToken.balanceOf(charlie) / 4;

        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = charlie;

        owners[0] = alice;
        owners[1] = bob;
        owners[2] = charlie;

        minAssets[0] = managedToken.previewRedeem(shares[0]) - 100;
        minAssets[1] = managedToken.previewRedeem(shares[1]) - 50;
        minAssets[2] = managedToken.previewRedeem(shares[2]) - 25;

        // Users approve strategy
        vm.prank(alice);
        managedToken.approve(address(strategy), shares[0]);
        vm.prank(bob);
        managedToken.approve(address(strategy), shares[1]);
        vm.prank(charlie);
        managedToken.approve(address(strategy), shares[2]);

        // Record balances before
        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        uint256 bobBalanceBefore = usdc.balanceOf(bob);
        uint256 charlieBalanceBefore = usdc.balanceOf(charlie);

        uint256 aliceSharesBefore = managedToken.balanceOf(alice);
        uint256 bobSharesBefore = managedToken.balanceOf(bob);
        uint256 charlieSharesBefore = managedToken.balanceOf(charlie);

        vm.prank(address(strategy));
        uint256[] memory assetsRedeemed = managedToken.batchRedeemShares(shares, recipients, owners, minAssets);

        // Verify assets were transferred correctly
        assertEq(usdc.balanceOf(alice), aliceBalanceBefore + assetsRedeemed[0]);
        assertEq(usdc.balanceOf(bob), bobBalanceBefore + assetsRedeemed[1]);
        assertEq(usdc.balanceOf(charlie), charlieBalanceBefore + assetsRedeemed[2]);

        // Verify shares were burned
        assertEq(managedToken.balanceOf(alice), aliceSharesBefore - shares[0]);
        assertEq(managedToken.balanceOf(bob), bobSharesBefore - shares[1]);
        assertEq(managedToken.balanceOf(charlie), charlieSharesBefore - shares[2]);

        // Verify assets are reasonable
        assertGt(assetsRedeemed[0], minAssets[0]);
        assertGt(assetsRedeemed[1], minAssets[1]);
        assertGt(assetsRedeemed[2], minAssets[2]);
    }

    function test_BatchRedeemShares_InvalidArrayLengths() public {
        uint256[] memory shares = new uint256[](2);
        address[] memory recipients = new address[](3); // Different length
        address[] memory owners = new address[](2);
        uint256[] memory minAssets = new uint256[](2);

        vm.prank(address(strategy));
        vm.expectRevert(ManagedWithdrawRWA.InvalidArrayLengths.selector);
        managedToken.batchRedeemShares(shares, recipients, owners, minAssets);
    }

    function test_BatchRedeemShares_InvalidArrayLengthsOwners() public {
        uint256[] memory shares = new uint256[](2);
        address[] memory recipients = new address[](2);
        address[] memory owners = new address[](3); // Different length
        uint256[] memory minAssets = new uint256[](2);

        vm.prank(address(strategy));
        vm.expectRevert(ManagedWithdrawRWA.InvalidArrayLengths.selector);
        managedToken.batchRedeemShares(shares, recipients, owners, minAssets);
    }

    function test_BatchRedeemShares_InvalidArrayLengthsMinAssets() public {
        uint256[] memory shares = new uint256[](2);
        address[] memory recipients = new address[](2);
        address[] memory owners = new address[](2);
        uint256[] memory minAssets = new uint256[](1); // Different length

        vm.prank(address(strategy));
        vm.expectRevert(ManagedWithdrawRWA.InvalidArrayLengths.selector);
        managedToken.batchRedeemShares(shares, recipients, owners, minAssets);
    }

    function test_BatchRedeemShares_InsufficientAssets() public {
        // Setup initial deposit
        _depositAsUser(alice, INITIAL_SUPPLY / 2);

        uint256[] memory shares = new uint256[](1);
        address[] memory recipients = new address[](1);
        address[] memory owners = new address[](1);
        uint256[] memory minAssets = new uint256[](1);

        shares[0] = managedToken.balanceOf(alice) / 2;
        recipients[0] = alice;
        owners[0] = alice;
        minAssets[0] = managedToken.previewRedeem(shares[0]) + 1000000; // Set unreasonably high

        vm.prank(alice);
        managedToken.approve(address(strategy), shares[0]);

        vm.prank(address(strategy));
        vm.expectRevert(ManagedWithdrawRWA.InsufficientOutputAssets.selector);
        managedToken.batchRedeemShares(shares, recipients, owners, minAssets);
    }

    function test_BatchRedeemShares_UnauthorizedCaller() public {
        uint256[] memory shares = new uint256[](1);
        address[] memory recipients = new address[](1);
        address[] memory owners = new address[](1);
        uint256[] memory minAssets = new uint256[](1);

        vm.prank(alice); // Not strategy
        vm.expectRevert(abi.encodeWithSelector(tRWA.NotStrategyAdmin.selector)); // Should revert - only strategy can call
        managedToken.batchRedeemShares(shares, recipients, owners, minAssets);
    }

    function test_BatchRedeemShares_EmptyArrays() public {
        uint256[] memory shares = new uint256[](0);
        address[] memory recipients = new address[](0);
        address[] memory owners = new address[](0);
        uint256[] memory minAssets = new uint256[](0);

        vm.prank(address(strategy));
        uint256[] memory assetsRedeemed = managedToken.batchRedeemShares(shares, recipients, owners, minAssets);

        assertEq(assetsRedeemed.length, 0);
    }

    // ============ Asset Collection Tests ============

    function test_Collect_Internal() public {
        // Setup initial deposit
        _depositAsUser(alice, INITIAL_SUPPLY / 2);

        // This tests the internal _collect function indirectly through redeem
        uint256 userShares = managedToken.balanceOf(alice);
        uint256 sharesToRedeem = userShares / 4;

        vm.prank(alice);
        managedToken.approve(address(strategy), sharesToRedeem);

        uint256 strategyBalanceBefore = usdc.balanceOf(address(strategy));
        uint256 aliceBalanceBefore = usdc.balanceOf(alice);

        // Calculate expected assets before redeem
        uint256 expectedAssets = managedToken.previewRedeem(sharesToRedeem);

        vm.prank(address(strategy));
        uint256 actualAssets = managedToken.redeem(sharesToRedeem, alice, alice);

        // Verify assets were collected from strategy and transferred to alice
        assertEq(actualAssets, expectedAssets, "Actual assets != expected");
        assertEq(usdc.balanceOf(address(strategy)), strategyBalanceBefore - actualAssets, "Strategy balance incorrect");
        assertEq(usdc.balanceOf(alice), aliceBalanceBefore + actualAssets, "Alice balance incorrect");
        // Token contract should have 0 balance (all transferred to alice)
        assertEq(usdc.balanceOf(address(managedToken)), 0, "Token contract should have 0 balance");
    }

    // ============ Integration Tests ============

    function test_CompleteRedemptionFlow() public {
        // Setup initial deposit
        _depositAsUser(alice, INITIAL_SUPPLY / 2);

        uint256 initialAliceShares = managedToken.balanceOf(alice);
        uint256 initialAliceAssets = usdc.balanceOf(alice);

        // Redeem all of Alice's shares
        vm.prank(alice);
        managedToken.approve(address(strategy), initialAliceShares);

        vm.prank(address(strategy));
        uint256 assetsRedeemed = managedToken.redeem(initialAliceShares, alice, alice);

        // Alice should have no shares left
        assertEq(managedToken.balanceOf(alice), 0);

        // Alice should have received assets
        assertEq(usdc.balanceOf(alice), initialAliceAssets + assetsRedeemed);

        // Verify assets redeemed is reasonable (should be close to what she originally deposited)
        assertGt(assetsRedeemed, 0);
    }

    function test_ProportionalRedemption() public {
        // Setup initial deposits
        _depositAsUser(alice, INITIAL_SUPPLY / 2);
        _depositAsUser(bob, INITIAL_SUPPLY / 3);

        // Test that redemption amounts are proportional to shares
        uint256 aliceShares = managedToken.balanceOf(alice);
        uint256 bobShares = managedToken.balanceOf(bob);

        uint256 aliceRedeem = aliceShares / 2;
        uint256 bobRedeem = bobShares / 2;

        vm.prank(alice);
        managedToken.approve(address(strategy), aliceRedeem);
        vm.prank(bob);
        managedToken.approve(address(strategy), bobRedeem);

        vm.prank(address(strategy));
        uint256 aliceAssets = managedToken.redeem(aliceRedeem, alice, alice);

        vm.prank(address(strategy));
        uint256 bobAssets = managedToken.redeem(bobRedeem, bob, bob);

        // The ratio of assets should be close to the ratio of shares
        // (allowing for rounding differences due to decimal conversions)
        uint256 expectedRatio = (aliceRedeem * 1e18) / bobRedeem;
        uint256 actualRatio = (aliceAssets * 1e18) / bobAssets;

        // Allow 10% difference for rounding (due to USDC 6 decimals to shares 18 decimals conversion)
        uint256 diff = expectedRatio > actualRatio ? expectedRatio - actualRatio : actualRatio - expectedRatio;
        assertLt(diff, expectedRatio / 10); // Less than 10% difference
    }

    // ============ RedeemMoreThanMax Tests ============

    function test_Redeem_RedeemMoreThanMax() public {
        // Setup initial deposit
        _depositAsUser(alice, INITIAL_SUPPLY / 2);

        uint256 aliceShares = managedToken.balanceOf(alice);
        uint256 tooManyShares = aliceShares + 1;

        // Alice approves strategy to spend her shares
        vm.prank(alice);
        managedToken.approve(address(strategy), tooManyShares);

        // Try to redeem more shares than alice has
        vm.prank(address(strategy));
        vm.expectRevert(ERC4626.RedeemMoreThanMax.selector);
        managedToken.redeem(tooManyShares, alice, alice);
    }

    function test_RedeemWithMinAssets_RedeemMoreThanMax() public {
        // Setup initial deposit
        _depositAsUser(alice, INITIAL_SUPPLY / 2);

        uint256 aliceShares = managedToken.balanceOf(alice);
        uint256 tooManyShares = aliceShares + 1;

        // Alice approves strategy to spend her shares
        vm.prank(alice);
        managedToken.approve(address(strategy), tooManyShares);

        // Try to redeem more shares than alice has with minAssets check
        vm.prank(address(strategy));
        vm.expectRevert(ERC4626.RedeemMoreThanMax.selector);
        managedToken.redeem(tooManyShares, alice, alice, 0);
    }

    function test_BatchRedeemShares_RedeemMoreThanMax() public {
        // Setup initial deposits
        _depositAsUser(alice, INITIAL_SUPPLY / 4);
        _depositAsUser(bob, INITIAL_SUPPLY / 4);

        uint256 aliceShares = managedToken.balanceOf(alice);
        uint256 bobShares = managedToken.balanceOf(bob);

        // Prepare batch arrays with one user trying to redeem too much
        uint256[] memory shares = new uint256[](2);
        shares[0] = aliceShares + 1; // Too many shares for alice
        shares[1] = bobShares / 2;

        address[] memory to = new address[](2);
        to[0] = alice;
        to[1] = bob;

        address[] memory owners = new address[](2);
        owners[0] = alice;
        owners[1] = bob;

        uint256[] memory minAssets = new uint256[](2);
        minAssets[0] = 0;
        minAssets[1] = 0;

        // Approve strategy to spend shares
        vm.prank(alice);
        managedToken.approve(address(strategy), aliceShares + 1);
        vm.prank(bob);
        managedToken.approve(address(strategy), bobShares / 2);

        // Try batch redeem with one user having too many shares
        vm.prank(address(strategy));
        vm.expectRevert(ERC4626.RedeemMoreThanMax.selector);
        managedToken.batchRedeemShares(shares, to, owners, minAssets);
    }

    function test_Withdraw_WithHooks() public {
        // Setup initial deposit
        _depositAsUser(alice, INITIAL_SUPPLY / 2);

        // Create and add a hook that tracks withdraw operations
        TrackingHook trackingHook = new TrackingHook();

        vm.prank(address(strategy));
        managedToken.addOperationHook(OP_WITHDRAW, address(trackingHook));

        uint256 userShares = managedToken.balanceOf(alice);
        uint256 sharesToRedeem = userShares / 2;

        // Alice must approve strategy to spend her shares
        vm.prank(alice);
        managedToken.approve(address(strategy), sharesToRedeem);

        // Perform the redeem which will trigger _withdraw with hooks
        vm.prank(address(strategy));
        uint256 assetsRedeemed = managedToken.redeem(sharesToRedeem, alice, alice);

        // Verify the hook was called
        assertTrue(trackingHook.wasWithdrawCalled());
        assertEq(trackingHook.lastWithdrawToken(), address(managedToken));
        assertEq(trackingHook.lastWithdrawOperator(), address(strategy));
        assertEq(trackingHook.lastWithdrawAssets(), assetsRedeemed);
        assertEq(trackingHook.lastWithdrawReceiver(), alice);
        assertEq(trackingHook.lastWithdrawOwner(), alice);
    }

    function test_Withdraw_MultipleHooks() public {
        // Setup initial deposit
        _depositAsUser(alice, INITIAL_SUPPLY / 2);

        // Create and add multiple hooks
        TrackingHook hook1 = new TrackingHook();
        TrackingHook hook2 = new TrackingHook();

        vm.startPrank(address(strategy));
        managedToken.addOperationHook(OP_WITHDRAW, address(hook1));
        managedToken.addOperationHook(OP_WITHDRAW, address(hook2));
        vm.stopPrank();

        uint256 userShares = managedToken.balanceOf(alice);
        uint256 sharesToRedeem = userShares / 2;

        // Alice must approve strategy to spend her shares
        vm.prank(alice);
        managedToken.approve(address(strategy), sharesToRedeem);

        // Perform the redeem which will trigger _withdraw with hooks
        vm.prank(address(strategy));
        managedToken.redeem(sharesToRedeem, alice, alice);

        // Verify both hooks were called
        assertTrue(hook1.wasWithdrawCalled());
        assertTrue(hook2.wasWithdrawCalled());
    }

    function test_BatchRedeemShares_WithHooks() public {
        // Setup initial deposits
        _depositAsUser(alice, INITIAL_SUPPLY / 4);
        _depositAsUser(bob, INITIAL_SUPPLY / 4);

        // Create and add a hook that tracks withdraw operations
        TrackingHook trackingHook = new TrackingHook();

        vm.prank(address(strategy));
        managedToken.addOperationHook(OP_WITHDRAW, address(trackingHook));

        uint256 aliceShares = managedToken.balanceOf(alice);
        uint256 bobShares = managedToken.balanceOf(bob);

        // Prepare batch arrays
        uint256[] memory shares = new uint256[](2);
        shares[0] = aliceShares / 2;
        shares[1] = bobShares / 2;

        address[] memory to = new address[](2);
        to[0] = alice;
        to[1] = bob;

        address[] memory owners = new address[](2);
        owners[0] = alice;
        owners[1] = bob;

        uint256[] memory minAssets = new uint256[](2);
        minAssets[0] = 0;
        minAssets[1] = 0;

        // Approve strategy to spend shares
        vm.prank(alice);
        managedToken.approve(address(strategy), aliceShares / 2);
        vm.prank(bob);
        managedToken.approve(address(strategy), bobShares / 2);

        // Perform batch redeem
        vm.prank(address(strategy));
        managedToken.batchRedeemShares(shares, to, owners, minAssets);

        // Verify the hook was called for each withdrawal
        assertTrue(trackingHook.wasWithdrawCalled());
        // The hook only stores the last call, but we can verify it was called
        assertEq(trackingHook.lastWithdrawToken(), address(managedToken));
        assertEq(trackingHook.lastWithdrawOperator(), address(strategy));
    }

    function test_BatchRedeemShares_WithFailingHook() public {
        // Setup initial deposits
        _depositAsUser(alice, INITIAL_SUPPLY / 4);
        _depositAsUser(bob, INITIAL_SUPPLY / 4);

        // Create a hook that rejects withdraw operations
        MockHook rejectingHook = new MockHook(false, "Batch withdrawal rejected");

        vm.prank(address(strategy));
        managedToken.addOperationHook(OP_WITHDRAW, address(rejectingHook));

        uint256 aliceShares = managedToken.balanceOf(alice);
        uint256 bobShares = managedToken.balanceOf(bob);

        // Prepare batch arrays
        uint256[] memory shares = new uint256[](2);
        shares[0] = aliceShares / 2;
        shares[1] = bobShares / 2;

        address[] memory to = new address[](2);
        to[0] = alice;
        to[1] = bob;

        address[] memory owners = new address[](2);
        owners[0] = alice;
        owners[1] = bob;

        uint256[] memory minAssets = new uint256[](2);
        minAssets[0] = 0;
        minAssets[1] = 0;

        // Approve strategy to spend shares
        vm.prank(alice);
        managedToken.approve(address(strategy), aliceShares / 2);
        vm.prank(bob);
        managedToken.approve(address(strategy), bobShares / 2);

        // Try batch redeem - should fail due to rejecting hook
        vm.prank(address(strategy));
        vm.expectRevert(abi.encodeWithSelector(tRWA.HookCheckFailed.selector, "Batch withdrawal rejected"));
        managedToken.batchRedeemShares(shares, to, owners, minAssets);
    }

    // ============ Helper Functions ============

    function _depositAsUser(address user, uint256 amount) internal {
        // ManagedWithdrawRWA inherits from tRWA, so it should support deposits
        // The key is that withdrawals are restricted, not deposits
        vm.startPrank(user);
        usdc.approve(address(mockConduit), amount);
        managedToken.deposit(amount, user);
        vm.stopPrank();
    }
}
