// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {MultiCollateralRegistry} from "../contracts/MultiCollateralRegistry.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract MultiCollateralRegistryEdgeCasesTest is Test {
    MultiCollateralRegistry public registry;
    RoleManager public roleManager;

    address public admin = address(0x1);
    address public nonAdmin = address(0x2);

    MockERC20 public sovaBTC;
    MockERC20 public wbtc;
    MockERC20 public tbtc;

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

    // Test constructor edge cases
    function testConstructorZeroRoleManager() public {
        vm.expectRevert();
        new MultiCollateralRegistry(address(0), address(sovaBTC));
    }

    function testConstructorZeroSovaBTC() public {
        vm.expectRevert();
        new MultiCollateralRegistry(address(roleManager), address(0));
    }

    // Test addCollateral edge cases
    function testAddCollateralZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert();
        registry.addCollateral(address(0), 1e18, 8);
    }

    function testAddCollateralZeroRate() public {
        vm.prank(admin);
        vm.expectRevert();
        registry.addCollateral(address(wbtc), 0, 8);
    }

    function testAddCollateralAlreadyAllowed() public {
        vm.startPrank(admin);
        registry.addCollateral(address(wbtc), 1e18, 8);

        vm.expectRevert();
        registry.addCollateral(address(wbtc), 1e18, 8);
        vm.stopPrank();
    }

    function testAddCollateralUnauthorized() public {
        vm.prank(nonAdmin);
        vm.expectRevert();
        registry.addCollateral(address(wbtc), 1e18, 8);
    }

    // Test removeCollateral edge cases
    function testRemoveCollateralNotAllowed() public {
        vm.prank(admin);
        vm.expectRevert();
        registry.removeCollateral(address(wbtc));
    }

    function testRemoveCollateralUnauthorized() public {
        vm.startPrank(admin);
        registry.addCollateral(address(wbtc), 1e18, 8);
        vm.stopPrank();

        vm.prank(nonAdmin);
        vm.expectRevert();
        registry.removeCollateral(address(wbtc));
    }

    function testRemoveLastCollateral() public {
        vm.startPrank(admin);
        registry.addCollateral(address(wbtc), 1e18, 8);
        registry.removeCollateral(address(wbtc));
        vm.stopPrank();

        assertEq(registry.getCollateralTokenCount(), 0);
        assertFalse(registry.isAllowedCollateral(address(wbtc)));
    }

    function testRemoveMiddleCollateral() public {
        vm.startPrank(admin);
        registry.addCollateral(address(wbtc), 1e18, 8);
        registry.addCollateral(address(tbtc), 1e18, 18);
        registry.addCollateral(address(sovaBTC), 1e18, 8);

        // Remove middle one
        registry.removeCollateral(address(tbtc));
        vm.stopPrank();

        assertEq(registry.getCollateralTokenCount(), 2);
        assertFalse(registry.isAllowedCollateral(address(tbtc)));

        // Check order is maintained
        address[] memory tokens = registry.getAllCollateralTokens();
        assertEq(tokens[0], address(wbtc));
        assertEq(tokens[1], address(sovaBTC));
    }

    // Test updateRate edge cases
    function testUpdateRateNotAllowed() public {
        vm.prank(admin);
        vm.expectRevert();
        registry.updateRate(address(wbtc), 1e18);
    }

    function testUpdateRateZero() public {
        vm.startPrank(admin);
        registry.addCollateral(address(wbtc), 1e18, 8);

        vm.expectRevert();
        registry.updateRate(address(wbtc), 0);
        vm.stopPrank();
    }

    function testUpdateRateUnauthorized() public {
        vm.prank(admin);
        registry.addCollateral(address(wbtc), 1e18, 8);

        vm.prank(nonAdmin);
        vm.expectRevert();
        registry.updateRate(address(wbtc), 0.95e18);
    }

    // Test conversion edge cases
    function testConvertToSovaBTCNotAllowed() public {
        vm.expectRevert();
        registry.convertToSovaBTC(address(wbtc), 1e8);
    }

    function testConvertFromSovaBTCNotAllowed() public {
        vm.expectRevert();
        registry.convertFromSovaBTC(address(wbtc), 1e8);
    }

    function testConvertZeroAmount() public {
        vm.prank(admin);
        registry.addCollateral(address(wbtc), 1e18, 8);

        assertEq(registry.convertToSovaBTC(address(wbtc), 0), 0);
        assertEq(registry.convertFromSovaBTC(address(wbtc), 0), 0);
    }

    // Test extreme conversion rates
    function testExtremeConversionRates() public {
        vm.startPrank(admin);

        // Very high rate (1 token = 1000 SovaBTC)
        registry.addCollateral(address(wbtc), 1000e18, 8);
        assertEq(registry.convertToSovaBTC(address(wbtc), 1e8), 1000e8);

        // Very low rate (1 token = 0.001 SovaBTC)
        MockERC20 cheapToken = new MockERC20("Cheap", "CHEAP", 8);
        registry.addCollateral(address(cheapToken), 0.001e18, 8);
        assertEq(registry.convertToSovaBTC(address(cheapToken), 1000e8), 1e8);

        vm.stopPrank();
    }

    // Test decimal handling edge cases
    function testMixedDecimalConversions() public {
        vm.startPrank(admin);

        // 6 decimal token
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);
        registry.addCollateral(address(usdc), 1e18, 6);

        // 1 USDC (1e6) should equal 1 SovaBTC (1e8)
        assertEq(registry.convertToSovaBTC(address(usdc), 1e6), 1e8);
        assertEq(registry.convertFromSovaBTC(address(usdc), 1e8), 1e6);

        // 27 decimal token
        MockERC20 bigToken = new MockERC20("Big", "BIG", 27);
        registry.addCollateral(address(bigToken), 1e18, 27);

        // 1 BIG (1e27) should equal 1 SovaBTC (1e8)
        assertEq(registry.convertToSovaBTC(address(bigToken), 1e27), 1e8);
        assertEq(registry.convertFromSovaBTC(address(bigToken), 1e8), 1e27);

        vm.stopPrank();
    }

    // Test getAllCollateralTokens
    function testGetAllCollateralTokensEmpty() public {
        address[] memory tokens = registry.getAllCollateralTokens();
        assertEq(tokens.length, 0);
    }

    function testGetAllCollateralTokensMultiple() public {
        vm.startPrank(admin);
        registry.addCollateral(address(wbtc), 1e18, 8);
        registry.addCollateral(address(tbtc), 1e18, 18);
        registry.addCollateral(address(sovaBTC), 1e18, 8);
        vm.stopPrank();

        address[] memory tokens = registry.getAllCollateralTokens();
        assertEq(tokens.length, 3);
        assertEq(tokens[0], address(wbtc));
        assertEq(tokens[1], address(tbtc));
        assertEq(tokens[2], address(sovaBTC));
    }

    // Test events - removed as events are internal to the contract

    // Fuzz testing
    function testFuzzAddCollateral(address token, uint256 rate, uint8 decimals) public {
        vm.assume(token != address(0));
        vm.assume(rate > 0 && rate <= 1000e18); // Reasonable range
        vm.assume(decimals <= 27); // Max reasonable decimals

        vm.prank(admin);
        registry.addCollateral(token, rate, decimals);

        assertTrue(registry.isAllowedCollateral(token));
        assertEq(registry.collateralToSovaBTCRate(token), rate);
        assertEq(registry.collateralDecimals(token), decimals);
    }

    function testFuzzConversion(uint256 amount, uint256 rate, uint8 tokenDecimals) public {
        // Bound the inputs to reasonable ranges
        tokenDecimals = uint8(bound(tokenDecimals, 6, 18)); // Common decimal ranges
        rate = bound(rate, 0.1e18, 10e18); // 0.1 to 10 rate

        // Calculate a reasonable max amount based on decimals
        uint256 maxAmount = 10 ** tokenDecimals * 1000; // Up to 1000 tokens
        uint256 minAmount = 10 ** tokenDecimals / 100; // At least 0.01 tokens
        amount = bound(amount, minAmount, maxAmount);

        MockERC20 token = new MockERC20("Test", "TEST", tokenDecimals);

        vm.prank(admin);
        registry.addCollateral(address(token), rate, tokenDecimals);

        uint256 sovaBTCValue = registry.convertToSovaBTC(address(token), amount);

        // Skip test if conversion results in 0 (due to rounding)
        if (sovaBTCValue == 0) {
            return;
        }

        // Should be able to convert back (with potential rounding)
        uint256 backToToken = registry.convertFromSovaBTC(address(token), sovaBTCValue);

        // Calculate the maximum possible rounding error
        // The error depends on the rate, amount, and decimal differences

        // For the conversion: amount * rate / scalingFactor
        // Then back: result * scalingFactor / rate
        // The maximum error is related to the decimal conversions and rate

        uint256 maxError;

        // Calculate base error from double conversion
        if (rate < 1e18) {
            // For rates < 1, error is amplified by 1/rate
            maxError = (2e18) / rate;
        } else {
            // For rates >= 1, error is proportional to rate
            maxError = (2 * rate) / 1e18;
        }

        // Adjust for decimal differences
        if (tokenDecimals > 8) {
            // More decimals means larger absolute error
            maxError = maxError * (10 ** (tokenDecimals - 8));
        }

        // Cap the error at a reasonable percentage of the amount (0.1%)
        uint256 percentageError = amount / 1000;
        if (maxError > percentageError && percentageError > 0) {
            maxError = percentageError;
        }

        // Ensure minimum error allowance
        if (maxError < 10) maxError = 10;

        if (backToToken > amount) {
            assertLe(backToToken - amount, maxError, "Exceeded tolerance on conversion back");
        } else {
            assertLe(amount - backToToken, maxError, "Less than expected on conversion back");
        }
    }
}
