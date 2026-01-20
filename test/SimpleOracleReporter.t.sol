// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {SimpleOracleReporter} from "../src/reporter/SimpleOracleReporter.sol";
import {Ownable} from "solady/auth/Ownable.sol";

contract SimpleOracleReporterTest is Test {
    SimpleOracleReporter public reporter;

    address public owner = makeAddr("owner");
    address public updater = makeAddr("updater");
    address public updater2 = makeAddr("updater2");
    address public unauthorized = makeAddr("unauthorized");

    uint256 constant INITIAL_PRICE = 1e18;

    event PricePerShareUpdated(uint256 roundNumber, uint256 pricePerShare, string source);
    event SetUpdater(address indexed updater, bool isAuthorized);

    function setUp() public {
        vm.startPrank(owner);
        reporter = new SimpleOracleReporter(INITIAL_PRICE, updater);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR & INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public view {
        assertEq(reporter.pricePerShare(), INITIAL_PRICE);
        assertEq(reporter.currentRound(), 1);
        assertEq(reporter.lastUpdateAt(), block.timestamp);
        assertTrue(reporter.authorizedUpdaters(updater));
        assertEq(reporter.owner(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                            PRICE UPDATES
    //////////////////////////////////////////////////////////////*/

    function test_Update_Basic() public {
        uint256 newPrice = 1.5e18;
        string memory source = "test";

        vm.expectEmit(true, true, true, true);
        emit PricePerShareUpdated(2, newPrice, source);

        vm.prank(updater);
        reporter.update(newPrice, source);

        assertEq(reporter.currentRound(), 2);
        assertEq(reporter.pricePerShare(), newPrice);
        assertEq(reporter.lastUpdateAt(), block.timestamp);
    }

    function test_Update_MultipleUpdates() public {
        // First update
        vm.prank(updater);
        reporter.update(1.2e18, "update1");
        assertEq(reporter.currentRound(), 2);
        assertEq(reporter.pricePerShare(), 1.2e18);

        // Second update
        vm.warp(block.timestamp + 100);
        vm.prank(updater);
        reporter.update(1.5e18, "update2");
        assertEq(reporter.currentRound(), 3);
        assertEq(reporter.pricePerShare(), 1.5e18);
        assertEq(reporter.lastUpdateAt(), block.timestamp);

        // Third update
        vm.warp(block.timestamp + 200);
        vm.prank(updater);
        reporter.update(1.1e18, "update3");
        assertEq(reporter.currentRound(), 4);
        assertEq(reporter.pricePerShare(), 1.1e18);
    }

    function test_Update_RevertUnauthorized() public {
        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(unauthorized);
        reporter.update(2e18, "test");
    }

    function test_Update_RevertInvalidSource() public {
        vm.expectRevert(SimpleOracleReporter.InvalidSource.selector);
        vm.prank(updater);
        reporter.update(2e18, "");
    }

    function test_Update_ZeroPrice() public {
        // Test that zero price is allowed
        vm.prank(updater);
        reporter.update(0, "zero");
        assertEq(reporter.pricePerShare(), 0);
    }

    function test_Update_LargePrice() public {
        uint256 largePrice = 1e36;
        vm.prank(updater);
        reporter.update(largePrice, "large");
        assertEq(reporter.pricePerShare(), largePrice);
    }

    /*//////////////////////////////////////////////////////////////
                            REPORTING
    //////////////////////////////////////////////////////////////*/

    function test_Report() public {
        bytes memory reportData = reporter.report();
        uint256 decodedPrice = abi.decode(reportData, (uint256));
        assertEq(decodedPrice, INITIAL_PRICE);

        // Update and check report reflects new price
        vm.prank(updater);
        reporter.update(2e18, "test");

        reportData = reporter.report();
        decodedPrice = abi.decode(reportData, (uint256));
        assertEq(decodedPrice, 2e18);
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

    function test_SetUpdater_MultipleUpdaters() public {
        // Authorize multiple updaters
        vm.startPrank(owner);
        reporter.setUpdater(updater2, true);
        reporter.setUpdater(unauthorized, true);
        vm.stopPrank();

        // All should be able to update
        vm.prank(updater);
        reporter.update(1.1e18, "updater1");

        vm.prank(updater2);
        reporter.update(1.2e18, "updater2");

        vm.prank(unauthorized);
        reporter.update(1.3e18, "updater3");

        assertEq(reporter.pricePerShare(), 1.3e18);
        assertEq(reporter.currentRound(), 4);
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RapidUpdates() public {
        // Multiple updates in quick succession
        vm.startPrank(updater);

        reporter.update(1.1e18, "1");
        reporter.update(1.2e18, "2");
        reporter.update(1.3e18, "3");
        reporter.update(1.4e18, "4");
        reporter.update(1.5e18, "5");

        vm.stopPrank();

        assertEq(reporter.currentRound(), 6);
        assertEq(reporter.pricePerShare(), 1.5e18);
    }

    function test_UpdaterManagement_Complex() public {
        // Start with one updater
        assertTrue(reporter.authorizedUpdaters(updater));

        // Add another updater
        vm.prank(owner);
        reporter.setUpdater(updater2, true);

        // Both can update
        vm.prank(updater);
        reporter.update(1.1e18, "test1");

        vm.prank(updater2);
        reporter.update(1.2e18, "test2");

        // Revoke first updater
        vm.prank(owner);
        reporter.setUpdater(updater, false);

        // First updater cannot update
        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(updater);
        reporter.update(1.3e18, "test3");

        // Second updater still can
        vm.prank(updater2);
        reporter.update(1.3e18, "test3");

        assertEq(reporter.pricePerShare(), 1.3e18);
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Update(uint256 price, string memory source) public {
        vm.assume(bytes(source).length > 0);

        vm.prank(updater);
        reporter.update(price, source);

        assertEq(reporter.pricePerShare(), price);
        assertEq(reporter.currentRound(), 2);
        assertEq(reporter.lastUpdateAt(), block.timestamp);
    }

    function testFuzz_MultipleUpdates(uint256[10] memory prices) public {
        for (uint256 i = 0; i < prices.length; i++) {
            vm.prank(updater);
            reporter.update(prices[i], "fuzz");

            assertEq(reporter.pricePerShare(), prices[i]);
            assertEq(reporter.currentRound(), i + 2);
        }
    }

    function testFuzz_Report(uint256 price) public {
        vm.prank(updater);
        reporter.update(price, "fuzz");

        bytes memory reportData = reporter.report();
        uint256 decodedPrice = abi.decode(reportData, (uint256));

        assertEq(decodedPrice, price);
    }
}
