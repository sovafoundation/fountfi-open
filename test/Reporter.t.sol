// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseFountfiTest} from "./BaseFountfiTest.t.sol";
import {PriceOracleReporter} from "../src/reporter/PriceOracleReporter.sol";

contract ReporterTest is BaseFountfiTest {
    PriceOracleReporter public reporter;
    address public updater;

    function setUp() public override {
        super.setUp();

        updater = makeAddr("updater");

        vm.startPrank(owner);
        reporter = new PriceOracleReporter(1e18, updater, 1000, 60); // 1 token per share, 10% max change per minute
        vm.stopPrank();
    }

    function test_Initialization() public view {
        assertEq(reporter.getCurrentPrice(), 1e18);
        assertEq(reporter.currentRound(), 1);
        assertTrue(reporter.authorizedUpdaters(updater));
    }

    function test_PriceUpdates() public {
        // Update price per share
        uint256 newPrice = 1.5e18; // 1.5 tokens per share

        vm.prank(updater);
        reporter.update(newPrice, "Test Source");

        // Price starts transitioning from current price
        assertEq(reporter.getCurrentPrice(), 1e18);
        assertEq(reporter.targetPricePerShare(), newPrice);
        assertEq(reporter.currentRound(), 2);

        // Move forward in time to complete transition (50% increase needs 5 periods)
        vm.warp(block.timestamp + 300); // 5 minutes = 5 periods

        // Report should return the new price per share after transition
        bytes memory reportData = reporter.report();
        uint256 reportedPrice = abi.decode(reportData, (uint256));
        assertEq(reportedPrice, newPrice);
    }

    function test_UpdaterManagement() public {
        address newUpdater = makeAddr("newUpdater");

        // New updater should not be authorized
        assertFalse(reporter.authorizedUpdaters(newUpdater));

        // Unauthorized updater can't update
        vm.prank(newUpdater);
        bytes4 unauthorizedSelector = bytes4(keccak256("Unauthorized()"));
        vm.expectRevert(unauthorizedSelector);
        reporter.update(1100 * 10 ** 6, "Test Source");

        // Add new updater
        vm.prank(owner);
        reporter.setUpdater(newUpdater, true);

        assertTrue(reporter.authorizedUpdaters(newUpdater));

        // Now the new updater can update
        vm.prank(newUpdater);
        reporter.update(1.2e18, "Test Source");

        // Price starts transitioning
        assertEq(reporter.getCurrentPrice(), 1e18);
        assertEq(reporter.targetPricePerShare(), 1.2e18);

        // Move forward to complete transition (20% increase needs 2 periods)
        vm.warp(block.timestamp + 120); // 2 minutes
        assertEq(reporter.getCurrentPrice(), 1.2e18);

        // Remove original updater
        vm.prank(owner);
        reporter.setUpdater(updater, false);

        assertFalse(reporter.authorizedUpdaters(updater));

        // Original updater can no longer update
        vm.prank(updater);
        vm.expectRevert(unauthorizedSelector);
        reporter.update(1.3e18, "Test Source");
    }

    function test_SourceValidation() public {
        // Empty source should fail
        vm.prank(updater);
        vm.expectRevert(PriceOracleReporter.InvalidSource.selector);
        reporter.update(1.1e18, "");
    }
}
