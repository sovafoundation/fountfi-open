// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {tRWA} from "../src/token/tRWA-multicollateral.sol";
import {MultiCollateralRegistry} from "../contracts/MultiCollateralRegistry.sol";
import {SimpleMultiCollateralStrategy} from "../contracts/SimpleMultiCollateralStrategy.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/**
 * @title Additional coverage tests to reach 100% line coverage
 * @notice Tests any remaining edge cases and view functions
 */
contract MultiCollateralExtraCoverageTest is Test {
    tRWA public vault;
    MultiCollateralRegistry public registry;
    SimpleMultiCollateralStrategy public strategy;
    RoleManager public roleManager;

    address public admin = address(0x1);
    address public manager = address(0x2);
    address public user = address(0x4);

    MockERC20 public sovaBTC;
    MockERC20 public wbtc;

    function setUp() public {
        // Deploy role manager
        roleManager = new RoleManager();
        roleManager.grantRole(admin, roleManager.PROTOCOL_ADMIN());

        // Deploy tokens
        sovaBTC = new MockERC20("SovaBTC", "SBTC", 8);
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);

        // Deploy registry
        registry = new MultiCollateralRegistry(address(roleManager), address(sovaBTC));

        // Add collaterals
        vm.prank(admin);
        registry.addCollateral(address(wbtc), 1e18, 8);

        // Deploy strategy
        strategy = new SimpleMultiCollateralStrategy(address(sovaBTC), 8, address(registry), manager);

        // Deploy vault
        vault = new tRWA(
            "Multi-Collateral Bitcoin Vault", "mcBTC", address(sovaBTC), 8, address(strategy), address(sovaBTC)
        );

        // Connect strategy to vault
        strategy.setSToken(address(vault));
    }

    // Test view functions that might not be covered
    function testRegistryViewFunctions() public view {
        // Test sovaBTC getter
        assertEq(registry.sovaBTC(), address(sovaBTC));

        // Test allowedCollateral mapping
        assertTrue(registry.allowedCollateral(address(wbtc)));
        assertFalse(registry.allowedCollateral(address(0x123)));

        // Test collateralToSovaBTCRate mapping
        assertEq(registry.collateralToSovaBTCRate(address(wbtc)), 1e18);
        assertEq(registry.collateralToSovaBTCRate(address(0x123)), 0);

        // Test collateralDecimals mapping
        assertEq(registry.collateralDecimals(address(wbtc)), 8);
        assertEq(registry.collateralDecimals(address(0x123)), 0);

        // Test collateralTokens array access
        assertEq(registry.collateralTokens(0), address(wbtc));
    }

    // Test strategy view functions
    function testStrategyViewFunctions() public {
        // Test all getters
        assertEq(strategy.asset(), address(sovaBTC));
        assertEq(strategy.assetDecimals(), 8);
        assertEq(strategy.collateralRegistry(), address(registry));
        assertEq(strategy.manager(), manager);
        assertEq(strategy.sToken(), address(vault));

        // Test empty state
        assertEq(strategy.balance(), 0);
        assertEq(strategy.totalCollateralValue(), 0);

        // Test heldCollateralTokens when empty
        vm.expectRevert();
        strategy.heldCollateralTokens(0);

        // Test isHeldCollateral when empty
        assertFalse(strategy.isHeldCollateral(address(wbtc)));

        // Test collateralBalances when empty
        assertEq(strategy.collateralBalances(address(wbtc)), 0);
    }

    // Test vault specific getters
    function testVaultSpecificGetters() public view {
        // Test sovaBTC getter
        assertEq(vault.sovaBTC(), address(sovaBTC));

        // Test operation constants
        assertEq(vault.OP_DEPOSIT(), keccak256("DEPOSIT_OPERATION"));
        assertEq(vault.OP_WITHDRAW(), keccak256("WITHDRAW_OPERATION"));
        assertEq(vault.OP_TRANSFER(), keccak256("TRANSFER_OPERATION"));

        // Test lastExecutedBlock mapping
        assertEq(vault.lastExecutedBlock(vault.OP_DEPOSIT()), 0);
        assertEq(vault.lastExecutedBlock(vault.OP_WITHDRAW()), 0);
        assertEq(vault.lastExecutedBlock(vault.OP_TRANSFER()), 0);
    }

    // Test depositCollateral with zero address receiver (should use msg.sender)
    function testDepositCollateralDefaultReceiver() public {
        wbtc.mint(user, 1e8);

        vm.startPrank(user);
        wbtc.approve(address(vault), 1e8);

        // Call depositCollateral without specifying receiver (address(0))
        // This isn't possible with the current function signature, but we can test with msg.sender
        uint256 shares = vault.depositCollateral(address(wbtc), 1e8, user);

        assertEq(vault.balanceOf(user), shares);
        vm.stopPrank();
    }

    // Test edge case: deposit when strategy already has the collateral
    function testDepositWithPreExistingCollateral() public {
        // First, mint some WBTC directly to strategy
        wbtc.mint(address(strategy), 5e8);

        // Now deposit through vault
        wbtc.mint(user, 1e8);
        vm.startPrank(user);
        wbtc.approve(address(vault), 1e8);
        uint256 shares = vault.depositCollateral(address(wbtc), 1e8, user);
        vm.stopPrank();

        // Verify the deposit worked correctly
        assertEq(vault.balanceOf(user), shares);
        assertEq(strategy.collateralBalances(address(wbtc)), 1e8);
    }

    // Test totalAssets when strategy has mixed funds
    function testTotalAssetsWithMixedFunds() public {
        // Deposit collateral
        wbtc.mint(user, 1e8);
        vm.startPrank(user);
        wbtc.approve(address(vault), 1e8);
        vault.depositCollateral(address(wbtc), 1e8, user);
        vm.stopPrank();

        // Add redemption funds
        sovaBTC.mint(manager, 2e8);
        vm.startPrank(manager);
        sovaBTC.approve(address(strategy), 2e8);
        strategy.depositRedemptionFunds(2e8);
        vm.stopPrank();

        // Total assets should be 3e8 (1e8 WBTC + 2e8 SovaBTC)
        assertEq(vault.totalAssets(), 3e8);
    }

    // Test all conversion functions with edge values
    function testConversionEdgeCases() public {
        // Test conversion of 0
        assertEq(vault.convertToShares(0), 0);
        assertEq(vault.convertToAssets(0), 0);
        assertEq(vault.previewDeposit(0), 0);
        assertEq(vault.previewMint(0), 0);
        assertEq(vault.previewWithdraw(0), 0);
        assertEq(vault.previewRedeem(0), 0);

        // Test with some supply
        wbtc.mint(user, 1e8);
        vm.startPrank(user);
        wbtc.approve(address(vault), 1e8);
        vault.depositCollateral(address(wbtc), 1e8, user);
        vm.stopPrank();

        // Test conversions with supply
        assertEq(vault.convertToShares(0), 0);
        assertEq(vault.convertToAssets(0), 0);
    }
}
