// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {ManagedWithdrawRWA} from "../src/token/ManagedWithdrawRWA-multicollateral.sol";
import {tRWA} from "../src/token/tRWA-multicollateral.sol";
import {ManagedWithdrawMultiCollateralStrategy} from "../src/strategy/ManagedWithdrawMultiCollateralStrategy.sol";
import {MultiCollateralRegistry} from "../contracts/MultiCollateralRegistry.sol";
import {Registry} from "../src/registry/Registry.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {IHook} from "../src/hooks/IHook.sol";
import {MockHook} from "../src/mocks/hooks/MockHook.sol";
import {IStrategy} from "../src/strategy/IStrategy.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

// Mock reporter for testing
contract MockReporter {
    function report() external pure returns (bytes memory) {
        return abi.encode(1e18); // Return 1:1 price
    }
}

contract ManagedWithdrawMultiCollateralFullTest is Test {
    ManagedWithdrawRWA public vault;
    ManagedWithdrawMultiCollateralStrategy public strategy;
    MultiCollateralRegistry public registry;
    RoleManager public roleManager;
    
    MockERC20 public sovaBTC;
    MockERC20 public wbtc;
    MockERC20 public tbtc;
    MockERC20 public cbbtc;
    MockHook public hook;
    
    address public manager = address(0x1);
    address public user1;
    address public user2;
    
    uint256 public user1PrivateKey = 0xA11CE;
    uint256 public user2PrivateKey = 0xB0B;
    
    // EIP-712 constants
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        
    bytes32 private constant WITHDRAWAL_REQUEST_TYPEHASH = keccak256(
        "WithdrawalRequest(address owner,address to,uint256 shares,uint256 minAssets,uint96 nonce,uint96 expirationTime)"
    );
    
    // Hook operation types
    bytes32 public constant OP_WITHDRAW = keccak256("WITHDRAW_OPERATION");
    
    event CollateralDeposited(address indexed token, uint256 amount);
    event WithdrawalNonceUsed(address indexed owner, uint96 nonce);
    event HookAdded(bytes32 indexed operationType, address indexed hookAddress, uint256 index);
    event HookRemoved(bytes32 indexed operationType, address indexed hookAddress);
    event HooksReordered(bytes32 indexed operationType, uint256[] newIndices);
    event WithdrawHookCalled(address token, address by, uint256 assets, address to, address owner);
    
    function setUp() public {
        // Deploy tokens
        sovaBTC = new MockERC20("SovaBTC", "SovaBTC", 8);
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        tbtc = new MockERC20("tBTC", "tBTC", 18);
        cbbtc = new MockERC20("Coinbase BTC", "cbBTC", 8);
        
        // Deploy infrastructure
        roleManager = new RoleManager();
        registry = new MultiCollateralRegistry(address(roleManager), address(sovaBTC));
        
        // Grant admin role to test contract
        vm.prank(address(roleManager.owner()));
        roleManager.grantRoles(address(this), roleManager.PROTOCOL_ADMIN());
        
        // Initialize registry in RoleManager
        vm.prank(address(roleManager.owner()));
        roleManager.initializeRegistry(address(registry));
        
        // Configure registry with 1:1 rates for simplicity (rates are in 18 decimals)
        registry.addCollateral(address(wbtc), 1e18, 8);
        registry.addCollateral(address(tbtc), 1e18, 18);
        registry.addCollateral(address(cbbtc), 1e18, 8);
        registry.addCollateral(address(sovaBTC), 1e18, 8);
        
        // Deploy strategy
        strategy = new ManagedWithdrawMultiCollateralStrategy();
        
        // Initialize strategy with multi-collateral config
        bytes memory initData = abi.encode(address(registry), address(sovaBTC));
        strategy.initialize(
            "SovaBTC Yield Token",
            "vBTC",
            address(roleManager),
            manager,
            address(sovaBTC),
            8,
            initData
        );
        
        // Get deployed vault
        vault = ManagedWithdrawRWA(strategy.sToken());
        
        // Setup roles
        roleManager.grantRoles(address(this), roleManager.PROTOCOL_ADMIN());
        roleManager.grantRoles(address(strategy), roleManager.STRATEGY_OPERATOR());
        
        // Setup users first
        user1 = vm.addr(user1PrivateKey);
        user2 = vm.addr(user2PrivateKey);
        
        // Fund users after addresses are set
        wbtc.mint(user1, 10e8);
        tbtc.mint(user1, 10e18);
        cbbtc.mint(user2, 5e8);
        sovaBTC.mint(manager, 5000e8); // Mint more for testing
        
        // Deploy mock hook
        hook = new MockHook(true, "");
        
        vm.label(manager, "Manager");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
    }
    
    /*//////////////////////////////////////////////////////////////
                    MANAGEDWITHDRAWRWA TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constructor() public {
        // Test that constructor sets correct values
        assertEq(vault.name(), "SovaBTC Yield Token");
        assertEq(vault.symbol(), "vBTC");
        assertEq(vault.decimals(), 18); // ERC4626 shares always 18
        assertEq(vault.asset(), address(sovaBTC));
        assertEq(address(vault.sovaBTC()), address(sovaBTC));
        assertEq(vault.strategy(), address(strategy));
    }
    
    function test_Withdraw_AlwaysReverts() public {
        vm.expectRevert(ManagedWithdrawRWA.UseRedeem.selector);
        vault.withdraw(100e8, user1, user1);
    }
    
    function test_Redeem_OnlyStrategy() public {
        // Try to call redeem as non-strategy
        vm.prank(user1);
        bytes memory encodedError = abi.encodeWithSignature("NotStrategyAdmin()");
        vm.expectRevert(encodedError);
        vault.redeem(100e18, user1, user1);
    }
    
    function test_Redeem_ThreeParam_Success() public {
        // Test the 3-parameter redeem function
        // Setup: User deposits and gets shares
        vm.startPrank(user1);
        wbtc.approve(address(vault), 1e8);
        vault.depositCollateral(address(wbtc), 1e8, user1);
        uint256 shares = vault.balanceOf(user1);
        
        // Approve strategy to spend shares
        vault.approve(address(strategy), shares);
        vm.stopPrank();
        
        // Transfer SovaBTC directly to strategy
        vm.prank(manager);
        sovaBTC.transfer(address(strategy), 1e8);
        
        // Strategy calls the 3-parameter redeem (without minAssets)
        vm.prank(address(strategy));
        uint256 assets = vault.redeem(shares, user1, user1);
        
        // Verify results
        assertEq(assets, 1e8);
        assertEq(vault.balanceOf(user1), 0);
        assertEq(sovaBTC.balanceOf(user1), 1e8);
    }
    
    function test_Redeem_ThreeParam_ExceedsMax() public {
        // Test the 3-parameter redeem when shares exceed maxRedeem
        // Setup: User deposits and gets shares
        vm.startPrank(user1);
        wbtc.approve(address(vault), 1e8);
        vault.depositCollateral(address(wbtc), 1e8, user1);
        uint256 shares = vault.balanceOf(user1);
        
        // Don't approve strategy - this will make maxRedeem return 0
        vm.stopPrank();
        
        // Try to redeem without approval
        vm.prank(address(strategy));
        vm.expectRevert();
        vault.redeem(shares, user1, user1);
    }
    
    function test_Redeem_WithMinAssets() public {
        // Setup: User deposits and gets shares
        vm.startPrank(user1);
        wbtc.approve(address(vault), 1e8);
        vault.depositCollateral(address(wbtc), 1e8, user1);
        uint256 shares = vault.balanceOf(user1);
        
        // Approve strategy to spend shares
        vault.approve(address(strategy), shares);
        vm.stopPrank();
        
        // In the proper workflow (like non-multi-collateral):
        // 1. User deposited 1e8 WBTC 
        // 2. Strategy already holds the collateral
        // 3. For redemption, transfer SovaBTC directly to strategy without depositRedemptionFunds
        
        // Transfer SovaBTC directly to strategy (simulating off-chain conversion)
        vm.prank(manager);
        sovaBTC.transfer(address(strategy), 1e8);
        
        // Now the strategy has both WBTC and SovaBTC, but only WBTC is tracked as collateral
        vm.prank(address(strategy));
        uint256 assets = vault.redeem(shares, user1, user1, 0);
        
        // User gets their proportional share
        assertEq(assets, 1e8);
        assertEq(vault.balanceOf(user1), 0);
        assertEq(sovaBTC.balanceOf(user1), 1e8);
    }
    
    function test_Redeem_InsufficientOutputAssets() public {
        // Setup: User deposits and gets shares
        vm.startPrank(user1);
        wbtc.approve(address(vault), 1e8);
        vault.depositCollateral(address(wbtc), 1e8, user1);
        uint256 shares = vault.balanceOf(user1);
        
        // Approve strategy to spend shares
        vault.approve(address(strategy), shares);
        vm.stopPrank();
        
        // Manager deposits enough SovaBTC
        vm.startPrank(manager);
        sovaBTC.approve(address(strategy), 2e8);
        strategy.depositRedemptionFunds(2e8);
        vm.stopPrank();
        
        // Strategy tries to redeem with high minAssets - should fail
        vm.prank(address(strategy));
        vm.expectRevert(ManagedWithdrawRWA.InsufficientOutputAssets.selector);
        vault.redeem(shares, user1, user1, 3e8); // Expecting 3 BTC but shares worth ~1.66 BTC
    }
    
    function test_BatchRedeemShares_InvalidArrayLengths() public {
        uint256[] memory shares = new uint256[](2);
        address[] memory to = new address[](1); // Wrong length
        address[] memory owner = new address[](2);
        uint256[] memory minAssets = new uint256[](2);
        
        vm.prank(address(strategy));
        vm.expectRevert(ManagedWithdrawRWA.InvalidArrayLengths.selector);
        vault.batchRedeemShares(shares, to, owner, minAssets);
    }
    
    function test_BatchRedeemShares_RedeemMoreThanMax() public {
        // Setup: User deposits
        vm.startPrank(user1);
        wbtc.approve(address(vault), 1e8);
        vault.depositCollateral(address(wbtc), 1e8, user1);
        uint256 userShares = vault.balanceOf(user1);
        vm.stopPrank();
        
        // Try to redeem more than user has
        uint256[] memory shares = new uint256[](1);
        shares[0] = userShares + 1;
        address[] memory to = new address[](1);
        to[0] = user1;
        address[] memory owner = new address[](1);
        owner[0] = user1;
        uint256[] memory minAssets = new uint256[](1);
        
        vm.prank(address(strategy));
        vm.expectRevert();
        vault.batchRedeemShares(shares, to, owner, minAssets);
    }
    
    function test_BatchRedeemShares_Success() public {
        // Setup: User deposits
        vm.startPrank(user1);
        wbtc.approve(address(vault), 1e8);
        vault.depositCollateral(address(wbtc), 1e8, user1);
        uint256 userShares = vault.balanceOf(user1);
        vault.approve(address(strategy), userShares);
        vm.stopPrank();
        
        // Transfer SovaBTC directly to strategy (simulating off-chain conversion)
        vm.prank(manager);
        sovaBTC.transfer(address(strategy), 1e8);
        
        // Prepare batch
        uint256[] memory shares = new uint256[](1);
        shares[0] = userShares;
        address[] memory to = new address[](1);
        to[0] = user1;
        address[] memory owner = new address[](1);
        owner[0] = user1;
        uint256[] memory minAssets = new uint256[](1);
        
        // Execute batch redemption
        vm.prank(address(strategy));
        uint256[] memory assets = vault.batchRedeemShares(shares, to, owner, minAssets);
        
        // User gets correct value
        assertEq(assets[0], 1e8);
        assertEq(vault.balanceOf(user1), 0);
        assertEq(sovaBTC.balanceOf(user1), 1e8);
    }
    
    /*//////////////////////////////////////////////////////////////
                MANAGEDWITHDRAWMULTICOLLATERALSTRATEGY TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Strategy_Constructor() public {
        // Deploy a new strategy to test constructor
        ManagedWithdrawMultiCollateralStrategy newStrategy = new ManagedWithdrawMultiCollateralStrategy();
        
        // Should be uninitialized
        assertEq(newStrategy.sToken(), address(0));
        assertEq(newStrategy.manager(), address(0));
    }
    
    function test_Strategy_Initialize() public {
        // Deploy fresh strategy
        ManagedWithdrawMultiCollateralStrategy newStrategy = new ManagedWithdrawMultiCollateralStrategy();
        
        // Initialize with init data containing registry and sovaBTC
        bytes memory initData = abi.encode(address(registry), address(sovaBTC));
        newStrategy.initialize(
            "Test Token",
            "TEST",
            address(roleManager),
            manager,
            address(sovaBTC),
            8,
            initData
        );
        
        assertEq(newStrategy.sovaBTC(), address(sovaBTC));
        assertEq(newStrategy.manager(), manager);
        assertEq(newStrategy.collateralRegistry(), address(registry));
    }
    
    // Note: Cannot test empty initData path because ReportedStrategy requires a reporter
    // The uncovered lines are:
    // 1. Line 109: sovaBTC = asset_ (when initData.length == 0)
    // 2. Line 142: sovaBTC != address(0) ? sovaBTC : asset_ (when sovaBTC is address(0))
    // These paths are not reachable in practice because ReportedStrategy will revert first
    
    function test_Strategy_Initialize_DifferentAssetAndSovaBTC() public {
        // Test initialization where asset is different from sovaBTC
        ManagedWithdrawMultiCollateralStrategy newStrategy = new ManagedWithdrawMultiCollateralStrategy();
        
        // Initialize with different asset and sovaBTC
        bytes memory initData = abi.encode(address(registry), address(sovaBTC));
        newStrategy.initialize(
            "Test Token",
            "TEST",
            address(roleManager),
            manager,
            address(wbtc), // Different asset than sovaBTC
            8,
            initData
        );
        
        // Verify both are set correctly
        assertEq(newStrategy.sovaBTC(), address(sovaBTC));
        assertEq(newStrategy.asset(), address(wbtc));
        assertNotEq(newStrategy.asset(), newStrategy.sovaBTC());
    }
    
    
    function test_Strategy_SetCollateralRegistry() public {
        // Deploy new registry
        MultiCollateralRegistry newRegistry = new MultiCollateralRegistry(address(roleManager), address(sovaBTC));
        
        // Only manager can set registry
        vm.expectRevert(abi.encodeWithSelector(IStrategy.Unauthorized.selector));
        strategy.setCollateralRegistry(address(newRegistry));
        
        // Manager sets registry
        vm.prank(manager);
        strategy.setCollateralRegistry(address(newRegistry));
        assertEq(strategy.collateralRegistry(), address(newRegistry));
    }
    
    function test_Strategy_DepositCollateral_NotVault() public {
        vm.expectRevert(ManagedWithdrawMultiCollateralStrategy.OnlyVault.selector);
        strategy.depositCollateral(address(wbtc), 1e8);
    }
    
    function test_Strategy_DepositCollateral_ZeroAmount() public {
        vm.prank(address(vault));
        vm.expectRevert(ManagedWithdrawMultiCollateralStrategy.ZeroAmount.selector);
        strategy.depositCollateral(address(wbtc), 0);
    }
    
    function test_Strategy_DepositCollateral_NotAllowed() public {
        MockERC20 randomToken = new MockERC20("Random", "RND", 18);
        
        vm.prank(address(vault));
        vm.expectRevert(ManagedWithdrawMultiCollateralStrategy.NotAllowed.selector);
        strategy.depositCollateral(address(randomToken), 1e18);
    }
    
    function test_Strategy_DepositRedemptionFunds_NotManager() public {
        vm.expectRevert(abi.encodeWithSelector(IStrategy.Unauthorized.selector));
        strategy.depositRedemptionFunds(10e8);
    }
    
    function test_Strategy_Balance() public {
        // Initially zero
        assertEq(strategy.balance(), 0);
        
        // After collateral deposit
        vm.startPrank(user1);
        wbtc.approve(address(vault), 1e8);
        vault.depositCollateral(address(wbtc), 1e8, user1);
        vm.stopPrank();
        
        // Balance should reflect collateral value
        assertEq(strategy.balance(), 1e8);
    }
    
    function test_Strategy_Redeem_ExpiredRequest() public {
        ManagedWithdrawMultiCollateralStrategy.WithdrawalRequest memory request = 
            ManagedWithdrawMultiCollateralStrategy.WithdrawalRequest({
                shares: 1e18,
                minAssets: 0,
                owner: user1,
                nonce: 1,
                to: user1,
                expirationTime: uint96(block.timestamp - 1) // Already expired
            });
            
        ManagedWithdrawMultiCollateralStrategy.Signature memory sig;
        
        vm.prank(manager);
        vm.expectRevert(ManagedWithdrawMultiCollateralStrategy.WithdrawalRequestExpired.selector);
        strategy.redeem(request, sig);
    }
    
    function test_Strategy_Redeem_InvalidSignature() public {
        ManagedWithdrawMultiCollateralStrategy.WithdrawalRequest memory request = 
            ManagedWithdrawMultiCollateralStrategy.WithdrawalRequest({
                shares: 1e18,
                minAssets: 0,
                owner: user1,
                nonce: 1,
                to: user1,
                expirationTime: uint96(block.timestamp + 1 hours)
            });
            
        // Sign with wrong key
        ManagedWithdrawMultiCollateralStrategy.Signature memory sig = _signWithdrawalRequest(request, user2PrivateKey);
        
        vm.prank(manager);
        vm.expectRevert(ManagedWithdrawMultiCollateralStrategy.WithdrawInvalidSignature.selector);
        strategy.redeem(request, sig);
    }
    
    function test_Strategy_BatchRedeem_ArrayLengthMismatch() public {
        ManagedWithdrawMultiCollateralStrategy.WithdrawalRequest[] memory requests = 
            new ManagedWithdrawMultiCollateralStrategy.WithdrawalRequest[](2);
        ManagedWithdrawMultiCollateralStrategy.Signature[] memory signatures = 
            new ManagedWithdrawMultiCollateralStrategy.Signature[](1); // Wrong length
            
        vm.prank(manager);
        vm.expectRevert(ManagedWithdrawMultiCollateralStrategy.InvalidArrayLengths.selector);
        strategy.batchRedeem(requests, signatures);
    }
    
    function test_Strategy_UsedNonces() public {
        // Setup: User deposits
        vm.startPrank(user1);
        wbtc.approve(address(vault), 1e8);
        vault.depositCollateral(address(wbtc), 1e8, user1);
        uint256 shares = vault.balanceOf(user1);
        vault.approve(address(strategy), shares);
        vm.stopPrank();
        
        // Transfer SovaBTC directly to strategy
        vm.prank(manager);
        sovaBTC.transfer(address(strategy), 1e8);
        
        // Create withdrawal request
        ManagedWithdrawMultiCollateralStrategy.WithdrawalRequest memory request = 
            ManagedWithdrawMultiCollateralStrategy.WithdrawalRequest({
                shares: shares,
                minAssets: 0,
                owner: user1,
                nonce: 1,
                to: user1,
                expirationTime: uint96(block.timestamp + 1 hours)
            });
            
        ManagedWithdrawMultiCollateralStrategy.Signature memory sig = _signWithdrawalRequest(request, user1PrivateKey);
        
        // Check nonce is not used
        assertFalse(strategy.usedNonces(user1, 1));
        
        // Process redemption
        vm.prank(manager);
        strategy.redeem(request, sig);
        
        // Check nonce is now used
        assertTrue(strategy.usedNonces(user1, 1));
    }
    
    function test_Strategy_CollateralBalances() public {
        // Initially zero
        assertEq(strategy.collateralBalances(address(wbtc)), 0);
        
        // After deposit
        vm.startPrank(user1);
        wbtc.approve(address(vault), 1e8);
        vault.depositCollateral(address(wbtc), 1e8, user1);
        vm.stopPrank();
        
        // Check balance updated
        assertEq(strategy.collateralBalances(address(wbtc)), 1e8);
    }
    
    function test_Strategy_HeldCollateralTokens() public {
        // After deposits
        vm.startPrank(user1);
        wbtc.approve(address(vault), 1e8);
        vault.depositCollateral(address(wbtc), 1e8, user1);
        
        tbtc.approve(address(vault), 1e18);
        vault.depositCollateral(address(tbtc), 1e18, user1);
        vm.stopPrank();
        
        // Check tokens tracked
        assertEq(strategy.heldCollateralTokens(0), address(wbtc));
        assertEq(strategy.heldCollateralTokens(1), address(tbtc));
    }
    
    function test_Strategy_IsHeldCollateral() public {
        // Initially false
        assertFalse(strategy.isHeldCollateral(address(wbtc)));
        
        // After deposit
        vm.startPrank(user1);
        wbtc.approve(address(vault), 1e8);
        vault.depositCollateral(address(wbtc), 1e8, user1);
        vm.stopPrank();
        
        // Now true
        assertTrue(strategy.isHeldCollateral(address(wbtc)));
    }
    
    function test_Strategy_GettersAndPublicVars() public {
        // Test all public getters
        assertEq(strategy.collateralRegistry(), address(registry));
        assertEq(strategy.sovaBTC(), address(sovaBTC));
        assertEq(strategy.asset(), address(sovaBTC));
        assertEq(strategy.assetDecimals(), 8);
        assertEq(strategy.manager(), manager);
        assertEq(strategy.sToken(), address(vault));
    }
    
    /*//////////////////////////////////////////////////////////////
                    HOOK INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_DepositCollateral_Multiple() public {
        // User1 deposits WBTC
        vm.startPrank(user1);
        wbtc.approve(address(vault), 1e8);
        uint256 wbtcShares = vault.depositCollateral(address(wbtc), 1e8, user1);
        vm.stopPrank();
        
        assertGt(wbtcShares, 0);
        assertEq(vault.balanceOf(user1), wbtcShares);
        assertEq(wbtc.balanceOf(address(strategy)), 1e8);
        
        // User1 deposits tBTC
        vm.startPrank(user1);
        tbtc.approve(address(vault), 1e18);
        uint256 tbtcShares = vault.depositCollateral(address(tbtc), 1e18, user1);
        vm.stopPrank();
        
        assertGt(tbtcShares, 0);
        assertEq(vault.balanceOf(user1), wbtcShares + tbtcShares);
        assertEq(tbtc.balanceOf(address(strategy)), 1e18);
        
        // Check strategy tracking
        assertEq(strategy.collateralBalances(address(wbtc)), 1e8);
        assertEq(strategy.collateralBalances(address(tbtc)), 1e18);
    }
    
    function test_DepositCollateral_NotAllowed() public {
        MockERC20 randomToken = new MockERC20("Random", "RND", 18);
        randomToken.mint(user1, 100e18);
        
        vm.startPrank(user1);
        randomToken.approve(address(vault), 100e18);
        
        vm.expectRevert(MultiCollateralRegistry.CollateralNotAllowed.selector);
        vault.depositCollateral(address(randomToken), 100e18, user1);
        vm.stopPrank();
    }
    
    function test_ConvertToShares_ConvertToAssets() public {
        // Initial deposit
        vm.startPrank(user1);
        wbtc.approve(address(vault), 1e8);
        vault.depositCollateral(address(wbtc), 1e8, user1);
        vm.stopPrank();
        
        // Test conversion functions
        uint256 shares = vault.convertToShares(1e8);
        assertEq(shares, 1e18); // 1:1 at first deposit
        
        uint256 assets = vault.convertToAssets(1e18);
        assertEq(assets, 1e8); // 1:1 conversion
    }
    
    /*//////////////////////////////////////////////////////////////
                    ERC4626 VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function test_Vault_ViewFunctions() public {
        // Test all view functions
        assertEq(vault.name(), "SovaBTC Yield Token");
        assertEq(vault.symbol(), "vBTC");
        assertEq(vault.decimals(), 18);
        assertEq(vault.asset(), address(sovaBTC));
        assertEq(vault.underlyingAsset(), address(sovaBTC));
        assertEq(vault.totalAssets(), 0);
        
        // After deposit
        vm.startPrank(user1);
        wbtc.approve(address(vault), 1e8);
        vault.depositCollateral(address(wbtc), 1e8, user1);
        vm.stopPrank();
        
        assertEq(vault.totalAssets(), 1e8);
        assertEq(vault.totalSupply(), 1e18);
    }
    
    function test_Vault_PreviewFunctions() public {
        // Setup some deposits first
        vm.startPrank(user1);
        wbtc.approve(address(vault), 1e8);
        vault.depositCollateral(address(wbtc), 1e8, user1);
        vm.stopPrank();
        
        // Test preview functions
        assertEq(vault.previewDeposit(1e8), 1e18);
        assertEq(vault.previewMint(1e18), 1e8);
        assertEq(vault.previewWithdraw(1e8), 1e18);
        assertEq(vault.previewRedeem(1e18), 1e8);
    }
    
    function test_Vault_MaxFunctions() public {
        assertEq(vault.maxDeposit(user1), type(uint256).max);
        assertEq(vault.maxMint(user1), type(uint256).max);
        assertEq(vault.maxWithdraw(user1), 0);
        assertEq(vault.maxRedeem(user1), 0);
        
        // After deposit
        vm.startPrank(user1);
        wbtc.approve(address(vault), 1e8);
        vault.depositCollateral(address(wbtc), 1e8, user1);
        vm.stopPrank();
        
        assertEq(vault.maxWithdraw(user1), 1e8);
        assertEq(vault.maxRedeem(user1), 1e18);
    }
    
    function test_ProperRedemptionWorkflow() public {
        // This test demonstrates the proper workflow like non-multi-collateral
        
        // Step 1: User deposits collateral
        vm.startPrank(user1);
        wbtc.approve(address(vault), 1e8);
        vault.depositCollateral(address(wbtc), 1e8, user1);
        uint256 shares = vault.balanceOf(user1);
        vault.approve(address(strategy), shares);
        vm.stopPrank();
        
        // Step 2: Record initial state
        uint256 initialTotalAssets = vault.totalAssets();
        assertEq(initialTotalAssets, 1e8);
        
        // Step 3: Manager converts collateral offline and transfers SovaBTC directly
        // This simulates the manager taking WBTC, converting it to BTC, then to SovaBTC
        // without using depositRedemptionFunds which causes inflation
        
        // Transfer exact amount needed for redemption
        vm.prank(manager);
        sovaBTC.transfer(address(strategy), 1e8);
        
        // Total assets should still be 1e8 (only tracking collateral, not redemption funds)
        assertEq(vault.totalAssets(), 1e8);
        
        // Create withdrawal request
        ManagedWithdrawMultiCollateralStrategy.WithdrawalRequest memory request = 
            ManagedWithdrawMultiCollateralStrategy.WithdrawalRequest({
                shares: shares,
                minAssets: 0,
                owner: user1,
                nonce: 1,
                to: user1,
                expirationTime: uint96(block.timestamp + 1 hours)
            });
            
        ManagedWithdrawMultiCollateralStrategy.Signature memory sig = _signWithdrawalRequest(request, user1PrivateKey);
        
        // Process redemption
        vm.prank(manager);
        uint256 assets = strategy.redeem(request, sig);
        
        // User receives correct amount
        assertEq(assets, 1e8);
        assertEq(sovaBTC.balanceOf(user1), 1e8);
    }
    
    
    
    
    // Test deposit() and mint() reverting with proper setup
    function test_Deposit_Reverts() public {
        // For multi-collateral vault, regular deposit should revert when trying to use conduit
        // Setup a mock registry that implements conduit to test the revert path
        
        // Create a regular Registry with conduit
        Registry regularRegistry = new Registry(address(roleManager));
        
        // Mock the roleManager to return this registry
        vm.mockCall(
            address(roleManager), 
            abi.encodeWithSelector(roleManager.registry.selector), 
            abi.encode(address(regularRegistry))
        );
        
        vm.startPrank(user1);
        sovaBTC.approve(address(vault), 1e8);
        
        // This should revert because conduit will reject the deposit
        vm.expectRevert();
        vault.deposit(1e8, user1);
        vm.stopPrank();
        
        // Clear the mock
        vm.clearMockedCalls();
    }
    
    function test_Mint_Reverts() public {
        // Similar test for mint()
        Registry regularRegistry = new Registry(address(roleManager));
        
        vm.mockCall(
            address(roleManager), 
            abi.encodeWithSelector(roleManager.registry.selector), 
            abi.encode(address(regularRegistry))
        );
        
        vm.startPrank(user1);
        sovaBTC.approve(address(vault), 1e8);
        
        // This should revert because conduit will reject the mint
        vm.expectRevert();
        vault.mint(1e18, user1);
        vm.stopPrank();
        
        // Clear the mock
        vm.clearMockedCalls();
    }
    
    function test_BatchRedeemShares_WithHooks() public {
        // Setup: User deposits
        vm.startPrank(user1);
        wbtc.approve(address(vault), 2e8);
        vault.depositCollateral(address(wbtc), 2e8, user1);
        uint256 userShares = vault.balanceOf(user1);
        vault.approve(address(strategy), userShares);
        vm.stopPrank();
        
        // Add a hook
        vm.prank(address(strategy));
        vault.addOperationHook(OP_WITHDRAW, address(hook));
        
        // Transfer SovaBTC directly to strategy
        vm.prank(manager);
        sovaBTC.transfer(address(strategy), 2e8);
        
        // Prepare batch
        uint256[] memory shares = new uint256[](2);
        shares[0] = userShares / 2;
        shares[1] = userShares / 2;
        address[] memory to = new address[](2);
        to[0] = user1;
        to[1] = user1;
        address[] memory owner = new address[](2);
        owner[0] = user1;
        owner[1] = user1;
        uint256[] memory minAssets = new uint256[](2);
        
        // Execute batch redemption with hooks
        vm.prank(address(strategy));
        uint256[] memory assets = vault.batchRedeemShares(shares, to, owner, minAssets);
        
        assertEq(assets.length, 2);
        assertGt(assets[0], 0);
        assertGt(assets[1], 0);
        assertEq(vault.balanceOf(user1), 0);
    }
    
    function test_BatchRedeemShares_InsufficientOutputAssetsInBatch() public {
        // Setup: User deposits
        vm.startPrank(user1);
        wbtc.approve(address(vault), 2e8);
        vault.depositCollateral(address(wbtc), 2e8, user1);
        uint256 userShares = vault.balanceOf(user1);
        vault.approve(address(strategy), userShares);
        vm.stopPrank();
        
        // Transfer SovaBTC directly to strategy (less than needed)
        vm.prank(manager);
        sovaBTC.transfer(address(strategy), 1e8); // Only 1 BTC but user has 2 BTC worth
        
        // Prepare batch with high minAssets requirement
        uint256[] memory shares = new uint256[](1);
        shares[0] = userShares;
        address[] memory to = new address[](1);
        to[0] = user1;
        address[] memory owner = new address[](1);
        owner[0] = user1;
        uint256[] memory minAssets = new uint256[](1);
        minAssets[0] = 3e8; // Require 3 BTC but only 2 BTC worth of shares
        
        // Should fail due to insufficient assets
        vm.prank(address(strategy));
        vm.expectRevert(ManagedWithdrawRWA.InsufficientOutputAssets.selector);
        vault.batchRedeemShares(shares, to, owner, minAssets);
    }
    
    function test_Strategy_Redeem_NonceReuse() public {
        // Setup: User deposits
        vm.startPrank(user1);
        wbtc.approve(address(vault), 1e8);
        vault.depositCollateral(address(wbtc), 1e8, user1);
        uint256 shares = vault.balanceOf(user1);
        vault.approve(address(strategy), shares);
        vm.stopPrank();
        
        // Transfer SovaBTC directly to strategy
        vm.prank(manager);
        sovaBTC.transfer(address(strategy), 1e8);
        
        // Create withdrawal request
        ManagedWithdrawMultiCollateralStrategy.WithdrawalRequest memory request = 
            ManagedWithdrawMultiCollateralStrategy.WithdrawalRequest({
                shares: shares,
                minAssets: 0,
                owner: user1,
                nonce: 1,
                to: user1,
                expirationTime: uint96(block.timestamp + 1 hours)
            });
            
        ManagedWithdrawMultiCollateralStrategy.Signature memory sig = _signWithdrawalRequest(request, user1PrivateKey);
        
        // Process redemption first time
        vm.prank(manager);
        strategy.redeem(request, sig);
        
        // Try to reuse the same nonce
        vm.prank(manager);
        vm.expectRevert(ManagedWithdrawMultiCollateralStrategy.WithdrawNonceReuse.selector);
        strategy.redeem(request, sig);
    }
    
    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    
    function _signWithdrawalRequest(
        ManagedWithdrawMultiCollateralStrategy.WithdrawalRequest memory request,
        uint256 privateKey
    ) internal view returns (ManagedWithdrawMultiCollateralStrategy.Signature memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                WITHDRAWAL_REQUEST_TYPEHASH,
                request.owner,
                request.to,
                request.shares,
                request.minAssets,
                request.nonce,
                request.expirationTime
            )
        );
        
        bytes32 domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256("MWMCS"), // Updated to match optimized contract
                keccak256("1"),
                block.chainid,
                address(strategy)
            )
        );
        
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        
        return ManagedWithdrawMultiCollateralStrategy.Signature({
            v: v,
            r: r,
            s: s
        });
    }
}