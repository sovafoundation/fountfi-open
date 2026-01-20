// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {SimpleMultiCollateralStrategy} from "../contracts/SimpleMultiCollateralStrategy.sol";
import {MultiCollateralRegistry} from "../contracts/MultiCollateralRegistry.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract SimpleMultiCollateralStrategyCoverageTest is Test {
    SimpleMultiCollateralStrategy public strategy;
    MultiCollateralRegistry public registry;
    RoleManager public roleManager;

    address public admin = address(0x1);
    address public manager = address(0x2);
    address public vault = address(0x3);
    address public nonVault = address(0x4);

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

        // Set vault
        strategy.setSToken(vault);
    }

    // Test basic getters
    function testGetters() public {
        assertEq(strategy.sToken(), vault);
        assertEq(strategy.collateralRegistry(), address(registry));
        assertEq(strategy.manager(), manager);
        assertEq(strategy.asset(), address(sovaBTC));
        assertEq(strategy.assetDecimals(), 8);
        assertEq(strategy.name(), "Simple Multi-Collateral Strategy");
        assertEq(strategy.symbol(), "SMCS");
    }

    // Test setSToken edge cases
    function testSetSTokenAlreadySet() public {
        vm.expectRevert("Already set");
        strategy.setSToken(address(0x5));
    }

    // Test depositCollateral edge cases
    function testDepositCollateralOnlyVault() public {
        wbtc.mint(address(strategy), 1e8);

        vm.prank(nonVault);
        vm.expectRevert("Only vault");
        strategy.depositCollateral(address(wbtc), 1e8);
    }

    function testDepositCollateralZeroAmount() public {
        vm.prank(vault);
        vm.expectRevert("Zero amount");
        strategy.depositCollateral(address(wbtc), 0);
    }

    function testDepositCollateralNotAllowed() public {
        MockERC20 randomToken = new MockERC20("Random", "RND", 18);
        randomToken.mint(address(strategy), 1e18);

        vm.prank(vault);
        vm.expectRevert("Not allowed");
        strategy.depositCollateral(address(randomToken), 1e18);
    }

    // Test multiple collateral deposits
    function testMultipleCollateralTypes() public {
        // Deposit WBTC
        wbtc.mint(address(strategy), 2e8);
        vm.prank(vault);
        strategy.depositCollateral(address(wbtc), 2e8);

        // Deposit tBTC
        tbtc.mint(address(strategy), 3e18);
        vm.prank(vault);
        strategy.depositCollateral(address(tbtc), 3e18);

        // Deposit SovaBTC
        sovaBTC.mint(address(strategy), 1e8);
        vm.prank(vault);
        strategy.depositCollateral(address(sovaBTC), 1e8);

        // Check balances
        assertEq(strategy.collateralBalances(address(wbtc)), 2e8);
        assertEq(strategy.collateralBalances(address(tbtc)), 3e18);
        assertEq(strategy.collateralBalances(address(sovaBTC)), 1e8);

        // Check total value (2 + 3 + 1 = 6 SovaBTC)
        assertEq(strategy.totalCollateralValue(), 6e8);

        // Check held collateral tracking
        assertEq(strategy.heldCollateralTokens(0), address(wbtc));
        assertEq(strategy.heldCollateralTokens(1), address(tbtc));
        assertEq(strategy.heldCollateralTokens(2), address(sovaBTC));
        assertTrue(strategy.isHeldCollateral(address(wbtc)));
        assertTrue(strategy.isHeldCollateral(address(tbtc)));
        assertTrue(strategy.isHeldCollateral(address(sovaBTC)));
    }

    // Test depositRedemptionFunds
    function testDepositRedemptionFundsOnlyManager() public {
        vm.expectRevert("Only manager");
        strategy.depositRedemptionFunds(1e8);
    }

    function testDepositRedemptionFundsSuccess() public {
        sovaBTC.mint(manager, 10e8);

        vm.startPrank(manager);
        sovaBTC.approve(address(strategy), 10e8);
        strategy.depositRedemptionFunds(10e8);
        vm.stopPrank();

        assertEq(sovaBTC.balanceOf(address(strategy)), 10e8);
        assertEq(strategy.totalCollateralValue(), 10e8);
    }

    // Test totalCollateralValue with mixed funds
    function testTotalCollateralValueMixed() public {
        // Deposit collateral
        wbtc.mint(address(strategy), 2e8);
        vm.prank(vault);
        strategy.depositCollateral(address(wbtc), 2e8);

        // Deposit redemption funds
        sovaBTC.mint(manager, 5e8);
        vm.startPrank(manager);
        sovaBTC.approve(address(strategy), 5e8);
        strategy.depositRedemptionFunds(5e8);
        vm.stopPrank();

        // Total should be 2 (WBTC) + 5 (redemption) = 7 SovaBTC
        assertEq(strategy.totalCollateralValue(), 7e8);
    }

    // Test totalCollateralValue with SovaBTC as collateral
    function testTotalCollateralValueSovaBTCCollateral() public {
        // Deposit SovaBTC as collateral
        sovaBTC.mint(address(strategy), 3e8);
        vm.prank(vault);
        strategy.depositCollateral(address(sovaBTC), 3e8);

        // Add redemption funds
        sovaBTC.mint(manager, 5e8);
        vm.startPrank(manager);
        sovaBTC.approve(address(strategy), 5e8);
        strategy.depositRedemptionFunds(5e8);
        vm.stopPrank();

        // Total should be 3 (collateral) + 5 (redemption) = 8 SovaBTC
        assertEq(strategy.totalCollateralValue(), 8e8);
        assertEq(sovaBTC.balanceOf(address(strategy)), 8e8);
    }

    // Test balance function
    function testBalance() public {
        wbtc.mint(address(strategy), 1e8);
        vm.prank(vault);
        strategy.depositCollateral(address(wbtc), 1e8);

        assertEq(strategy.balance(), strategy.totalCollateralValue());
        assertEq(strategy.balance(), 1e8);
    }

    // Test withdraw function
    function testWithdrawOnlyVault() public {
        vm.expectRevert("Only vault");
        strategy.withdraw(address(0x5), 1e8);
    }

    function testWithdrawFunction() public {
        // Note: withdraw doesn't actually transfer, just sets approval
        vm.prank(vault);
        strategy.withdraw(address(0x5), 1e8);

        // Check approval was set
        assertEq(sovaBTC.allowance(address(strategy), vault), type(uint256).max);
    }

    // Test setManager
    function testSetManagerOnlyManager() public {
        vm.expectRevert("Only manager");
        strategy.setManager(address(0x6));
    }

    function testSetManagerSuccess() public {
        address newManager = address(0x6);

        vm.prank(manager);
        strategy.setManager(newManager);

        assertEq(strategy.manager(), newManager);
    }

    // Test initialize (should revert)
    function testInitializeReverts() public {
        vm.expectRevert("Use constructor");
        strategy.initialize("", "", address(0), address(0), address(0), 0, "");
    }

    // Test events - removed as events are internal to the contract

    // Test edge case: empty strategy
    function testEmptyStrategyTotalValue() public {
        assertEq(strategy.totalCollateralValue(), 0);
        assertEq(strategy.balance(), 0);
    }

    // Test with updated rates
    function testTotalValueWithUpdatedRates() public {
        // Deposit WBTC
        wbtc.mint(address(strategy), 1e8);
        vm.prank(vault);
        strategy.depositCollateral(address(wbtc), 1e8);

        // Initially 1:1
        assertEq(strategy.totalCollateralValue(), 1e8);

        // Update rate to 0.95 (5% discount)
        vm.prank(admin);
        registry.updateRate(address(wbtc), 0.95e18);

        // Now worth 0.95 SovaBTC
        assertEq(strategy.totalCollateralValue(), 0.95e8);
    }

    // Fuzz test deposits
    function testFuzzDepositCollateral(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000e8); // Reasonable range

        wbtc.mint(address(strategy), amount);

        vm.prank(vault);
        strategy.depositCollateral(address(wbtc), amount);

        assertEq(strategy.collateralBalances(address(wbtc)), amount);
        assertEq(strategy.totalCollateralValue(), amount); // 1:1 rate
    }
}
