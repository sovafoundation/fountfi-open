// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {MultiCollateralRegistry} from "../contracts/MultiCollateralRegistry.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract MultiCollateralRegistryFullCoverageTest is Test {
    MultiCollateralRegistry public registry;
    RoleManager public roleManager;

    address public admin = address(0x1);
    address public nonAdmin = address(0x2);

    MockERC20 public sovaBTC;
    MockERC20 public wbtc;
    MockERC20 public tbtc;

    // Events to test
    event CollateralAdded(address indexed token, uint256 rate, uint8 decimals);
    event CollateralRemoved(address indexed token);
    event RateUpdated(address indexed token, uint256 oldRate, uint256 newRate);

    function setUp() public {
        // Deploy role manager
        roleManager = new RoleManager();
        roleManager.grantRole(admin, roleManager.PROTOCOL_ADMIN());

        // Deploy tokens
        sovaBTC = new MockERC20("SovaBTC", "SBTC", 8);
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        tbtc = new MockERC20("tBTC", "TBTC", 18);

        // Deploy registry
        registry = new MultiCollateralRegistry(address(roleManager), address(sovaBTC));
    }

    // Test constructor edge cases that might not be covered
    function testConstructorWithValidParams() public {
        MultiCollateralRegistry newRegistry = new MultiCollateralRegistry(address(roleManager), address(sovaBTC));
        assertEq(newRegistry.sovaBTC(), address(sovaBTC));
        assertEq(address(newRegistry.roleManager()), address(roleManager));
    }

    // Test removing the last collateral token (edge case)
    function testRemoveOnlyCollateral() public {
        // Add only one collateral
        vm.prank(admin);
        registry.addCollateral(address(wbtc), 1e18, 8);

        assertEq(registry.getCollateralTokenCount(), 1);

        // Remove it
        vm.prank(admin);
        registry.removeCollateral(address(wbtc));

        assertEq(registry.getCollateralTokenCount(), 0);
        assertFalse(registry.isAllowedCollateral(address(wbtc)));
    }

    // Test removing first collateral when multiple exist
    function testRemoveFirstCollateral() public {
        vm.startPrank(admin);
        registry.addCollateral(address(wbtc), 1e18, 8);
        registry.addCollateral(address(tbtc), 1e18, 18);
        registry.addCollateral(address(sovaBTC), 1e18, 8);

        // Remove first one
        registry.removeCollateral(address(wbtc));
        vm.stopPrank();

        assertEq(registry.getCollateralTokenCount(), 2);
        assertFalse(registry.isAllowedCollateral(address(wbtc)));

        // Check order - sovaBTC should now be first (it replaced wbtc's spot)
        address[] memory tokens = registry.getAllCollateralTokens();
        assertEq(tokens[0], address(sovaBTC));
        assertEq(tokens[1], address(tbtc));
    }

    // Test event emissions
    function testEventEmissions() public {
        vm.startPrank(admin);

        // Test CollateralAdded event
        vm.expectEmit(true, false, false, true);
        emit CollateralAdded(address(wbtc), 1e18, 8);
        registry.addCollateral(address(wbtc), 1e18, 8);

        // Test RateUpdated event
        vm.expectEmit(true, false, false, true);
        emit RateUpdated(address(wbtc), 1e18, 0.95e18);
        registry.updateRate(address(wbtc), 0.95e18);

        // Test CollateralRemoved event
        vm.expectEmit(true, false, false, false);
        emit CollateralRemoved(address(wbtc));
        registry.removeCollateral(address(wbtc));

        vm.stopPrank();
    }

    // Test all getters with empty registry
    function testGettersWithEmptyRegistry() public view {
        assertEq(registry.getCollateralTokenCount(), 0);

        address[] memory tokens = registry.getAllCollateralTokens();
        assertEq(tokens.length, 0);

        assertFalse(registry.isAllowedCollateral(address(wbtc)));
        assertEq(registry.collateralToSovaBTCRate(address(wbtc)), 0);
        assertEq(registry.collateralDecimals(address(wbtc)), 0);
    }

    // Test conversion with SovaBTC (1:1 conversion path)
    function testSovaBTCToSovaBTCConversion() public {
        vm.prank(admin);
        registry.addCollateral(address(sovaBTC), 1e18, 8);

        // Test both directions - should be 1:1
        uint256 amount = 12345678;
        assertEq(registry.convertToSovaBTC(address(sovaBTC), amount), amount);
        assertEq(registry.convertFromSovaBTC(address(sovaBTC), amount), amount);
    }

    // Test the exact rounding behavior
    function testConversionRounding() public {
        vm.prank(admin);
        // Add a token with 18 decimals and a non-1:1 rate
        registry.addCollateral(address(tbtc), 0.99e18, 18); // 0.99 rate

        // Test small amounts that might round
        uint256 smallAmount = 1;
        uint256 sovaBTCValue = registry.convertToSovaBTC(address(tbtc), smallAmount);
        assertEq(sovaBTCValue, 0); // Should round down to 0

        // Test amount that should produce non-zero result
        uint256 largerAmount = 1e18; // 1 tBTC
        sovaBTCValue = registry.convertToSovaBTC(address(tbtc), largerAmount);
        assertEq(sovaBTCValue, 0.99e8); // Should be 0.99 SovaBTC
    }

    // Test all error conditions are hit
    function testAllErrorConditions() public {
        // Test InvalidCollateral in constructor
        vm.expectRevert(MultiCollateralRegistry.InvalidCollateral.selector);
        new MultiCollateralRegistry(address(roleManager), address(0));

        // Test InvalidCollateral for zero address in addCollateral
        vm.prank(admin);
        vm.expectRevert(MultiCollateralRegistry.InvalidCollateral.selector);
        registry.addCollateral(address(0), 1e18, 8);

        // Test InvalidRate for zero rate
        vm.prank(admin);
        vm.expectRevert(MultiCollateralRegistry.InvalidRate.selector);
        registry.addCollateral(address(wbtc), 0, 8);

        // Test InvalidCollateral for already added
        vm.startPrank(admin);
        registry.addCollateral(address(wbtc), 1e18, 8);
        vm.expectRevert(MultiCollateralRegistry.InvalidCollateral.selector);
        registry.addCollateral(address(wbtc), 1e18, 8);
        vm.stopPrank();

        // Test CollateralNotAllowed in removeCollateral
        vm.prank(admin);
        vm.expectRevert(MultiCollateralRegistry.CollateralNotAllowed.selector);
        registry.removeCollateral(address(tbtc));

        // Test CollateralNotAllowed in updateRate
        vm.prank(admin);
        vm.expectRevert(MultiCollateralRegistry.CollateralNotAllowed.selector);
        registry.updateRate(address(tbtc), 1e18);

        // Test InvalidRate in updateRate
        vm.startPrank(admin);
        registry.addCollateral(address(tbtc), 1e18, 18);
        vm.expectRevert(MultiCollateralRegistry.InvalidRate.selector);
        registry.updateRate(address(tbtc), 0);
        vm.stopPrank();

        // Test CollateralNotAllowed in convertToSovaBTC
        vm.expectRevert(MultiCollateralRegistry.CollateralNotAllowed.selector);
        registry.convertToSovaBTC(address(0x123), 1e8);

        // Test CollateralNotAllowed in convertFromSovaBTC
        vm.expectRevert(MultiCollateralRegistry.CollateralNotAllowed.selector);
        registry.convertFromSovaBTC(address(0x123), 1e8);
    }
}
