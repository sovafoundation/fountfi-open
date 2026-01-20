// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {tRWA} from "../src/token/tRWA-multicollateral.sol";
import {MultiCollateralRegistry} from "../contracts/MultiCollateralRegistry.sol";
import {SimpleMultiCollateralStrategy} from "../contracts/SimpleMultiCollateralStrategy.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {IStrategy} from "../src/strategy/IStrategy.sol";

contract tRWAMultiCollateralTest is Test {
    tRWA public vault;
    MultiCollateralRegistry public registry;
    SimpleMultiCollateralStrategy public strategy;
    RoleManager public roleManager;

    address public admin = address(0x1);
    address public manager = address(0x2);
    address public user = address(0x4);
    address public user2 = address(0x5);

    MockERC20 public sovaBTC;
    MockERC20 public wbtc;
    MockERC20 public tbtc;
    MockERC20 public cbBTC;

    function setUp() public {
        // Deploy role manager
        roleManager = new RoleManager();
        roleManager.grantRole(admin, roleManager.PROTOCOL_ADMIN());

        // Deploy tokens
        sovaBTC = new MockERC20("SovaBTC", "SBTC", 8);
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        tbtc = new MockERC20("tBTC", "TBTC", 18);
        cbBTC = new MockERC20("Coinbase BTC", "cbBTC", 8);

        // Deploy registry for multi-collateral
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

        // Deploy vault
        vault = new tRWA(
            "Multi-Collateral Bitcoin Vault", "mcBTC", address(sovaBTC), 8, address(strategy), address(sovaBTC)
        );

        // Setup connections
        strategy.setSToken(address(vault));

        // Grant roles - RoleManager owner (test contract) grants roles
        roleManager.grantRole(address(strategy), roleManager.STRATEGY_ADMIN());
        roleManager.grantRole(address(vault), roleManager.PROTOCOL_ADMIN());

        // Mint tokens for testing
        wbtc.mint(user, 10e8); // 10 WBTC
        tbtc.mint(user, 10e18); // 10 tBTC
        cbBTC.mint(user, 10e8); // 10 cbBTC
        sovaBTC.mint(user, 10e8); // 10 SovaBTC
        sovaBTC.mint(manager, 100e8); // 100 SovaBTC for redemptions

        wbtc.mint(user2, 5e8); // 5 WBTC
        tbtc.mint(user2, 5e18); // 5 tBTC
    }

    function testVaultSetup() public {
        assertEq(vault.name(), "Multi-Collateral Bitcoin Vault");
        assertEq(vault.symbol(), "mcBTC");
        assertEq(vault.asset(), address(sovaBTC));
        assertEq(vault.sovaBTC(), address(sovaBTC));
        assertEq(vault.strategy(), address(strategy));
        assertEq(vault.decimals(), 18); // ERC4626 shares are 18 decimals
    }

    function testDepositCollateralWBTC() public {
        uint256 depositAmount = 1e8; // 1 WBTC

        vm.startPrank(user);
        wbtc.approve(address(vault), depositAmount);

        uint256 sharesBefore = vault.balanceOf(user);
        uint256 shares = vault.depositCollateral(address(wbtc), depositAmount, user);
        vm.stopPrank();

        assertGt(shares, 0);
        assertEq(vault.balanceOf(user), sharesBefore + shares);
        assertEq(wbtc.balanceOf(address(strategy)), depositAmount);
        assertEq(strategy.collateralBalances(address(wbtc)), depositAmount);
    }

    function testDepositCollateralTBTC() public {
        uint256 depositAmount = 2e18; // 2 tBTC

        vm.startPrank(user);
        tbtc.approve(address(vault), depositAmount);

        uint256 shares = vault.depositCollateral(address(tbtc), depositAmount, user);
        vm.stopPrank();

        assertGt(shares, 0);
        assertEq(vault.balanceOf(user), shares);
        assertEq(tbtc.balanceOf(address(strategy)), depositAmount);
        assertEq(strategy.collateralBalances(address(tbtc)), depositAmount);

        // Check total value in SovaBTC terms
        assertEq(strategy.totalCollateralValue(), 2e8); // 2 SovaBTC worth
    }

    function testDepositCollateralSovaBTC() public {
        uint256 depositAmount = 3e8; // 3 SovaBTC

        vm.startPrank(user);
        sovaBTC.approve(address(vault), depositAmount);

        uint256 shares = vault.depositCollateral(address(sovaBTC), depositAmount, user);
        vm.stopPrank();

        assertGt(shares, 0);
        assertEq(vault.balanceOf(user), shares);
        assertEq(sovaBTC.balanceOf(address(strategy)), depositAmount);
        assertEq(strategy.collateralBalances(address(sovaBTC)), depositAmount);
    }

    function testMultipleUsersDepositDifferentCollateral() public {
        // User 1 deposits WBTC
        vm.startPrank(user);
        wbtc.approve(address(vault), 1e8);
        uint256 shares1 = vault.depositCollateral(address(wbtc), 1e8, user);
        vm.stopPrank();

        // User 2 deposits tBTC
        vm.startPrank(user2);
        tbtc.approve(address(vault), 2e18);
        uint256 shares2 = vault.depositCollateral(address(tbtc), 2e18, user2);
        vm.stopPrank();

        // Check balances
        assertEq(vault.balanceOf(user), shares1);
        assertEq(vault.balanceOf(user2), shares2);

        // Total value should be 3 SovaBTC (1 from WBTC + 2 from tBTC)
        assertEq(strategy.totalCollateralValue(), 3e8);
        assertEq(vault.totalSupply(), shares1 + shares2);
    }

    function testDepositMultipleCollateralsSameUser() public {
        vm.startPrank(user);

        // Deposit WBTC
        wbtc.approve(address(vault), 1e8);
        uint256 shares1 = vault.depositCollateral(address(wbtc), 1e8, user);

        // Deposit tBTC
        tbtc.approve(address(vault), 1e18);
        uint256 shares2 = vault.depositCollateral(address(tbtc), 1e18, user);

        // Deposit cbBTC
        cbBTC.approve(address(vault), 0.5e8);
        uint256 shares3 = vault.depositCollateral(address(cbBTC), 0.5e8, user);

        vm.stopPrank();

        // Total shares
        uint256 totalShares = shares1 + shares2 + shares3;
        assertEq(vault.balanceOf(user), totalShares);

        // Total value: 1 + 1 + 0.5 = 2.5 SovaBTC
        assertEq(strategy.totalCollateralValue(), 2.5e8);
    }

    function testRedeemAfterMultiCollateralDeposits() public {
        // Setup: Multiple deposits
        vm.startPrank(user);
        wbtc.approve(address(vault), 2e8);
        vault.depositCollateral(address(wbtc), 2e8, user);

        tbtc.approve(address(vault), 1e18);
        vault.depositCollateral(address(tbtc), 1e18, user);
        vm.stopPrank();

        // Manager deposits redemption funds
        vm.startPrank(manager);
        sovaBTC.approve(address(strategy), 10e8);
        strategy.depositRedemptionFunds(10e8);
        vm.stopPrank();

        // User redeems half their shares
        uint256 userShares = vault.balanceOf(user);
        uint256 redeemShares = userShares / 2;

        vm.startPrank(user);
        uint256 assetsReceived = vault.redeem(redeemShares, user, user);
        vm.stopPrank();

        // Should receive SovaBTC
        assertGt(assetsReceived, 0);
        assertEq(vault.balanceOf(user), userShares - redeemShares);
    }

    function testDepositWithNonAllowedCollateral() public {
        MockERC20 randomToken = new MockERC20("Random", "RND", 18);
        randomToken.mint(user, 1e18);

        vm.startPrank(user);
        randomToken.approve(address(vault), 1e18);

        // Should revert through registry check
        vm.expectRevert();
        vault.depositCollateral(address(randomToken), 1e18, user);
        vm.stopPrank();
    }

    function testShareCalculationWithDifferentDecimals() public {
        // First deposit sets the price
        vm.startPrank(user);
        wbtc.approve(address(vault), 1e8);
        uint256 firstShares = vault.depositCollateral(address(wbtc), 1e8, user);
        vm.stopPrank();

        // Second deposit with 18 decimal token
        vm.startPrank(user2);
        tbtc.approve(address(vault), 1e18);
        uint256 secondShares = vault.depositCollateral(address(tbtc), 1e18, user2);
        vm.stopPrank();

        // Both deposited 1 BTC worth, should get same shares
        assertEq(firstShares, secondShares);
    }

    function testDepositZeroAmount() public {
        vm.startPrank(user);
        wbtc.approve(address(vault), 1e8);

        vm.expectRevert();
        vault.depositCollateral(address(wbtc), 0, user);
        vm.stopPrank();
    }

    function testPreviewFunctions() public {
        // Setup initial deposit
        vm.startPrank(user);
        wbtc.approve(address(vault), 2e8);
        vault.depositCollateral(address(wbtc), 2e8, user);
        vm.stopPrank();

        // Preview deposit (in SovaBTC terms)
        uint256 previewShares = vault.previewDeposit(1e8); // 1 SovaBTC worth
        assertGt(previewShares, 0);

        // Preview redeem
        uint256 userShares = vault.balanceOf(user);
        uint256 previewAssets = vault.previewRedeem(userShares);
        assertEq(previewAssets, 2e8); // Should get back 2 SovaBTC worth
    }

    function testMaxDepositAndMaxMint() public {
        // These should work with SovaBTC as the asset
        uint256 maxDep = vault.maxDeposit(user);
        uint256 maxMnt = vault.maxMint(user);

        assertGt(maxDep, 0);
        assertGt(maxMnt, 0);
    }

    function testRateChangeImpact() public {
        // Deposit WBTC at 1:1 rate
        vm.startPrank(user);
        wbtc.approve(address(vault), 1e8);
        uint256 sharesAt1to1 = vault.depositCollateral(address(wbtc), 1e8, user);
        vm.stopPrank();

        // Change WBTC rate to 0.95 (depeg scenario)
        vm.prank(admin);
        registry.updateRate(address(wbtc), 0.95e18);

        // New deposit should get more shares for same WBTC amount
        vm.startPrank(user2);
        wbtc.approve(address(vault), 1e8);
        uint256 sharesAt095 = vault.depositCollateral(address(wbtc), 1e8, user2);
        vm.stopPrank();

        // User2 should get fewer shares because their WBTC is worth less
        assertLt(sharesAt095, sharesAt1to1);
    }

    function testComplexScenarioWithRedemptions() public {
        // Multiple users deposit different collaterals
        vm.startPrank(user);
        wbtc.approve(address(vault), 3e8);
        vault.depositCollateral(address(wbtc), 3e8, user);

        cbBTC.approve(address(vault), 2e8);
        vault.depositCollateral(address(cbBTC), 2e8, user);
        vm.stopPrank();

        vm.startPrank(user2);
        tbtc.approve(address(vault), 4e18);
        vault.depositCollateral(address(tbtc), 4e18, user2);
        vm.stopPrank();

        // Total value: 3 + 2 + 4 = 9 SovaBTC
        assertEq(strategy.totalCollateralValue(), 9e8);

        // Manager adds redemption funds
        vm.startPrank(manager);
        sovaBTC.approve(address(strategy), 20e8);
        strategy.depositRedemptionFunds(20e8);
        vm.stopPrank();

        // User1 withdraws some
        uint256 user1Shares = vault.balanceOf(user);
        vm.startPrank(user);
        vault.withdraw(2e8, user, user); // Withdraw 2 SovaBTC worth
        vm.stopPrank();

        // Check user received SovaBTC
        assertGt(sovaBTC.balanceOf(user), 10e8); // Started with 10, should have more

        // User2 redeems all
        vm.startPrank(user2);
        uint256 user2Shares = vault.balanceOf(user2);
        uint256 user2Assets = vault.redeem(user2Shares, user2, user2);
        vm.stopPrank();

        // User2 should get back their proportional share of the total value
        // They deposited 4 BTC worth out of 9 total, so they should get ~44.44% of total value
        assertGt(user2Assets, 4e8); // Should get back at least 4 SovaBTC worth
    }
}
