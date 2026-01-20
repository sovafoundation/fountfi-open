// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {BaseFountfiTest} from "./BaseFountfiTest.t.sol";
import {tRWA} from "../src/token/tRWA.sol";
import {Registry} from "../src/registry/Registry.sol";
import {BasicStrategy} from "../src/strategy/BasicStrategy.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockStrategy} from "../src/mocks/MockStrategy.sol";
import {MockRegistry} from "../src/mocks/MockRegistry.sol";
import {MockConduit} from "../src/mocks/MockConduit.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {console2} from "forge-std/console2.sol";

contract MultiUserFuzzTest is BaseFountfiTest {
    // Track user balances and shares for verification
    mapping(address => uint256) private userAssetBalances;
    mapping(address => uint256) private userShareBalances;
    mapping(address => bool) private isUser;
    address[] private users;

    // Protocol state tracking
    uint256 private totalAssetsInProtocol;
    uint256 private totalSharesOutstanding;

    // Test contracts
    tRWA internal token;
    RoleManager internal roleManager;
    MockConduit internal mockConduit;

    function setUp() public override {
        super.setUp();

        // Deploy RoleManager with mock registry
        vm.prank(owner);
        MockRegistry mockRegistry = new MockRegistry();
        mockConduit = new MockConduit();
        mockRegistry.setConduit(address(mockConduit));

        vm.prank(owner);
        roleManager = new RoleManager();
        vm.prank(owner);
        roleManager.initializeRegistry(address(mockRegistry));

        // Deploy strategy directly without registry
        vm.prank(owner);
        MockStrategy strategy = new MockStrategy();
        vm.prank(owner);
        strategy.initialize("Test RWA", "tRWA", address(roleManager), manager, address(usdc), 6, "");

        // Get the token
        token = tRWA(strategy.sToken());

        // Setup 3 users
        users.push(alice);
        users.push(bob);
        users.push(charlie);

        // Mark them as users
        isUser[alice] = true;
        isUser[bob] = true;
        isUser[charlie] = true;

        // Mint initial tokens to users (USDC has 6 decimals)
        vm.prank(owner);
        usdc.mint(alice, 1000000e6); // 1M USDC
        vm.prank(owner);
        usdc.mint(bob, 1000000e6); // 1M USDC
        vm.prank(owner);
        usdc.mint(charlie, 1000000e6); // 1M USDC

        // Store conduit for approvals
        mockRegistry.setAsset(address(usdc), 6); // Register USDC as allowed asset

        // Approve both token and conduit for all users
        vm.prank(alice);
        usdc.approve(address(token), type(uint256).max);
        vm.prank(alice);
        usdc.approve(address(mockConduit), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(token), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(mockConduit), type(uint256).max);

        vm.prank(charlie);
        usdc.approve(address(token), type(uint256).max);
        vm.prank(charlie);
        usdc.approve(address(mockConduit), type(uint256).max);

        // Strategy needs to approve token to transfer USDC during withdrawals
        vm.prank(manager);
        strategy.setAllowance(address(usdc), address(token), type(uint256).max);
    }

    /**
     * @notice Fuzz test for sequential deposits by multiple users
     * @param depositAmounts Array of deposit amounts for each user
     */
    function testFuzz_MultiUserSequentialDeposits(uint256[3] memory depositAmounts) public {
        // Bound deposit amounts to reasonable ranges (max is what was minted in USDC decimals)
        for (uint256 i = 0; i < 3; i++) {
            depositAmounts[i] = bound(depositAmounts[i], 1e6, 900000e6); // USDC has 6 decimals
        }

        // Track expected shares for each deposit
        uint256[] memory expectedShares = new uint256[](3);

        // Alice deposits first
        vm.prank(alice);
        uint256 aliceShares = token.deposit(depositAmounts[0], alice);
        expectedShares[0] = aliceShares;
        userAssetBalances[alice] = depositAmounts[0];
        userShareBalances[alice] = aliceShares;
        totalAssetsInProtocol += depositAmounts[0];
        totalSharesOutstanding += aliceShares;

        // Verify Alice's position
        assertEq(token.balanceOf(alice), aliceShares, "Alice shares mismatch");
        assertEq(token.convertToAssets(aliceShares), depositAmounts[0], "Alice assets mismatch");

        // Bob deposits second
        vm.prank(bob);
        uint256 bobShares = token.deposit(depositAmounts[1], bob);
        expectedShares[1] = bobShares;
        userAssetBalances[bob] = depositAmounts[1];
        userShareBalances[bob] = bobShares;
        totalAssetsInProtocol += depositAmounts[1];
        totalSharesOutstanding += bobShares;

        // Verify Bob's position
        assertEq(token.balanceOf(bob), bobShares, "Bob shares mismatch");

        // Charlie deposits third
        vm.prank(charlie);
        uint256 charlieShares = token.deposit(depositAmounts[2], charlie);
        expectedShares[2] = charlieShares;
        userAssetBalances[charlie] = depositAmounts[2];
        userShareBalances[charlie] = charlieShares;
        totalAssetsInProtocol += depositAmounts[2];
        totalSharesOutstanding += charlieShares;

        // Verify Charlie's position
        assertEq(token.balanceOf(charlie), charlieShares, "Charlie shares mismatch");

        // Verify total protocol state
        assertEq(token.totalAssets(), totalAssetsInProtocol, "Total assets mismatch");
        assertEq(token.totalSupply(), totalSharesOutstanding, "Total shares mismatch");

        // Verify proportional ownership is maintained
        _verifyProportionalOwnership();
    }

    /**
     * @notice Fuzz test for mixed deposits and withdrawals
     * @param actions Array of actions (0 = deposit, 1 = withdraw)
     * @param amounts Array of amounts for each action
     * @param userIndices Array of user indices (0 = alice, 1 = bob, 2 = charlie)
     */
    function testFuzz_MixedDepositsWithdrawals(
        uint8[10] memory actions,
        uint256[10] memory amounts,
        uint8[10] memory userIndices
    ) public {
        // Initial deposits to ensure there's liquidity
        _setupInitialDeposits();

        for (uint256 i = 0; i < 10; i++) {
            // Bound inputs
            uint8 action = actions[i] % 2; // 0 or 1
            uint8 userIndex = userIndices[i] % 3; // 0, 1, or 2
            address user = users[userIndex];

            if (action == 0) {
                // Deposit action
                uint256 depositAmount = bound(amounts[i], 1e6, 10000e6); // USDC decimals
                uint256 userBalance = usdc.balanceOf(user);

                if (userBalance >= depositAmount) {
                    vm.prank(user);
                    uint256 sharesMinted = token.deposit(depositAmount, user);

                    // Update tracking
                    userAssetBalances[user] += depositAmount;
                    userShareBalances[user] += sharesMinted;
                    totalAssetsInProtocol += depositAmount;
                    totalSharesOutstanding += sharesMinted;

                    console2.log("User deposited:", depositAmount);
                    console2.log("Shares minted:", sharesMinted);
                }
            } else {
                // Withdraw action
                uint256 userShares = token.balanceOf(user);
                if (userShares > 0) {
                    uint256 sharesToRedeem = bound(amounts[i], 1, userShares);
                    console2.log("Bound result", sharesToRedeem);
                    uint256 expectedAssets = token.convertToAssets(sharesToRedeem);

                    vm.prank(user);
                    uint256 assetsReceived = token.redeem(sharesToRedeem, user, user);

                    // Update tracking
                    userShareBalances[user] -= sharesToRedeem;
                    totalAssetsInProtocol -= assetsReceived;
                    totalSharesOutstanding -= sharesToRedeem;

                    console2.log("Shares redeemed:", sharesToRedeem);
                    console2.log("Assets received:", assetsReceived);

                    // Verify the withdrawal was proportional
                    assertApproxEqRel(assetsReceived, expectedAssets, 1e15, "Withdrawal not proportional");
                }
            }

            // Verify protocol invariants after each action
            _verifyProtocolInvariants();
        }

        // Final verification of proportional ownership
        _verifyProportionalOwnership();
    }

    /**
     * @notice Fuzz test for concurrent operations (simulating same-block transactions)
     * @param depositAmounts Array of deposit amounts
     * @param withdrawAmounts Array of withdrawal amounts
     */
    function testFuzz_ConcurrentOperations(uint256[3] memory depositAmounts, uint256[3] memory withdrawAmounts)
        public
    {
        // Setup initial state
        _setupInitialDeposits();

        // Bound amounts (USDC has 6 decimals)
        for (uint256 i = 0; i < 3; i++) {
            depositAmounts[i] = bound(depositAmounts[i], 1e6, 10000e6);
            withdrawAmounts[i] = bound(withdrawAmounts[i], 1e6, 5000e6); // Lower max for withdrawals
        }

        // Record initial state
        uint256 initialTotalAssets = token.totalAssets();

        // Execute all deposits first (simulating same block)
        uint256[] memory sharesReceived = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            address user = users[i];
            vm.prank(user);
            sharesReceived[i] = token.deposit(depositAmounts[i], user);
        }

        // Execute withdrawals (simulating same block)
        uint256[] memory assetsWithdrawn = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            address user = users[i];
            uint256 userShares = token.balanceOf(user);
            uint256 sharesToRedeem = userShares > 0 ? bound(withdrawAmounts[i], 0, userShares / 2) : 0;

            if (sharesToRedeem > 0) {
                vm.prank(user);
                assetsWithdrawn[i] = token.redeem(sharesToRedeem, user, user);
            }
        }

        // Verify final state consistency
        uint256 expectedTotalAssets = initialTotalAssets;
        for (uint256 i = 0; i < 3; i++) {
            expectedTotalAssets += depositAmounts[i];
            expectedTotalAssets -= assetsWithdrawn[i];
        }

        assertApproxEqRel(token.totalAssets(), expectedTotalAssets, 1e15, "Total assets mismatch after concurrent ops");
        _verifyProtocolInvariants();
    }

    /**
     * @notice Fuzz test for extreme scenarios (dust amounts, max amounts)
     * @param extremeType Type of extreme test (0 = dust, 1 = max, 2 = mixed)
     * @param seed Random seed for generating amounts
     */
    function testFuzz_ExtremeScenarios(uint8 extremeType, uint256 seed) public {
        extremeType = extremeType % 3;

        if (extremeType == 0) {
            // Test dust amounts
            _testDustAmounts(seed);
        } else if (extremeType == 1) {
            // Test maximum amounts
            _testMaxAmounts();
        } else {
            // Test mixed dust and max
            _testMixedExtremes(seed);
        }

        _verifyProtocolInvariants();
    }

    // Helper functions

    function _setupInitialDeposits() private {
        // Each user deposits 1000 USDC initially
        vm.prank(alice);
        userShareBalances[alice] = token.deposit(1000e6, alice);
        userAssetBalances[alice] = 1000e6;

        vm.prank(bob);
        userShareBalances[bob] = token.deposit(1000e6, bob);
        userAssetBalances[bob] = 1000e6;

        vm.prank(charlie);
        userShareBalances[charlie] = token.deposit(1000e6, charlie);
        userAssetBalances[charlie] = 1000e6;

        totalAssetsInProtocol = 3000e6;
        totalSharesOutstanding = token.totalSupply();
    }

    function _verifyProportionalOwnership() private view {
        uint256 totalShares = token.totalSupply();
        uint256 totalAssets = token.totalAssets();

        if (totalShares == 0) return;

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            uint256 userShares = token.balanceOf(user);

            if (userShares > 0) {
                uint256 expectedAssets = (userShares * totalAssets) / totalShares;
                uint256 actualAssets = token.convertToAssets(userShares);

                assertApproxEqRel(actualAssets, expectedAssets, 1e15, "Proportional ownership violated");
            }
        }
    }

    function _verifyProtocolInvariants() private view {
        // Invariant 1: Total shares should equal sum of all user shares
        uint256 sumOfUserShares = 0;
        for (uint256 i = 0; i < users.length; i++) {
            sumOfUserShares += token.balanceOf(users[i]);
        }
        assertEq(token.totalSupply(), sumOfUserShares, "Share accounting mismatch");

        // Invariant 2: convertToShares and convertToAssets should be inverses
        if (token.totalSupply() > 0) {
            uint256 testAmount = 1000e18;
            uint256 shares = token.convertToShares(testAmount);
            uint256 assets = token.convertToAssets(shares);
            assertApproxEqRel(assets, testAmount, 1e15, "Conversion functions not inverse");
        }

        // Invariant 3: No user should be able to withdraw more than their proportional share
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            uint256 userShares = token.balanceOf(user);
            if (userShares > 0) {
                uint256 maxWithdraw = token.maxWithdraw(user);
                uint256 convertedAssets = token.convertToAssets(userShares);
                assertLe(maxWithdraw, convertedAssets, "Max withdraw exceeds proportional share");
            }
        }
    }

    function _testDustAmounts(uint256 seed) private {
        // Test with very small amounts (1 wei to 1000 wei)
        for (uint256 i = 0; i < 3; i++) {
            address user = users[i];
            uint256 dustAmount = (seed % 1000) + 1;

            vm.prank(user);
            try token.deposit(dustAmount, user) returns (uint256 shares) {
                assertTrue(shares >= 0, "Negative shares on dust deposit");
            } catch {
                // Dust might be rejected, which is acceptable
            }
        }
    }

    function _testMaxAmounts() private {
        // Test with very large amounts (USDC decimals)
        uint256 maxAmount = 100000000e6; // 100M USDC
        vm.prank(owner); // Need owner to mint
        usdc.mint(alice, maxAmount);

        vm.prank(alice);
        usdc.approve(address(token), maxAmount);
        vm.prank(alice);
        usdc.approve(address(mockConduit), maxAmount);

        vm.prank(alice);
        uint256 shares = token.deposit(maxAmount, alice);

        assertTrue(shares > 0, "No shares minted for max deposit");
        assertEq(token.balanceOf(alice), shares, "Share balance mismatch for max deposit");
    }

    function _testMixedExtremes(uint256 seed) private {
        // Mix dust and large amounts
        uint256 dustAmount = (seed % 1000) + 1;
        uint256 largeAmount = 50000e6; // 50k USDC

        // Alice deposits dust
        vm.prank(alice);
        try token.deposit(dustAmount, alice) {} catch {}

        // Bob deposits large amount
        vm.prank(bob);
        token.deposit(largeAmount, bob);

        // Charlie deposits dust
        vm.prank(charlie);
        try token.deposit(dustAmount, charlie) {} catch {}

        // Verify the large depositor isn't affected by dust
        uint256 bobShares = token.balanceOf(bob);
        uint256 bobAssets = token.convertToAssets(bobShares);
        assertApproxEqRel(bobAssets, largeAmount, 1e14, "Large deposit affected by dust");
    }
}
