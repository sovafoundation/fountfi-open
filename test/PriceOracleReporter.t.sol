// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {PriceOracleReporter} from "../src/reporter/PriceOracleReporter.sol";
import {Ownable} from "solady/auth/Ownable.sol";

contract PriceOracleReporterTest is Test {
    PriceOracleReporter public reporter;

    address public owner = makeAddr("owner");
    address public updater = makeAddr("updater");
    address public updater2 = makeAddr("updater2");
    address public unauthorized = makeAddr("unauthorized");

    uint256 constant INITIAL_PRICE = 1e18;
    uint256 constant MAX_DEVIATION = 1000; // 10%
    uint256 constant TIME_PERIOD = 60; // 1 minute

    event ForceCompleteTransition(uint256 roundNumber, uint256 targetPricePerShare);
    event PricePerShareUpdated(
        uint256 roundNumber, uint256 targetPricePerShare, uint256 startPricePerShare, string source
    );
    event SetUpdater(address indexed updater, bool isAuthorized);
    event MaxDeviationUpdated(uint256 oldMaxDeviation, uint256 newMaxDeviation, uint256 timePeriod);

    function setUp() public {
        vm.startPrank(owner);
        reporter = new PriceOracleReporter(INITIAL_PRICE, updater, MAX_DEVIATION, TIME_PERIOD);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR & INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public view {
        assertEq(reporter.getCurrentPrice(), INITIAL_PRICE);
        assertEq(reporter.targetPricePerShare(), INITIAL_PRICE);
        assertEq(reporter.transitionStartPrice(), INITIAL_PRICE);
        assertEq(reporter.currentRound(), 1);
        assertEq(reporter.maxDeviationPerTimePeriod(), MAX_DEVIATION);
        assertEq(reporter.deviationTimePeriod(), TIME_PERIOD);
        assertEq(reporter.lastUpdateAt(), block.timestamp);
        assertTrue(reporter.authorizedUpdaters(updater));
        assertEq(reporter.owner(), owner);
    }

    function test_Constructor_RevertInvalidMaxDeviation() public {
        vm.expectRevert(PriceOracleReporter.InvalidMaxDeviation.selector);
        new PriceOracleReporter(INITIAL_PRICE, updater, 0, TIME_PERIOD);
    }

    function test_Constructor_RevertInvalidTimePeriod() public {
        vm.expectRevert(PriceOracleReporter.InvalidTimePeriod.selector);
        new PriceOracleReporter(INITIAL_PRICE, updater, MAX_DEVIATION, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            PRICE UPDATES
    //////////////////////////////////////////////////////////////*/

    function test_Update_Basic() public {
        uint256 newPrice = 1.1e18;
        string memory source = "test";

        vm.expectEmit(true, true, true, true);
        emit PricePerShareUpdated(2, newPrice, INITIAL_PRICE, source);

        vm.prank(updater);
        reporter.update(newPrice, source);

        assertEq(reporter.currentRound(), 2);
        assertEq(reporter.targetPricePerShare(), newPrice);
        // Since 10% is within max deviation, it should do a direct update
        assertEq(reporter.transitionStartPrice(), newPrice);
        assertEq(reporter.getCurrentPrice(), newPrice);
        assertEq(reporter.lastUpdateAt(), block.timestamp);
    }

    function test_Update_ExceedsMaxDeviation() public {
        uint256 newPrice = 1.15e18; // 15% increase, exceeds 10% max
        string memory source = "test";

        vm.expectEmit(true, true, true, true);
        emit PricePerShareUpdated(2, newPrice, INITIAL_PRICE, source);

        vm.prank(updater);
        reporter.update(newPrice, source);

        assertEq(reporter.currentRound(), 2);
        assertEq(reporter.targetPricePerShare(), newPrice);
        // Should start a transition, not direct update
        assertEq(reporter.transitionStartPrice(), INITIAL_PRICE);
        assertEq(reporter.getCurrentPrice(), INITIAL_PRICE);
        assertEq(reporter.lastUpdateAt(), block.timestamp);
    }

    function test_Update_RevertUnauthorized() public {
        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(unauthorized);
        reporter.update(2e18, "test");
    }

    function test_Update_RevertInvalidSource() public {
        vm.expectRevert(PriceOracleReporter.InvalidSource.selector);
        vm.prank(updater);
        reporter.update(2e18, "");
    }

    function test_Update_DuringTransition() public {
        // First update
        vm.prank(updater);
        reporter.update(2e18, "test1");

        // Move forward 30 seconds (half time period)
        vm.warp(block.timestamp + 30);

        // Second update during transition
        uint256 currentPrice = reporter.getCurrentPrice();

        vm.expectEmit(true, true, true, true);
        emit PricePerShareUpdated(3, 1.5e18, currentPrice, "test2");

        vm.prank(updater);
        reporter.update(1.5e18, "test2");

        assertEq(reporter.getCurrentPrice(), currentPrice);
        assertEq(reporter.transitionStartPrice(), currentPrice);
        assertEq(reporter.targetPricePerShare(), 1.5e18);
    }

    /*//////////////////////////////////////////////////////////////
                        PRICE TRANSITIONS
    //////////////////////////////////////////////////////////////*/

    function test_GetCurrentPrice_NoTransition() public view {
        assertEq(reporter.getCurrentPrice(), INITIAL_PRICE);
    }

    function test_GetCurrentPrice_IncreasingTransition() public {
        vm.prank(updater);
        reporter.update(2e18, "test");

        // At start
        assertEq(reporter.getCurrentPrice(), INITIAL_PRICE);

        // After 30 seconds (0.5 periods) - should be 5% increase
        vm.warp(block.timestamp + 30);
        uint256 expectedPrice = INITIAL_PRICE + (INITIAL_PRICE * 500 / 10000);
        assertEq(reporter.getCurrentPrice(), expectedPrice);

        // After 60 seconds (1 period) - should be 10% increase
        vm.warp(block.timestamp + 30);
        expectedPrice = INITIAL_PRICE + (INITIAL_PRICE * 1000 / 10000);
        assertEq(reporter.getCurrentPrice(), expectedPrice);

        // After 600 seconds (10 periods) - should reach target
        vm.warp(block.timestamp + 540);
        assertEq(reporter.getCurrentPrice(), 2e18);
    }

    function test_GetCurrentPrice_DecreasingTransition() public {
        vm.prank(updater);
        reporter.update(0.5e18, "test");

        // After 60 seconds (1 period) - should be 10% decrease
        vm.warp(block.timestamp + 60);
        uint256 expectedPrice = INITIAL_PRICE - (INITIAL_PRICE * 1000 / 10000);
        assertEq(reporter.getCurrentPrice(), expectedPrice);

        // After 300 seconds (5 periods) - should reach target
        vm.warp(block.timestamp + 240);
        assertEq(reporter.getCurrentPrice(), 0.5e18);
    }

    function test_GetCurrentPrice_UnderflowProtection() public {
        // Update to very low price
        vm.prank(updater);
        reporter.update(1, "test");

        // After many periods, should not underflow
        vm.warp(block.timestamp + 10000);
        assertEq(reporter.getCurrentPrice(), 1);
    }

    function test_GetCurrentPrice_NoCap() public {
        vm.prank(updater);
        reporter.update(10e18, "test");

        // After 11 periods (110% change)
        vm.warp(block.timestamp + 660);
        uint256 expectedPrice = INITIAL_PRICE + (INITIAL_PRICE * 11000 / 10000); // 110% increase
        assertEq(reporter.getCurrentPrice(), expectedPrice);

        // After 90 periods (900% change), should reach target
        vm.warp(block.timestamp + 4740); // Additional 79 periods
        assertEq(reporter.getCurrentPrice(), 10e18);
    }

    /*//////////////////////////////////////////////////////////////
                        TRANSITION PROGRESS
    //////////////////////////////////////////////////////////////*/

    function test_GetTransitionProgress_Complete() public view {
        assertEq(reporter.getTransitionProgress(), 10000); // 100%
    }

    function test_GetTransitionProgress_InProgress() public {
        vm.prank(updater);
        reporter.update(2e18, "test");

        // At start
        assertEq(reporter.getTransitionProgress(), 0);

        // After 30 seconds (5% progress)
        vm.warp(block.timestamp + 30);
        assertEq(reporter.getTransitionProgress(), 500); // 5%

        // After 60 seconds (10% progress)
        vm.warp(block.timestamp + 30);
        assertEq(reporter.getTransitionProgress(), 1000); // 10%

        // After reaching target
        vm.warp(block.timestamp + 540);
        assertEq(reporter.getTransitionProgress(), 10000); // 100%
    }

    function test_GetTransitionProgress_Decreasing() public {
        vm.prank(updater);
        reporter.update(0.5e18, "test");

        // After 30 seconds (10% of 50% decrease = 5% total progress)
        vm.warp(block.timestamp + 30);
        assertEq(reporter.getTransitionProgress(), 1000); // 10% of the way

        // After 300 seconds (should be complete)
        vm.warp(block.timestamp + 270);
        assertEq(reporter.getTransitionProgress(), 10000); // 100%
    }

    /*//////////////////////////////////////////////////////////////
                            REPORTING
    //////////////////////////////////////////////////////////////*/

    function test_Report() public {
        bytes memory reportData = reporter.report();
        uint256 decodedPrice = abi.decode(reportData, (uint256));
        assertEq(decodedPrice, INITIAL_PRICE);

        // Update and check report reflects transition
        vm.prank(updater);
        reporter.update(2e18, "test");

        vm.warp(block.timestamp + 30);
        reportData = reporter.report();
        decodedPrice = abi.decode(reportData, (uint256));

        uint256 expectedPrice = INITIAL_PRICE + (INITIAL_PRICE * 500 / 10000);
        assertEq(decodedPrice, expectedPrice);
    }

    /*//////////////////////////////////////////////////////////////
                        OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_SetUpdater_Authorize() public {
        vm.expectEmit(true, true, true, true);
        emit SetUpdater(updater2, true);

        vm.prank(owner);
        reporter.setUpdater(updater2, true);

        assertTrue(reporter.authorizedUpdaters(updater2));

        // Test new updater can update
        vm.prank(updater2);
        reporter.update(2e18, "test");
    }

    function test_SetUpdater_Revoke() public {
        vm.expectEmit(true, true, true, true);
        emit SetUpdater(updater, false);

        vm.prank(owner);
        reporter.setUpdater(updater, false);

        assertFalse(reporter.authorizedUpdaters(updater));

        // Test revoked updater cannot update
        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(updater);
        reporter.update(2e18, "test");
    }

    function test_SetUpdater_RevertNotOwner() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        reporter.setUpdater(updater2, true);
    }

    function test_SetMaxDeviation() public {
        // Start a transition
        vm.prank(updater);
        reporter.update(2e18, "test");

        // Move forward
        vm.warp(block.timestamp + 30);
        uint256 currentPrice = reporter.getCurrentPrice();

        vm.expectEmit(true, true, true, true);
        emit MaxDeviationUpdated(MAX_DEVIATION, 500, 120);

        vm.prank(owner);
        reporter.setMaxDeviation(500, 120); // 5% per 2 minutes

        // Verify price was updated
        assertEq(reporter.getCurrentPrice(), currentPrice);
        assertEq(reporter.maxDeviationPerTimePeriod(), 500);
        assertEq(reporter.deviationTimePeriod(), 120);
    }

    function test_SetMaxDeviation_RevertInvalidMaxDeviation() public {
        vm.expectRevert(PriceOracleReporter.InvalidMaxDeviation.selector);
        vm.prank(owner);
        reporter.setMaxDeviation(0, 120);
    }

    function test_SetMaxDeviation_RevertInvalidTimePeriod() public {
        vm.expectRevert(PriceOracleReporter.InvalidTimePeriod.selector);
        vm.prank(owner);
        reporter.setMaxDeviation(500, 0);
    }

    function test_SetMaxDeviation_RevertNotOwner() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        reporter.setMaxDeviation(500, 120);
    }

    function test_ForceCompleteTransition() public {
        // Start a transition
        vm.prank(updater);
        reporter.update(2e18, "test");

        // Force complete
        vm.expectEmit(true, true, true, true);
        emit ForceCompleteTransition(2, 2e18);

        vm.prank(owner);
        reporter.forceCompleteTransition();

        assertEq(reporter.getCurrentPrice(), 2e18);
        assertEq(reporter.transitionStartPrice(), 2e18);
        assertEq(reporter.targetPricePerShare(), 2e18);
        assertEq(reporter.lastUpdateAt(), block.timestamp);
    }

    function test_ForceCompleteTransition_RevertNotOwner() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        reporter.forceCompleteTransition();
    }

    /*//////////////////////////////////////////////////////////////
                            INTEGRATION
    //////////////////////////////////////////////////////////////*/

    function test_MultipleTransitions() public {
        // First transition up (50% increase)
        vm.prank(updater);
        reporter.update(1.5e18, "up");

        vm.warp(block.timestamp + 300); // Complete transition
        assertEq(reporter.getCurrentPrice(), 1.5e18);

        // Second transition down (33% decrease)
        vm.prank(updater);
        reporter.update(1e18, "down");

        vm.warp(block.timestamp + 300); // Complete transition
        assertEq(reporter.getCurrentPrice(), 1e18);

        // Third transition up (200% increase)
        vm.prank(updater);
        reporter.update(3e18, "up");

        vm.warp(block.timestamp + 1200); // 20 periods = 200% change
        assertEq(reporter.getCurrentPrice(), 3e18); // Should reach target
    }

    function test_RapidUpdates() public {
        // Multiple updates in quick succession
        vm.startPrank(updater);

        reporter.update(1.1e18, "1");
        reporter.update(1.2e18, "2");
        reporter.update(1.3e18, "3");

        vm.stopPrank();

        assertEq(reporter.currentRound(), 4);
        assertEq(reporter.targetPricePerShare(), 1.3e18);
    }

    function testFuzz_PriceTransitions(uint256 startPrice, uint256 targetPrice, uint256 maxDev, uint256 timePer)
        public
    {
        // Bound inputs
        startPrice = bound(startPrice, 1, 1e36);
        targetPrice = bound(targetPrice, 1, 1e36);
        maxDev = bound(maxDev, 1, 10000); // 0.01% to 100%
        timePer = bound(timePer, 1, 3600); // 1 second to 1 hour

        // Deploy new reporter with fuzzed params
        vm.startPrank(owner);
        reporter = new PriceOracleReporter(startPrice, updater, maxDev, timePer);
        vm.stopPrank();

        // Update to target
        vm.prank(updater);
        reporter.update(targetPrice, "fuzz");

        // Calculate periods needed for transition
        uint256 priceDiff = targetPrice > startPrice ? targetPrice - startPrice : startPrice - targetPrice;
        uint256 percentChange = (priceDiff * 10000) / startPrice;
        uint256 periodsNeeded = percentChange / maxDev + 1;

        // Fast forward enough time to complete transition
        vm.warp(block.timestamp + timePer * periodsNeeded);

        // Get final price and verify
        uint256 finalPrice = reporter.getCurrentPrice();

        // Should always reach target given enough time
        assertEq(finalPrice, targetPrice);
    }

    /*//////////////////////////////////////////////////////////////
                     CUMULATIVE TRACKING & FULL COVERAGE
    //////////////////////////////////////////////////////////////*/

    function test_SetMaxDeviation_NotInTransition() public {
        // Initially not in transition (all prices are equal)
        assertEq(reporter.transitionStartPrice(), reporter.targetPricePerShare());

        uint256 timestampBefore = block.timestamp;

        vm.prank(owner);
        reporter.setMaxDeviation(500, 120); // 5% per 2 minutes

        assertEq(reporter.lastUpdateAt(), timestampBefore); // Still the initial timestamp
        assertEq(reporter.transitionStartPrice(), INITIAL_PRICE);
        assertEq(reporter.maxDeviationPerTimePeriod(), 500);
        assertEq(reporter.deviationTimePeriod(), 120);
    }

    function test_SetMaxDeviation_InTransition() public {
        // Start a transition
        vm.prank(updater);
        reporter.update(2e18, "test"); // 100% increase, will trigger gradual transition

        // Verify we're in transition
        assertEq(reporter.transitionStartPrice(), INITIAL_PRICE);
        assertEq(reporter.targetPricePerShare(), 2e18);
        assertTrue(reporter.transitionStartPrice() != reporter.targetPricePerShare());

        // Move forward to get a different current price
        vm.warp(block.timestamp + 30);
        uint256 currentPrice = reporter.getCurrentPrice();
        assertTrue(currentPrice > INITIAL_PRICE && currentPrice < 2e18);

        uint256 timestampBefore = block.timestamp;

        vm.prank(owner);
        reporter.setMaxDeviation(500, 120);

        // Should update transition parameters since we were in transition
        assertEq(reporter.transitionStartPrice(), currentPrice);
        assertEq(reporter.lastUpdateAt(), timestampBefore);
    }

    function test_BatchingAttackPrevented() public {
        // Try to bypass gradual transition by batching multiple 10% increases
        vm.startPrank(updater);

        // First update: 10% increase (should succeed immediately)
        reporter.update(1.1e18, "batch1");
        assertEq(reporter.getCurrentPrice(), 1.1e18);

        // Second update: Another 10% increase (should trigger gradual transition)
        // This would make total 21% from original price
        reporter.update(1.21e18, "batch2");

        // Price should not immediately jump to 1.21e18
        assertEq(reporter.getCurrentPrice(), 1.1e18);
        assertEq(reporter.targetPricePerShare(), 1.21e18);

        // Third update: Try another 10% increase
        reporter.update(1.331e18, "batch3");

        // Price should still be transitioning
        assertEq(reporter.getCurrentPrice(), 1.1e18);
        assertEq(reporter.targetPricePerShare(), 1.331e18);

        vm.stopPrank();
    }

    function test_CumulativeTracking_MultipleUpdatesInPeriod() public {
        vm.startPrank(updater);

        // First update: 5%
        reporter.update(1.05e18, "test1");
        assertEq(reporter.appliedChangeInPeriod(), 500);

        // Second update: another 4% (total 9%, still under 10%)
        reporter.update(1.092e18, "test2"); // 4% from 1.05
        assertEq(reporter.appliedChangeInPeriod(), 900); // 9% total

        // Third update: try 2% more (would be 11% total, exceeds max)
        reporter.update(1.11372e18, "test3"); // ~2% from 1.092

        // Should trigger gradual transition, cumulative stays at 900
        assertEq(reporter.getCurrentPrice(), 1.092e18); // Stays at last immediate price
        assertEq(reporter.targetPricePerShare(), 1.11372e18); // New target
        assertEq(reporter.appliedChangeInPeriod(), 900); // Doesn't increase since gradual transition started

        vm.stopPrank();
    }

    function test_CumulativeTrackingResets() public {
        vm.startPrank(updater);

        // First update: 10% increase
        reporter.update(1.1e18, "update1");
        assertEq(reporter.getCurrentPrice(), 1.1e18);

        // Get cumulative info
        assertEq(reporter.appliedChangeInPeriod(), 1000); // 10% in basis points

        // Wait for period to expire
        vm.warp(block.timestamp + TIME_PERIOD + 1);

        // Now another 10% should work immediately
        reporter.update(1.21e18, "update2");
        assertEq(reporter.getCurrentPrice(), 1.21e18);

        // Check that appliedChangeInPeriod was reset and now shows the new 10% change
        assertEq(reporter.appliedChangeInPeriod(), 1000); // New 10% from 1.1 to 1.21

        vm.stopPrank();
    }

    function test_MaxDeviationUpdateResetsTracking() public {
        vm.startPrank(updater);

        // First update: 5% increase
        reporter.update(1.05e18, "update1");
        assertEq(reporter.getCurrentPrice(), 1.05e18);

        // Check cumulative
        assertEq(reporter.appliedChangeInPeriod(), 500); // 5% in basis points

        vm.stopPrank();

        // Owner updates max deviation
        vm.prank(owner);
        reporter.setMaxDeviation(200, 30); // 2% per 30 seconds

        // Check cumulative was reset
        assertEq(reporter.appliedChangeInPeriod(), 0);

        // Verify timestamps were updated
        assertEq(reporter.lastUpdateAt(), block.timestamp);
    }

    function test_BatchingAttack_SameBlock() public {
        // Test that multiple transactions in the same block cannot bypass restrictions
        uint256 blockTime = block.timestamp;

        vm.startPrank(updater);

        // First transaction: 10% increase (should succeed)
        reporter.update(1.1e18, "tx1");
        assertEq(reporter.getCurrentPrice(), 1.1e18);
        assertEq(block.timestamp, blockTime); // Still same block

        // Second transaction in same block: Another 10% increase
        // This would be 21% total from original, should trigger gradual transition
        reporter.update(1.21e18, "tx2");
        assertEq(reporter.getCurrentPrice(), 1.1e18); // Price should NOT jump
        assertEq(reporter.targetPricePerShare(), 1.21e18);
        assertEq(block.timestamp, blockTime); // Still same block

        // Third transaction in same block: Try to update again
        reporter.update(1.331e18, "tx3");
        assertEq(reporter.getCurrentPrice(), 1.1e18); // Still at 1.1
        assertEq(reporter.targetPricePerShare(), 1.331e18);
        assertEq(block.timestamp, blockTime); // Still same block

        // Even after multiple updates in same block, price doesn't bypass transition
        assertEq(reporter.getCurrentPrice(), 1.1e18);

        // Verify cumulative tracking prevents bypass
        assertEq(reporter.appliedChangeInPeriod(), 1000); // Only the first 10% counted

        vm.stopPrank();
    }

    function test_BatchingAttack_MultipleBlocks_SamePeriod() public {
        vm.startPrank(updater);

        // Block 1: 10% increase
        reporter.update(1.1e18, "block1");
        assertEq(reporter.getCurrentPrice(), 1.1e18);
        assertEq(reporter.appliedChangeInPeriod(), 1000);

        // Block 2 (1 second later, still within period)
        vm.warp(block.timestamp + 1);
        uint256 priceBefore = reporter.getCurrentPrice();
        reporter.update(1.21e18, "block2");
        // Should trigger gradual transition since cumulative would exceed max
        uint256 priceAfter = reporter.getCurrentPrice();
        assertEq(priceBefore, priceAfter); // Price doesn't jump from the update
        assertEq(reporter.targetPricePerShare(), 1.21e18);
        assertEq(reporter.appliedChangeInPeriod(), 1000); // Cumulative doesn't increase

        // Block 3 (another second later)
        vm.warp(block.timestamp + 1);
        priceBefore = reporter.getCurrentPrice();
        reporter.update(1.331e18, "block3");
        priceAfter = reporter.getCurrentPrice();
        // The update itself shouldn't cause a price jump
        assertEq(priceBefore, priceAfter);
        assertEq(reporter.targetPricePerShare(), 1.331e18);

        // Verify that even with multiple blocks, we can't bypass the max deviation per period
        // The price should be gradually transitioning, not jumping
        uint256 finalPrice = reporter.getCurrentPrice();
        // After 2 seconds, with 10% per minute, we should have at most ~0.33% additional increase
        assertLe(finalPrice, (1.1e18 * 10033) / 10000); // Max 1.1033e18

        vm.stopPrank();
    }

    function test_BatchingAttack_RapidSmallUpdates() public {
        // Test many small updates that together would exceed max deviation
        vm.startPrank(updater);

        // 10 updates of 1.5% each in same block (would be 15% total)
        uint256 currentPrice = INITIAL_PRICE;
        uint256 totalChangeAccumulated = 0;

        for (uint256 i = 0; i < 10; i++) {
            uint256 newPrice = (currentPrice * 10150) / 10000; // 1.5% increase
            reporter.update(newPrice, string(abi.encodePacked("update", i)));

            uint256 actualPrice = reporter.getCurrentPrice();

            // Check if we've hit the cumulative limit
            if (totalChangeAccumulated + 150 <= 1000) {
                // Should succeed immediately
                assertEq(actualPrice, newPrice);
                currentPrice = newPrice;
                totalChangeAccumulated += 150;
            } else {
                // Should trigger gradual transition
                assertLe(actualPrice, currentPrice); // Price shouldn't jump
                break;
            }
        }

        // Verify we couldn't bypass the 10% limit
        assertLe(reporter.getCurrentPrice(), (INITIAL_PRICE * 11000) / 10000); // Max 10% increase

        vm.stopPrank();
    }
}
