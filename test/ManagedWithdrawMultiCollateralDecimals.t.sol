// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {ManagedWithdrawRWA} from "../src/token/ManagedWithdrawRWA-multicollateral.sol";
import {ManagedWithdrawMultiCollateralStrategy} from "../src/strategy/ManagedWithdrawMultiCollateralStrategy.sol";
import {MultiCollateralRegistry} from "../contracts/MultiCollateralRegistry.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {Registry} from "../src/registry/Registry.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

contract ManagedWithdrawMultiCollateralDecimalsTest is Test {
    ManagedWithdrawMultiCollateralStrategy public strategy;
    ManagedWithdrawRWA public vault;
    MultiCollateralRegistry public registry;
    RoleManager public roleManager;
    
    MockERC20 public wbtc;     // 8 decimals
    MockERC20 public tbtc;     // 18 decimals
    MockERC20 public cbbtc;    // 8 decimals
    MockERC20 public sovaBTC;  // 8 decimals
    
    address public manager = address(0x1);
    address public user;
    uint256 public userPrivateKey = 0x2;
    
    function setUp() public {
        // Setup user address from private key
        user = vm.addr(userPrivateKey);
        
        // Deploy mock tokens with proper decimals
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        tbtc = new MockERC20("Threshold Bitcoin", "tBTC", 18);
        cbbtc = new MockERC20("Coinbase Bitcoin", "cbBTC", 8);
        sovaBTC = new MockERC20("Sova Bitcoin", "sovaBTC", 8);
        
        // Deploy infrastructure
        roleManager = new RoleManager();
        registry = new MultiCollateralRegistry(address(roleManager), address(sovaBTC));
        
        // Grant admin role to this test contract
        roleManager.grantRoles(address(this), roleManager.PROTOCOL_ADMIN());
        
        // Initialize registry with proper decimals and 1:1 rates
        registry.addCollateral(address(wbtc), 1e18, 8);   // 1:1 rate, 8 decimals
        registry.addCollateral(address(tbtc), 1e18, 18);  // 1:1 rate, 18 decimals
        registry.addCollateral(address(cbbtc), 1e18, 8);  // 1:1 rate, 8 decimals
        registry.addCollateral(address(sovaBTC), 1e18, 8); // SovaBTC itself
        
        // Deploy and initialize strategy
        strategy = new ManagedWithdrawMultiCollateralStrategy();
        bytes memory initData = abi.encode(address(registry), address(sovaBTC));
        strategy.initialize(
            "SovaBTC Yield Token",
            "vBTC",
            address(roleManager),
            manager,
            address(sovaBTC),
            8,  // CRITICAL: 8 decimals for Bitcoin standard
            initData
        );
        
        vault = ManagedWithdrawRWA(strategy.sToken());
        
        // Setup roles
        roleManager.grantRoles(manager, roleManager.STRATEGY_ADMIN());
        roleManager.grantRoles(address(strategy), roleManager.STRATEGY_OPERATOR());
        
        // Fund users with tokens
        wbtc.mint(user, 10e8);     // 10 WBTC
        tbtc.mint(user, 10e18);    // 10 tBTC
        cbbtc.mint(user, 10e8);    // 10 cbBTC
        sovaBTC.mint(manager, 100e8); // 100 sovaBTC for redemptions
        
        // Approve vault for all tokens
        vm.startPrank(user);
        wbtc.approve(address(vault), type(uint256).max);
        tbtc.approve(address(vault), type(uint256).max);
        cbbtc.approve(address(vault), type(uint256).max);
        vm.stopPrank();
        
        vm.prank(manager);
        sovaBTC.approve(address(strategy), type(uint256).max);
    }
    
    function test_DecimalConversion_WBTC() public {
        uint256 depositAmount = 1e8; // 1 WBTC (8 decimals)
        
        vm.startPrank(user);
        
        // Preview the deposit
        uint256 expectedShares = vault.previewDeposit(depositAmount);
        console2.log("Depositing 1 WBTC (1e8)");
        console2.log("Expected shares:", expectedShares);
        
        // Deposit WBTC
        uint256 shares = vault.depositCollateral(address(wbtc), depositAmount, user);
        console2.log("Actual shares received:", shares);
        
        // Verify shares are in 18 decimals (1e18 for 1 BTC worth)
        assertEq(vault.decimals(), 18, "Vault shares should be 18 decimals");
        assertEq(shares, 1e18, "Should receive 1e18 shares for 1 WBTC");
        assertEq(vault.balanceOf(user), 1e18, "User balance should be 1e18 shares");
        
        // Verify total assets (in 8 decimals)
        uint256 totalAssets = vault.totalAssets();
        console2.log("Total assets in vault:", totalAssets);
        assertEq(totalAssets, 1e8, "Total assets should be 1e8 (1 BTC in 8 decimals)");
        
        vm.stopPrank();
    }
    
    function test_DecimalConversion_tBTC() public {
        uint256 depositAmount = 1e18; // 1 tBTC (18 decimals)
        
        vm.startPrank(user);
        
        console2.log("Depositing 1 tBTC (1e18)");
        
        // Deposit tBTC
        uint256 shares = vault.depositCollateral(address(tbtc), depositAmount, user);
        console2.log("Shares received:", shares);
        
        // Verify shares are in 18 decimals (1e18 for 1 BTC worth)
        assertEq(shares, 1e18, "Should receive 1e18 shares for 1 tBTC");
        assertEq(vault.balanceOf(user), 1e18, "User balance should be 1e18 shares");
        
        // Verify total assets (in 8 decimals)
        uint256 totalAssets = vault.totalAssets();
        console2.log("Total assets in vault:", totalAssets);
        assertEq(totalAssets, 1e8, "Total assets should be 1e8 (1 BTC in 8 decimals)");
        
        vm.stopPrank();
    }
    
    function test_DecimalConversion_MixedDeposits() public {
        vm.startPrank(user);
        
        // Deposit 0.5 WBTC (8 decimals)
        uint256 wbtcDeposit = 5e7; // 0.5 WBTC
        uint256 wbtcShares = vault.depositCollateral(address(wbtc), wbtcDeposit, user);
        console2.log("0.5 WBTC shares:", wbtcShares);
        assertEq(wbtcShares, 5e17, "Should receive 0.5e18 shares for 0.5 WBTC");
        
        // Deposit 0.3 tBTC (18 decimals)
        uint256 tbtcDeposit = 3e17; // 0.3 tBTC
        uint256 tbtcShares = vault.depositCollateral(address(tbtc), tbtcDeposit, user);
        console2.log("0.3 tBTC shares:", tbtcShares);
        assertEq(tbtcShares, 3e17, "Should receive 0.3e18 shares for 0.3 tBTC");
        
        // Deposit 0.2 cbBTC (8 decimals)
        uint256 cbbtcDeposit = 2e7; // 0.2 cbBTC
        uint256 cbbtcShares = vault.depositCollateral(address(cbbtc), cbbtcDeposit, user);
        console2.log("0.2 cbBTC shares:", cbbtcShares);
        assertEq(cbbtcShares, 2e17, "Should receive 0.2e18 shares for 0.2 cbBTC");
        
        // Verify total position
        uint256 totalShares = vault.balanceOf(user);
        console2.log("Total shares:", totalShares);
        assertEq(totalShares, 1e18, "Total shares should be 1e18 (1 BTC worth)");
        
        // Verify total assets
        uint256 totalAssets = vault.totalAssets();
        console2.log("Total assets:", totalAssets);
        assertEq(totalAssets, 1e8, "Total assets should be 1e8 (1 BTC in 8 decimals)");
        
        vm.stopPrank();
    }
    
    function test_SharePriceAfterMultipleDeposits() public {
        // First user deposits 1 WBTC
        vm.prank(user);
        vault.depositCollateral(address(wbtc), 1e8, user);
        
        // Second user deposits 1 WBTC
        address user2 = address(0x3);
        wbtc.mint(user2, 1e8);
        vm.startPrank(user2);
        wbtc.approve(address(vault), type(uint256).max);
        uint256 shares = vault.depositCollateral(address(wbtc), 1e8, user2);
        vm.stopPrank();
        
        // Both users should have equal shares (1e18 each)
        assertEq(vault.balanceOf(user), 1e18, "User1 should have 1e18 shares");
        assertEq(vault.balanceOf(user2), 1e18, "User2 should have 1e18 shares");
        
        // Total supply should be 2e18
        assertEq(vault.totalSupply(), 2e18, "Total supply should be 2e18");
        
        // Total assets should be 2e8 (2 BTC in 8 decimals)
        assertEq(vault.totalAssets(), 2e8, "Total assets should be 2e8");
    }
    
    function test_RedemptionDecimalConversion() public {
        // Setup: User deposits 1 WBTC
        vm.prank(user);
        vault.depositCollateral(address(wbtc), 1e8, user);
        
        // User approves strategy to pull shares
        vm.prank(user);
        vault.approve(address(strategy), type(uint256).max);
        
        // Manager prepares redemption with SovaBTC
        vm.prank(manager);
        strategy.depositRedemptionFunds(1e8); // 1 sovaBTC (8 decimals)
        
        // Create withdrawal request for full amount
        ManagedWithdrawMultiCollateralStrategy.WithdrawalRequest memory request = 
            ManagedWithdrawMultiCollateralStrategy.WithdrawalRequest({
                owner: user,
                to: user,
                shares: 1e18, // Redeeming 1e18 shares
                minAssets: 1e8, // Expecting at least 1 BTC (8 decimals)
                nonce: 0,
                expirationTime: uint96(block.timestamp + 1 hours)
            });
        
        // Create domain separator
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("MWMCS"),
                keccak256("1"),
                block.chainid,
                address(strategy)
            )
        );
        
        // Sign the request
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator,
            keccak256(abi.encode(
                keccak256("WithdrawalRequest(address owner,address to,uint256 shares,uint256 minAssets,uint96 nonce,uint96 expirationTime)"),
                request.owner,
                request.to,
                request.shares,
                request.minAssets,
                request.nonce,
                request.expirationTime
            ))
        ));
        
        // Sign with user's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        
        ManagedWithdrawMultiCollateralStrategy.Signature memory sig = 
            ManagedWithdrawMultiCollateralStrategy.Signature({v: v, r: r, s: s});
        
        // Process redemption
        uint256 initialBalance = sovaBTC.balanceOf(user);
        vm.prank(manager);
        uint256 assets = strategy.redeem(request, sig);
        
        // Verify redemption amounts
        assertEq(assets, 1e8, "Should receive 1e8 sovaBTC (1 BTC)");
        assertEq(sovaBTC.balanceOf(user) - initialBalance, 1e8, "User should receive 1e8 sovaBTC");
        assertEq(vault.balanceOf(user), 0, "User should have no shares left");
    }
}