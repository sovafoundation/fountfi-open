// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {MultiCollateralRegistry} from "../contracts/MultiCollateralRegistry.sol";
import {SimpleMultiCollateralStrategy} from "../contracts/SimpleMultiCollateralStrategy.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract FullMultiCollateralTest is Test {
    MultiCollateralRegistry public registry;
    SimpleMultiCollateralStrategy public strategy;
    RoleManager public roleManager;

    address public admin = address(0x1);
    address public manager = address(0x2);
    address public vault = address(0x3);
    address public user = address(0x4);

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

        // Add collaterals
        vm.startPrank(admin);
        registry.addCollateral(address(wbtc), 1e18, 8);
        registry.addCollateral(address(tbtc), 1e18, 18);
        registry.addCollateral(address(sovaBTC), 1e18, 8);
        vm.stopPrank();

        // Deploy strategy
        strategy = new SimpleMultiCollateralStrategy(address(sovaBTC), 8, address(registry), manager);
        strategy.setSToken(vault);

        // Mint tokens for testing
        wbtc.mint(user, 10e8); // 10 WBTC
        tbtc.mint(user, 10e18); // 10 tBTC
        sovaBTC.mint(user, 10e8); // 10 SovaBTC
        sovaBTC.mint(manager, 100e8); // 100 SovaBTC for redemptions
    }

    function testRegistrySetup() public {
        assertEq(registry.sovaBTC(), address(sovaBTC));
        assertTrue(registry.isAllowedCollateral(address(wbtc)));
        assertTrue(registry.isAllowedCollateral(address(tbtc)));
        assertTrue(registry.isAllowedCollateral(address(sovaBTC)));
        assertEq(registry.getCollateralTokenCount(), 3);
    }

    function testDepositWBTC() public {
        uint256 amount = 1e8; // 1 WBTC

        // Transfer to strategy
        wbtc.mint(address(strategy), amount);

        // Deposit as vault
        vm.prank(vault);
        strategy.depositCollateral(address(wbtc), amount);

        assertEq(strategy.collateralBalances(address(wbtc)), amount);
        assertEq(strategy.totalCollateralValue(), amount);
    }

    function testDepositTBTC() public {
        uint256 amount = 2e18; // 2 tBTC

        // Transfer to strategy
        tbtc.mint(address(strategy), amount);

        // Deposit as vault
        vm.prank(vault);
        strategy.depositCollateral(address(tbtc), amount);

        assertEq(strategy.collateralBalances(address(tbtc)), amount);
        assertEq(strategy.totalCollateralValue(), 2e8); // 2 SovaBTC worth
    }

    function testDepositSovaBTC() public {
        uint256 amount = 3e8; // 3 SovaBTC

        // Transfer to strategy
        sovaBTC.mint(address(strategy), amount);

        // Deposit as vault
        vm.prank(vault);
        strategy.depositCollateral(address(sovaBTC), amount);

        assertEq(strategy.collateralBalances(address(sovaBTC)), amount);
        assertEq(strategy.totalCollateralValue(), amount); // 1:1
    }

    function testMultipleCollateralDeposits() public {
        // Deposit 1 WBTC
        wbtc.mint(address(strategy), 1e8);
        vm.prank(vault);
        strategy.depositCollateral(address(wbtc), 1e8);

        // Deposit 2 tBTC
        tbtc.mint(address(strategy), 2e18);
        vm.prank(vault);
        strategy.depositCollateral(address(tbtc), 2e18);

        // Deposit 0.5 SovaBTC
        sovaBTC.mint(address(strategy), 0.5e8);
        vm.prank(vault);
        strategy.depositCollateral(address(sovaBTC), 0.5e8);

        // Total should be 3.5 SovaBTC
        assertEq(strategy.totalCollateralValue(), 3.5e8);
    }

    function testDepositRedemptionFunds() public {
        uint256 amount = 10e8; // 10 SovaBTC

        vm.startPrank(manager);
        sovaBTC.approve(address(strategy), amount);
        strategy.depositRedemptionFunds(amount);
        vm.stopPrank();

        assertEq(sovaBTC.balanceOf(address(strategy)), amount);
        assertEq(strategy.totalCollateralValue(), amount);
    }

    function testWithdraw() public {
        // Setup: deposit some SovaBTC
        sovaBTC.mint(address(strategy), 5e8);

        // Vault withdraws (note: the strategy just sets approval, doesn't transfer)
        vm.prank(vault);
        strategy.withdraw(user, 2e8);

        // The SimpleMultiCollateralStrategy doesn't actually transfer in withdraw()
        // It just sets approval for the vault to pull. So balances shouldn't change
        assertEq(sovaBTC.balanceOf(user), 10e8); // Still 10 initial
        assertEq(sovaBTC.balanceOf(address(strategy)), 5e8); // Still 5
    }

    function testConversionRates() public {
        // Test WBTC (8 decimals) -> SovaBTC (8 decimals)
        uint256 wbtcAmount = 1.5e8; // 1.5 WBTC
        assertEq(registry.convertToSovaBTC(address(wbtc), wbtcAmount), 1.5e8);

        // Test tBTC (18 decimals) -> SovaBTC (8 decimals)
        uint256 tbtcAmount = 2.5e18; // 2.5 tBTC
        assertEq(registry.convertToSovaBTC(address(tbtc), tbtcAmount), 2.5e8);

        // Test SovaBTC -> SovaBTC (always 1:1)
        uint256 sovaAmount = 1.234e8;
        assertEq(registry.convertToSovaBTC(address(sovaBTC), sovaAmount), sovaAmount);
    }

    function testUpdateCollateralRate() public {
        vm.startPrank(admin);

        // Simulate a depeg - WBTC worth 0.95 SovaBTC
        registry.updateRate(address(wbtc), 0.95e18);

        vm.stopPrank();

        // 1 WBTC now worth 0.95 SovaBTC
        assertEq(registry.convertToSovaBTC(address(wbtc), 1e8), 0.95e8);
    }

    function testRemoveCollateral() public {
        vm.startPrank(admin);

        registry.removeCollateral(address(wbtc));

        assertFalse(registry.isAllowedCollateral(address(wbtc)));
        assertEq(registry.getCollateralTokenCount(), 2);

        vm.stopPrank();
    }

    function testCannotDepositUnallowedCollateral() public {
        MockERC20 randomToken = new MockERC20("Random", "RND", 18);
        randomToken.mint(address(strategy), 1e18);

        vm.prank(vault);
        vm.expectRevert("Not allowed");
        strategy.depositCollateral(address(randomToken), 1e18);
    }

    function testOnlyVaultCanDeposit() public {
        wbtc.mint(address(strategy), 1e8);

        vm.expectRevert("Only vault");
        strategy.depositCollateral(address(wbtc), 1e8);
    }

    function testOnlyManagerCanDepositRedemptionFunds() public {
        vm.expectRevert("Only manager");
        strategy.depositRedemptionFunds(1e8);
    }

    function testFuzzConversion(uint256 amount, uint256 rate) public {
        // Bound inputs to more reasonable ranges
        amount = bound(amount, 1e4, 1e10); // From 0.0001 to 100 WBTC (8 decimals)
        rate = bound(rate, 0.1e18, 10e18); // From 0.1 to 10 rate

        // Log the bounded values for debugging
        console2.log("Bound result", amount);
        console2.log("Bound result", rate);

        vm.prank(admin);
        registry.updateRate(address(wbtc), rate);

        uint256 sovaBTCValue = registry.convertToSovaBTC(address(wbtc), amount);
        uint256 backToWBTC = registry.convertFromSovaBTC(address(wbtc), sovaBTCValue);

        // Skip test if conversion would result in 0 (rate too low)
        if (sovaBTCValue == 0) return;

        // Calculate the maximum expected error based on the conversion math
        // Error comes from: amount * rate / scalingFactor, then result * scalingFactor / rate
        // The error is proportional to the amount and inversely proportional to the rate

        // For low rates (< 1), the error can be amplified
        uint256 maxError;
        if (rate < 1e18) {
            // For rates less than 1, the error can be up to (1e18 / rate)
            // But we cap it at a reasonable value
            maxError = (1e18 * 2) / rate;
            if (maxError > 100) maxError = 100; // Cap at 100 units
        } else {
            maxError = 2; // For rates >= 1, error is minimal
        }

        if (backToWBTC > amount) {
            assertLe(backToWBTC - amount, maxError, "Conversion back exceeded tolerance");
        } else {
            assertLe(amount - backToWBTC, maxError, "Conversion back was less than expected");
        }
    }

    function testEdgeCaseZeroDeposit() public {
        vm.prank(vault);
        vm.expectRevert("Zero amount");
        strategy.depositCollateral(address(wbtc), 0);
    }

    function testLargeDeposits() public {
        uint256 largeAmount = 1000000e8; // 1 million BTC worth

        wbtc.mint(address(strategy), largeAmount);

        vm.prank(vault);
        strategy.depositCollateral(address(wbtc), largeAmount);

        assertEq(strategy.totalCollateralValue(), largeAmount);
    }
}
