// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {MultiCollateralRegistry} from "../contracts/MultiCollateralRegistry.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";

contract BasicMultiCollateralTest is Test {
    MultiCollateralRegistry public registry;
    RoleManager public roleManager;

    address public admin = address(0x1);
    address public sovaBTC = address(0x1111);
    address public wbtc = address(0x2222);
    address public tbtc = address(0x3333);

    function setUp() public {
        // Deploy role manager
        roleManager = new RoleManager();
        roleManager.grantRole(admin, roleManager.PROTOCOL_ADMIN());

        // Deploy registry
        registry = new MultiCollateralRegistry(address(roleManager), sovaBTC);
    }

    function testBasicSetup() public {
        assertEq(registry.sovaBTC(), sovaBTC);
    }

    function testAddCollateral() public {
        vm.startPrank(admin);

        // Add WBTC as collateral
        registry.addCollateral(wbtc, 1e18, 8);

        assertTrue(registry.allowedCollateral(wbtc));
        assertEq(registry.collateralToSovaBTCRate(wbtc), 1e18);
        assertEq(registry.collateralDecimals(wbtc), 8);

        vm.stopPrank();
    }

    function testConversion() public {
        vm.startPrank(admin);
        registry.addCollateral(wbtc, 1e18, 8);
        vm.stopPrank();

        // 1 WBTC = 1 SovaBTC
        uint256 wbtcAmount = 1e8;
        uint256 sovaBTCValue = registry.convertToSovaBTC(wbtc, wbtcAmount);
        assertEq(sovaBTCValue, 1e8);
    }

    function testSovaBTCConversion() public {
        vm.startPrank(admin);
        registry.addCollateral(sovaBTC, 1e18, 8);
        vm.stopPrank();

        // SovaBTC to SovaBTC is always 1:1
        uint256 amount = 1e8;
        uint256 value = registry.convertToSovaBTC(sovaBTC, amount);
        assertEq(value, amount);
    }
}
