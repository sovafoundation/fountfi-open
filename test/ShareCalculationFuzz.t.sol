// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {BaseFountfiTest} from "./BaseFountfiTest.t.sol";
import {tRWA} from "../src/token/tRWA.sol";
import {FixedPointMathLib} from "../lib/solady/src/utils/FixedPointMathLib.sol";
import {MockStrategy} from "../src/mocks/MockStrategy.sol";
import {MockRegistry} from "../src/mocks/MockRegistry.sol";
import {MockConduit} from "../src/mocks/MockConduit.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {console2} from "forge-std/console2.sol";

contract ShareCalculationFuzzTest is BaseFountfiTest {
    using FixedPointMathLib for uint256;

    // Constants for precision testing
    uint256 constant PRECISION = 1e18;
    uint256 constant MAX_RELATIVE_ERROR = 1e15; // 0.1% max error

    // Test contracts
    tRWA internal token;
    RoleManager internal roleManager;
    MockConduit internal mockConduit;

    struct DepositWithdrawPair {
        address user;
        uint256 depositAmount;
        uint256 shares;
        uint256 withdrawAmount;
        uint256 timestamp;
    }

    DepositWithdrawPair[] private operations;

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

        // Register USDC as allowed asset
        mockRegistry.setAsset(address(usdc), 6);

        // Give users large amounts for testing (USDC has 6 decimals)
        vm.prank(owner);
        usdc.mint(alice, 1e30);
        vm.prank(owner);
        usdc.mint(bob, 1e30);
        vm.prank(owner);
        usdc.mint(charlie, 1e30);

        // Max approvals for both token and conduit
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
     * @notice Test share calculations remain accurate across different scales
     * @param scale The scale factor (10^n where n is 0 to 20)
     * @param deposits Array of deposit amounts at the given scale
     */
    function testFuzz_ShareCalculationAcrossScales(uint8 scale, uint256[3] memory deposits) public {
        scale = uint8(bound(scale, 0, 20));
        uint256 scaleFactor = 10 ** scale;

        // Bound deposits to reasonable ranges at the given scale
        for (uint256 i = 0; i < 3; i++) {
            deposits[i] = bound(deposits[i], 1, 1000) * scaleFactor;
        }

        // Track share prices at each step
        uint256[] memory sharePrices = new uint256[](4);
        sharePrices[0] = PRECISION; // Initial price is 1:1

        // First deposit (alice)
        vm.prank(alice);
        uint256 aliceShares = token.deposit(deposits[0], alice);
        sharePrices[1] = _calculateSharePrice();

        console2.log("Scale factor:", scaleFactor);
        console2.log("Alice deposited:", deposits[0]);
        console2.log("Alice shares:", aliceShares);
        console2.log("Share price after Alice:", sharePrices[1]);

        // Verify first deposit gets shares with proper decimal conversion
        // tRWA shares have 18 decimals, USDC has 6 decimals
        uint256 expectedShares = deposits[0] * 1e12; // Convert from 6 to 18 decimals
        assertEq(aliceShares, expectedShares, "First deposit should get properly scaled shares");

        // Second deposit (bob)
        vm.prank(bob);
        uint256 bobShares = token.deposit(deposits[1], bob);
        sharePrices[2] = _calculateSharePrice();

        console2.log("Bob deposited:", deposits[1]);
        console2.log("Bob shares:", bobShares);
        console2.log("Share price after Bob:", sharePrices[2]);

        // Verify share price stability
        assertApproxEqRel(sharePrices[2], sharePrices[1], MAX_RELATIVE_ERROR, "Share price changed after deposit");

        // Third deposit (charlie)
        vm.prank(charlie);
        uint256 charlieShares = token.deposit(deposits[2], charlie);
        sharePrices[3] = _calculateSharePrice();

        console2.log("Charlie deposited:", deposits[2]);
        console2.log("Charlie shares:", charlieShares);
        console2.log("Share price after Charlie:", sharePrices[3]);

        // Verify proportional ownership
        _verifyProportionalOwnership([aliceShares, bobShares, charlieShares], [deposits[0], deposits[1], deposits[2]]);
    }

    /**
     * @notice Test that rounding always favors the protocol (no value extraction)
     * @param amounts Random amounts to test rounding behavior
     */
    function testFuzz_RoundingFavorsProtocol(uint256[10] memory amounts) public {
        // Initial deposit to establish non-1:1 ratio
        vm.prank(alice);
        token.deposit(1000e18, alice);

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amount = bound(amounts[i], 1, 1e24);
            address user = i % 2 == 0 ? bob : charlie;

            // Test deposit rounding
            uint256 sharesBefore = token.totalSupply();
            uint256 assetsBefore = token.totalAssets();

            vm.prank(user);
            uint256 shares = token.deposit(amount, user);

            uint256 sharesAfter = token.totalSupply();
            uint256 assetsAfter = token.totalAssets();

            // Verify no value was created
            uint256 expectedShares = amount.mulDiv(sharesBefore, assetsBefore);
            assertLe(shares, expectedShares, "Deposit rounding created value");

            // Test withdrawal rounding
            if (shares > 0) {
                uint256 assetsReceived = token.convertToAssets(shares);
                uint256 expectedAssets = shares.mulDiv(assetsAfter, sharesAfter);
                assertLe(assetsReceived, expectedAssets, "Withdrawal rounding created value");
            }
        }
    }

    /**
     * @notice Test share calculations with extreme ratios
     * @param initialDeposit Large initial deposit to create extreme ratio
     * @param subsequentDeposits Small deposits to test precision
     */
    function testFuzz_ExtremeRatios(uint256 initialDeposit, uint256[5] memory subsequentDeposits) public {
        // Create extreme ratio with large initial deposit (USDC has 6 decimals)
        initialDeposit = bound(initialDeposit, 1e12, 1e16);

        vm.prank(alice);
        uint256 aliceShares = token.deposit(initialDeposit, alice);

        console2.log("Initial deposit:", initialDeposit);
        console2.log("Initial shares:", aliceShares);

        // Now test small deposits
        for (uint256 i = 0; i < 5; i++) {
            uint256 smallDeposit = bound(subsequentDeposits[i], 1, 1000);
            address user = i % 2 == 0 ? bob : charlie;

            uint256 expectedShares = token.convertToShares(smallDeposit);

            vm.prank(user);
            uint256 actualShares = token.deposit(smallDeposit, user);

            console2.log("Small deposit:", smallDeposit);
            console2.log("Expected vs actual shares:", expectedShares);

            // Verify shares are calculated correctly even with extreme ratios
            if (expectedShares > 0) {
                assertGe(actualShares, 1, "Small deposit should get at least 1 share");
                assertApproxEqRel(actualShares, expectedShares, MAX_RELATIVE_ERROR, "Share calculation error");
            }
        }
    }

    /**
     * @notice Test deposit/withdraw/deposit cycles maintain accuracy
     * @param deposits Array of deposit amounts for each cycle
     * @param withdrawFractions Array of withdrawal percentages for each cycle
     */
    function testFuzz_DepositWithdrawCycles(uint256[5] memory deposits, uint256[5] memory withdrawFractions) public {
        address[3] memory users = [alice, bob, charlie];
        uint256[3] memory userShares;

        for (uint256 cycle = 0; cycle < 5; cycle++) {
            // Deposit phase
            for (uint256 i = 0; i < 3; i++) {
                address user = users[i];
                uint256 depositAmount = bound(deposits[cycle], 100e6, 10000e6) * (i + 1);

                vm.prank(user);
                uint256 shares = token.deposit(depositAmount, user);
                userShares[i] += shares;

                operations.push(
                    DepositWithdrawPair({
                        user: user,
                        depositAmount: depositAmount,
                        shares: shares,
                        withdrawAmount: 0,
                        timestamp: block.timestamp
                    })
                );
            }

            // Withdraw phase (partial withdrawals)
            uint256 withdrawFraction = bound(withdrawFractions[cycle], 1, 50); // 1-50% withdrawal
            for (uint256 i = 0; i < 3; i++) {
                address user = users[i];
                uint256 sharesToRedeem = (userShares[i] * withdrawFraction) / 100;

                if (sharesToRedeem > 0) {
                    vm.prank(user);
                    uint256 assetsReceived = token.redeem(sharesToRedeem, user, user);
                    userShares[i] -= sharesToRedeem;

                    operations[operations.length - 3 + i].withdrawAmount = assetsReceived;
                }
            }

            // Verify consistency after each cycle
            _verifyConsistencyAfterCycle(cycle);
        }

        // Final verification
        _verifyFinalConsistency();
    }

    /**
     * @notice Test that share value never decreases (no negative yield)
     * @param numOperations Number of operations to perform
     * @param amounts Array of amounts for operations
     */
    function testFuzz_ShareValueMonotonicity(uint8 numOperations, uint256[20] memory amounts) public {
        numOperations = uint8(bound(numOperations, 5, 20));
        uint256 lastSharePrice = PRECISION;

        // Initial deposit (USDC has 6 decimals)
        vm.prank(alice);
        token.deposit(10000e6, alice);

        for (uint256 i = 0; i < numOperations; i++) {
            uint256 amount = bound(amounts[i], 100e6, 5000e6);
            address user = [alice, bob, charlie][i % 3];

            // Alternate between deposits and withdrawals
            if (i % 2 == 0) {
                vm.prank(user);
                token.deposit(amount, user);
            } else {
                uint256 userShares = token.balanceOf(user);
                if (userShares > 0) {
                    uint256 sharesToRedeem = userShares / 2;
                    vm.prank(user);
                    token.redeem(sharesToRedeem, user, user);
                }
            }

            uint256 currentSharePrice = _calculateSharePrice();
            console2.log("Share price:", currentSharePrice);

            // Share price should never decrease significantly (allow for minimal rounding)
            // Allow for 1 wei difference due to rounding in conversions
            if (currentSharePrice < lastSharePrice) {
                uint256 diff = lastSharePrice - currentSharePrice;
                assertLe(diff, 1, "Share price decreased significantly");
            }
            lastSharePrice = currentSharePrice;
        }
    }

    /**
     * @notice Test precision with very small and very large numbers
     * @param verySmall Very small deposit amount
     * @param veryLarge Very large deposit amount
     */
    function testFuzz_ExtremePrecision(uint256 verySmall, uint256 veryLarge) public {
        verySmall = bound(verySmall, 1, 1000); // 1 wei to 1000 wei
        veryLarge = bound(veryLarge, 1e15, 1e17); // Very large amounts (USDC decimals)

        // Test very large deposit first
        vm.prank(alice);
        uint256 largeShares = token.deposit(veryLarge, alice);

        assertTrue(largeShares > 0, "Large deposit failed");
        assertEq(token.convertToAssets(largeShares), veryLarge, "Large deposit conversion error");

        // Test very small deposit
        vm.prank(bob);
        uint256 smallShares = token.deposit(verySmall, bob);

        // Small deposits might get 0 shares due to rounding
        if (smallShares > 0) {
            uint256 convertedAssets = token.convertToAssets(smallShares);
            assertGe(convertedAssets, verySmall, "Small deposit lost value");
        }

        // Test that large depositor's value is unaffected
        uint256 aliceAssets = token.convertToAssets(largeShares);
        assertApproxEqRel(aliceAssets, veryLarge, MAX_RELATIVE_ERROR, "Large deposit value affected");
    }

    // Helper functions

    function _calculateSharePrice() private view returns (uint256) {
        uint256 totalShares = token.totalSupply();
        uint256 totalAssets = token.totalAssets();

        if (totalShares == 0) return PRECISION;
        // Convert totalAssets from 6 decimals to 18 decimals for price calculation
        return (totalAssets * 1e12).mulDiv(PRECISION, totalShares);
    }

    function _verifyProportionalOwnership(uint256[3] memory shares, uint256[3] memory deposits) private pure {
        uint256 totalShares = shares[0] + shares[1] + shares[2];
        uint256 totalDeposits = deposits[0] + deposits[1] + deposits[2];

        for (uint256 i = 0; i < 3; i++) {
            if (shares[i] > 0) {
                uint256 expectedProportion = deposits[i].mulDiv(PRECISION, totalDeposits);
                uint256 actualProportion = shares[i].mulDiv(PRECISION, totalShares);

                assertApproxEqRel(
                    actualProportion, expectedProportion, MAX_RELATIVE_ERROR, "Proportional ownership violated"
                );
            }
        }
    }

    function _verifyConsistencyAfterCycle(uint256 cycle) private view {
        console2.log("=== Cycle", cycle, "Verification ===");

        uint256 totalShares = token.totalSupply();
        uint256 totalAssets = token.totalAssets();
        uint256 sharePrice = _calculateSharePrice();

        console2.log("Total shares:", totalShares);
        console2.log("Total assets:", totalAssets);
        console2.log("Share price:", sharePrice);

        // Verify sum of user balances equals total supply
        uint256 sumBalances = token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(charlie);
        assertEq(sumBalances, totalShares, "Balance sum mismatch");

        // Verify conversions are consistent
        if (totalShares > 0) {
            uint256 testAmount = 1000e18;
            uint256 sharesToAssets = token.convertToAssets(token.convertToShares(testAmount));
            assertApproxEqRel(sharesToAssets, testAmount, MAX_RELATIVE_ERROR, "Conversion consistency error");
        }
    }

    function _verifyFinalConsistency() private view {
        console2.log("=== Final Consistency Check ===");

        // Calculate total deposits and withdrawals
        uint256 totalDeposited;
        uint256 totalWithdrawn;

        for (uint256 i = 0; i < operations.length; i++) {
            totalDeposited += operations[i].depositAmount;
            totalWithdrawn += operations[i].withdrawAmount;
        }

        uint256 expectedAssets = totalDeposited - totalWithdrawn;
        uint256 actualAssets = token.totalAssets();

        console2.log("Total deposited:", totalDeposited);
        console2.log("Total withdrawn:", totalWithdrawn);
        console2.log("Expected assets:", expectedAssets);
        console2.log("Actual assets:", actualAssets);

        assertApproxEqRel(actualAssets, expectedAssets, MAX_RELATIVE_ERROR, "Final asset mismatch");

        // Verify each user can withdraw their proportional share
        address[3] memory users = [alice, bob, charlie];
        for (uint256 i = 0; i < 3; i++) {
            address user = users[i];
            uint256 userShares = token.balanceOf(user);
            if (userShares > 0) {
                uint256 withdrawable = token.convertToAssets(userShares);
                uint256 maxWithdrawable = token.maxWithdraw(user);
                assertGe(maxWithdrawable, withdrawable, "Cannot withdraw proportional share");
            }
        }
    }
}
