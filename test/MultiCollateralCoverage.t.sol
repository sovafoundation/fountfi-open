// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {tRWA} from "../src/token/tRWA-multicollateral.sol";
import {MultiCollateralRegistry} from "../contracts/MultiCollateralRegistry.sol";
import {SimpleMultiCollateralStrategy} from "../contracts/SimpleMultiCollateralStrategy.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract MultiCollateralCoverageTest is Test {
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

    function setUp() public {
        // Deploy role manager
        roleManager = new RoleManager();
        roleManager.grantRole(admin, roleManager.PROTOCOL_ADMIN());
        roleManager.grantRole(manager, roleManager.STRATEGY_ADMIN());

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

        // Deploy vault
        vault = new tRWA(
            "Multi-Collateral Bitcoin Vault", "mcBTC", address(sovaBTC), 8, address(strategy), address(sovaBTC)
        );

        // Connect strategy to vault
        strategy.setSToken(address(vault));

        // Mint tokens for testing
        wbtc.mint(user, 10e8);
        tbtc.mint(user, 10e18);
        sovaBTC.mint(user, 10e8);
        sovaBTC.mint(manager, 100e8);

        wbtc.mint(user2, 5e8);
        sovaBTC.mint(user2, 5e8);
    }

    // Test view functions
    function testVaultViewFunctions() public {
        assertEq(vault.name(), "Multi-Collateral Bitcoin Vault");
        assertEq(vault.symbol(), "mcBTC");
        assertEq(vault.decimals(), 18); // ERC4626 shares are 18 decimals
        assertEq(vault.asset(), address(sovaBTC));
        assertEq(vault.underlyingAsset(), address(sovaBTC));
        assertEq(vault.strategy(), address(strategy));
        assertEq(vault.sovaBTC(), address(sovaBTC));
    }

    // Test edge cases
    function testDepositZeroAmount() public {
        vm.startPrank(user);
        wbtc.approve(address(vault), 1e8);

        vm.expectRevert("Zero amount");
        vault.depositCollateral(address(wbtc), 0, user);
        vm.stopPrank();
    }

    function testDepositNonAllowedCollateral() public {
        MockERC20 randomToken = new MockERC20("Random", "RND", 18);
        randomToken.mint(user, 1e18);

        vm.startPrank(user);
        randomToken.approve(address(vault), 1e18);

        vm.expectRevert();
        vault.depositCollateral(address(randomToken), 1e18, user);
        vm.stopPrank();
    }

    // Test withdrawal flow with partial redemption
    function testPartialWithdrawalFlow() public {
        // Deposit SovaBTC for simpler redemption
        vm.startPrank(user);
        sovaBTC.approve(address(vault), 2e8);
        uint256 shares = vault.depositCollateral(address(sovaBTC), 2e8, user);
        vm.stopPrank();

        // Withdraw half of the shares
        uint256 halfShares = shares / 2;

        vm.prank(user);
        uint256 assets = vault.redeem(halfShares, user, user);

        // Should get back half of deposited amount
        assertEq(assets, 1e8);
        assertEq(vault.balanceOf(user), halfShares);
    }

    // Test full withdrawal with sufficient redemption funds
    function testFullWithdrawalFlow() public {
        // This test demonstrates a limitation of the SimpleMultiCollateralStrategy:
        // It cannot convert collateral to SovaBTC for redemptions.
        // In production, a more sophisticated strategy would handle conversions.

        // Deposit SovaBTC directly (which can be redeemed 1:1)
        vm.startPrank(user);
        sovaBTC.approve(address(vault), 1e8);
        uint256 shares = vault.depositCollateral(address(sovaBTC), 1e8, user);
        vm.stopPrank();

        // No need to add redemption funds since we deposited SovaBTC

        // Redeem all shares
        vm.prank(user);
        uint256 assets = vault.redeem(shares, user, user);

        // Should get back exactly what was deposited
        assertEq(assets, 1e8);
        assertEq(sovaBTC.balanceOf(user), 10e8); // 10e8 initial - 1e8 deposited + 1e8 withdrawn = 10e8
        assertEq(vault.balanceOf(user), 0);
    }

    // Test allowance spending in withdrawal
    function testWithdrawWithAllowance() public {
        // Deposit SovaBTC for direct redemption
        vm.startPrank(user);
        sovaBTC.approve(address(vault), 1e8);
        uint256 shares = vault.depositCollateral(address(sovaBTC), 1e8, user);

        // Approve user2 to spend shares
        vault.approve(user2, shares);
        vm.stopPrank();

        // User2 redeems shares on behalf of user
        vm.prank(user2);
        uint256 assets = vault.redeem(shares, user2, user);

        assertEq(assets, 1e8);
        assertEq(sovaBTC.balanceOf(user2), 6e8); // 5e8 initial + 1e8 withdrawn
        assertEq(vault.balanceOf(user), 0);
    }
}
