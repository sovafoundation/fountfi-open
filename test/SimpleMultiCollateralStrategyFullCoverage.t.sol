// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {SimpleMultiCollateralStrategy} from "../contracts/SimpleMultiCollateralStrategy.sol";
import {MultiCollateralRegistry} from "../contracts/MultiCollateralRegistry.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract SimpleMultiCollateralStrategyFullCoverageTest is Test {
    SimpleMultiCollateralStrategy public strategy;
    MultiCollateralRegistry public registry;
    RoleManager public roleManager;

    address public admin = address(0x1);
    address public manager = address(0x2);
    address public vault = address(0x3);
    address public nonVault = address(0x4);
    address public nonManager = address(0x5);

    MockERC20 public sovaBTC;
    MockERC20 public wbtc;
    MockERC20 public tbtc;
    MockERC20 public cbBTC;

    event CollateralDeposited(address indexed token, uint256 amount);

    function setUp() public {
        // Deploy role manager
        roleManager = new RoleManager();
        roleManager.grantRole(admin, roleManager.PROTOCOL_ADMIN());

        // Deploy tokens
        sovaBTC = new MockERC20("SovaBTC", "SBTC", 8);
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        tbtc = new MockERC20("tBTC", "TBTC", 18);
        cbBTC = new MockERC20("cbBTC", "cbBTC", 8);

        // Deploy registry
        registry = new MultiCollateralRegistry(address(roleManager), address(sovaBTC));

        // Add collaterals
        vm.startPrank(admin);
        registry.addCollateral(address(wbtc), 1e18, 8);
        registry.addCollateral(address(tbtc), 1e18, 18);
        registry.addCollateral(address(cbBTC), 1e18, 8);
        registry.addCollateral(address(sovaBTC), 1e18, 8);
        vm.stopPrank();

        // Deploy strategy
        strategy = new SimpleMultiCollateralStrategy(address(sovaBTC), 8, address(registry), manager);

        // Set vault
        strategy.setSToken(vault);
    }

    // Test constructor parameters
    function testConstructor() public {
        SimpleMultiCollateralStrategy newStrategy =
            new SimpleMultiCollateralStrategy(address(sovaBTC), 8, address(registry), manager);

        assertEq(newStrategy.asset(), address(sovaBTC));
        assertEq(newStrategy.assetDecimals(), 8);
        assertEq(newStrategy.collateralRegistry(), address(registry));
        assertEq(newStrategy.manager(), manager);
        assertEq(newStrategy.sToken(), address(0)); // Not set yet
    }

    // Test the initialize function that should always revert
    function testInitializeAlwaysReverts() public {
        vm.expectRevert("Use constructor");
        strategy.initialize("", "", address(0), address(0), address(0), 0, "");

        // Try with different parameters
        vm.expectRevert("Use constructor");
        strategy.initialize("Test", "TST", address(sovaBTC), address(vault), address(registry), 8, "test");
    }

    // Test totalCollateralValue with no collateral
    function testTotalCollateralValueEmpty() public view {
        assertEq(strategy.totalCollateralValue(), 0);
    }

    // Test totalCollateralValue with only redemption funds (no collateral)
    function testTotalCollateralValueOnlyRedemptionFunds() public {
        // Deposit redemption funds
        sovaBTC.mint(manager, 10e8);
        vm.startPrank(manager);
        sovaBTC.approve(address(strategy), 10e8);
        strategy.depositRedemptionFunds(10e8);
        vm.stopPrank();

        assertEq(strategy.totalCollateralValue(), 10e8);
    }

    // Test depositing multiple collateral types to ensure all paths are covered
    function testDepositAllCollateralTypes() public {
        // Mint tokens to strategy
        wbtc.mint(address(strategy), 1e8);
        tbtc.mint(address(strategy), 1e18);
        cbBTC.mint(address(strategy), 1e8);
        sovaBTC.mint(address(strategy), 1e8);

        vm.startPrank(vault);

        // Deposit each type
        strategy.depositCollateral(address(wbtc), 1e8);
        strategy.depositCollateral(address(tbtc), 1e18);
        strategy.depositCollateral(address(cbBTC), 1e8);
        strategy.depositCollateral(address(sovaBTC), 1e8);

        vm.stopPrank();

        // Check balances
        assertEq(strategy.collateralBalances(address(wbtc)), 1e8);
        assertEq(strategy.collateralBalances(address(tbtc)), 1e18);
        assertEq(strategy.collateralBalances(address(cbBTC)), 1e8);
        assertEq(strategy.collateralBalances(address(sovaBTC)), 1e8);

        // Check held collateral tracking
        assertEq(strategy.heldCollateralTokens(0), address(wbtc));
        assertEq(strategy.heldCollateralTokens(1), address(tbtc));
        assertEq(strategy.heldCollateralTokens(2), address(cbBTC));
        assertEq(strategy.heldCollateralTokens(3), address(sovaBTC));

        assertTrue(strategy.isHeldCollateral(address(wbtc)));
        assertTrue(strategy.isHeldCollateral(address(tbtc)));
        assertTrue(strategy.isHeldCollateral(address(cbBTC)));
        assertTrue(strategy.isHeldCollateral(address(sovaBTC)));

        // Total value should be 4 BTC worth
        assertEq(strategy.totalCollateralValue(), 4e8);
    }

    // Test depositing the same collateral multiple times
    function testDepositSameCollateralMultipleTimes() public {
        wbtc.mint(address(strategy), 3e8);

        vm.startPrank(vault);

        // First deposit
        strategy.depositCollateral(address(wbtc), 1e8);
        assertEq(strategy.collateralBalances(address(wbtc)), 1e8);

        // Second deposit
        strategy.depositCollateral(address(wbtc), 1e8);
        assertEq(strategy.collateralBalances(address(wbtc)), 2e8);

        // Third deposit
        strategy.depositCollateral(address(wbtc), 1e8);
        assertEq(strategy.collateralBalances(address(wbtc)), 3e8);

        vm.stopPrank();

        // Should only be tracked once in heldCollateralTokens
        assertEq(strategy.heldCollateralTokens(0), address(wbtc));
        vm.expectRevert(); // Should revert on accessing index 1
        strategy.heldCollateralTokens(1);
    }

    // Test totalCollateralValue with mixed collateral and redemption funds
    function testTotalCollateralValueMixedWithSovaBTCCollateral() public {
        // Deposit WBTC as collateral
        wbtc.mint(address(strategy), 1e8);
        vm.prank(vault);
        strategy.depositCollateral(address(wbtc), 1e8);

        // Deposit SovaBTC as collateral
        sovaBTC.mint(address(strategy), 2e8);
        vm.prank(vault);
        strategy.depositCollateral(address(sovaBTC), 2e8);

        // Add redemption funds
        sovaBTC.mint(manager, 3e8);
        vm.startPrank(manager);
        sovaBTC.approve(address(strategy), 3e8);
        strategy.depositRedemptionFunds(3e8);
        vm.stopPrank();

        // Total should be:
        // 1e8 (WBTC) + 2e8 (SovaBTC collateral) + 3e8 (redemption) = 6e8
        assertEq(strategy.totalCollateralValue(), 6e8);

        // Check SovaBTC balance
        assertEq(sovaBTC.balanceOf(address(strategy)), 5e8); // 2e8 collateral + 3e8 redemption
    }

    // Test edge case: totalCollateralValue when SovaBTC balance < collateral balance
    function testTotalCollateralValueSovaBTCDeficit() public {
        // This shouldn't happen in practice, but test the branch
        sovaBTC.mint(address(strategy), 5e8);

        // Deposit 10e8 as collateral (more than actual balance)
        vm.prank(vault);
        strategy.depositCollateral(address(sovaBTC), 10e8);

        // In this case, totalCollateralValue should still report the tracked amount
        // Since the actual balance (5e8) < tracked collateral (10e8),
        // no additional redemption funds are counted
        assertEq(strategy.totalCollateralValue(), 10e8);
    }

    // Test access control
    function testDepositCollateralOnlyVault() public {
        wbtc.mint(address(strategy), 1e8);

        vm.prank(nonVault);
        vm.expectRevert("Only vault");
        strategy.depositCollateral(address(wbtc), 1e8);

        vm.prank(manager);
        vm.expectRevert("Only vault");
        strategy.depositCollateral(address(wbtc), 1e8);
    }

    function testDepositRedemptionFundsOnlyManager() public {
        sovaBTC.mint(nonManager, 1e8);

        vm.startPrank(nonManager);
        sovaBTC.approve(address(strategy), 1e8);
        vm.expectRevert("Only manager");
        strategy.depositRedemptionFunds(1e8);
        vm.stopPrank();

        vm.expectRevert("Only manager");
        strategy.depositRedemptionFunds(1e8);
    }

    function testSetManagerOnlyManager() public {
        vm.prank(nonManager);
        vm.expectRevert("Only manager");
        strategy.setManager(nonManager);

        vm.prank(vault);
        vm.expectRevert("Only manager");
        strategy.setManager(vault);
    }

    function testWithdrawOnlyVault() public {
        vm.prank(nonVault);
        vm.expectRevert("Only vault");
        strategy.withdraw(address(0x123), 1e8);

        vm.prank(manager);
        vm.expectRevert("Only vault");
        strategy.withdraw(address(0x123), 1e8);
    }

    // Test event emissions
    function testEventEmissions() public {
        wbtc.mint(address(strategy), 1e8);

        vm.prank(vault);
        vm.expectEmit(true, false, false, true);
        emit CollateralDeposited(address(wbtc), 1e8);
        strategy.depositCollateral(address(wbtc), 1e8);
    }

    // Test withdraw function (even though it doesn't do much)
    function testWithdrawFunction() public {
        // The withdraw function only checks access, doesn't transfer
        vm.prank(vault);
        strategy.withdraw(address(0x123), 1e8); // Should not revert

        // Can call with any parameters
        vm.prank(vault);
        strategy.withdraw(address(0), 0);

        vm.prank(vault);
        strategy.withdraw(address(this), type(uint256).max);
    }

    // Test view functions
    function testAllViewFunctions() public {
        assertEq(strategy.name(), "Simple Multi-Collateral Strategy");
        assertEq(strategy.symbol(), "SMCS");
        assertEq(strategy.asset(), address(sovaBTC));
        assertEq(strategy.assetDecimals(), 8);
        assertEq(strategy.collateralRegistry(), address(registry));
        assertEq(strategy.manager(), manager);
        assertEq(strategy.sToken(), vault);
        assertEq(strategy.balance(), 0);
        assertEq(strategy.totalCollateralValue(), 0);
    }
}
