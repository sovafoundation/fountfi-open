// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {tRWA} from "../src/token/tRWA-multicollateral.sol";
import {MultiCollateralRegistry} from "../contracts/MultiCollateralRegistry.sol";
import {SimpleMultiCollateralStrategy} from "../contracts/SimpleMultiCollateralStrategy.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {Registry} from "../src/registry/Registry.sol";
import {IRegistry} from "../src/registry/IRegistry.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {IHook} from "../src/hooks/IHook.sol";
import {ItRWA} from "../src/token/ItRWA.sol";
import {IStrategy} from "../src/strategy/IStrategy.sol";
import {RoleManaged} from "../src/auth/RoleManaged.sol";

// Mock conduit for testing
contract MockConduit {
    function collectDeposit(address token, address from, address to, uint256 amount) external returns (bool) {
        // Transfer tokens from 'from' to 'to'
        // The user needs to approve the conduit first
        require(MockERC20(token).allowance(from, address(this)) >= amount, "Insufficient allowance");
        MockERC20(token).transferFrom(from, to, amount);
        return true;
    }
}

// Mock strategy with registry function
contract MockStrategyWithRegistry is IStrategy {
    address public sToken;
    address public asset;
    address private _registry;
    address public manager;

    constructor(address _asset, address __registry) {
        asset = _asset;
        _registry = __registry;
    }

    function registry() public view returns (address) {
        return _registry;
    }

    function setSToken(address _sToken) external {
        sToken = _sToken;
    }

    function assetDecimals() external pure returns (uint8) {
        return 8;
    }

    function initialize(string memory, string memory, address, address, address, uint8, bytes memory) external {}

    function balance() external pure returns (uint256) {
        return 0;
    }

    function deposit(uint256) external pure returns (bool) {
        return true;
    }

    function redeem(address, uint256) external pure returns (bool) {
        return true;
    }

    function withdraw(address, uint256) external {}
    function rescueERC20(address, address, uint256) external {}

    function name() external pure returns (string memory) {
        return "Mock Strategy";
    }

    function symbol() external pure returns (string memory) {
        return "MOCK";
    }

    function setManager(address) external {}
}

// Simple mock hook for testing
contract SimpleMockHook is IHook {
    string public override name;

    constructor(string memory _name) {
        name = _name;
    }

    function hookId() external view returns (bytes32) {
        return keccak256(abi.encodePacked(name));
    }

    function onBeforeDeposit(address token, address user, uint256 assets, address receiver)
        external
        pure
        returns (HookOutput memory)
    {
        return HookOutput({approved: true, reason: ""});
    }

    function onBeforeWithdraw(address token, address by, uint256 assets, address to, address owner)
        external
        pure
        returns (HookOutput memory)
    {
        return HookOutput({approved: true, reason: ""});
    }

    function onBeforeTransfer(address token, address from, address to, uint256 amount)
        external
        pure
        returns (HookOutput memory)
    {
        return HookOutput({approved: true, reason: ""});
    }
}

// Mock hook that rejects withdrawals
contract RejectingHook is IHook {
    string public override name = "RejectingHook";

    function hookId() external view returns (bytes32) {
        return keccak256(abi.encodePacked(name));
    }

    function onBeforeDeposit(address, address, uint256, address) external pure returns (HookOutput memory) {
        return HookOutput({approved: false, reason: "Deposit rejected"});
    }

    function onBeforeWithdraw(address, address, uint256, address, address) external pure returns (HookOutput memory) {
        return HookOutput({approved: false, reason: "Withdrawal rejected"});
    }

    function onBeforeTransfer(address, address, address, uint256) external pure returns (HookOutput memory) {
        return HookOutput({approved: true, reason: ""});
    }
}

contract tRWAMultiCollateralFullCoverageTest is Test {
    tRWA public vault;
    MultiCollateralRegistry public registry;
    SimpleMultiCollateralStrategy public strategy;
    RoleManager public roleManager;

    address public admin = address(0x1);
    address public manager = address(0x2);
    address public user = address(0x4);

    MockERC20 public sovaBTC;
    MockERC20 public wbtc;
    MockERC20 public tbtc;

    function setUp() public {
        // Deploy role manager
        roleManager = new RoleManager();
        roleManager.grantRole(admin, roleManager.PROTOCOL_ADMIN());
        roleManager.grantRole(manager, roleManager.STRATEGY_ADMIN());

        // Deploy tokens with specific decimals
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
    }

    // Test constructor validations
    function testConstructorValidDecimals() public {
        // Test with matching decimals
        MockERC20 token8 = new MockERC20("Token8", "T8", 8);

        tRWA testVault = new tRWA(
            "Test Vault",
            "TEST",
            address(token8), // 8 decimals
            8, // matching 8 decimals
            address(strategy),
            address(token8)
        );

        assertEq(testVault.asset(), address(token8));
        assertEq(testVault.underlyingAsset(), address(token8));
    }

    // Test depositCollateral with exact share calculations
    function testDepositCollateralShareCalculations() public {
        vm.startPrank(user);

        // First deposit - should get 1:1 shares (scaled to 18 decimals)
        wbtc.approve(address(vault), 1e8);
        uint256 shares1 = vault.depositCollateral(address(wbtc), 1e8, user);
        assertEq(shares1, 1e18); // 1e8 worth -> 1e18 shares

        // Second deposit of same amount should get same shares (no value change)
        wbtc.approve(address(vault), 1e8);
        uint256 shares2 = vault.depositCollateral(address(wbtc), 1e8, user);
        assertEq(shares2, 1e18); // Still 1:1 ratio

        // Total shares should be 2e18
        assertEq(vault.balanceOf(user), 2e18);
        vm.stopPrank();
    }

    // Test depositCollateral with all hooks paths
    function testDepositCollateralHookPaths() public {
        // Test deposit when no hooks are registered (optimized path)
        vm.startPrank(user);
        wbtc.approve(address(vault), 1e8);
        uint256 shares = vault.depositCollateral(address(wbtc), 1e8, user);
        assertGt(shares, 0);
        vm.stopPrank();

        // Hooks would need to be tested if the vault had hook management enabled
    }

    // Test maxDeposit with strategy balance
    function testMaxDepositWithStrategyBalance() public {
        // Add funds to strategy
        vm.startPrank(manager);
        sovaBTC.approve(address(strategy), 50e8);
        strategy.depositRedemptionFunds(50e8);
        vm.stopPrank();

        // maxDeposit should still be max uint256
        assertEq(vault.maxDeposit(user), type(uint256).max);
    }

    // Test maxMint with strategy balance
    function testMaxMintWithStrategyBalance() public {
        // Add funds to strategy
        vm.startPrank(manager);
        sovaBTC.approve(address(strategy), 50e8);
        strategy.depositRedemptionFunds(50e8);
        vm.stopPrank();

        // maxMint should still be max uint256
        assertEq(vault.maxMint(user), type(uint256).max);
    }

    // Test previewDeposit with collateral
    function testPreviewDepositCollateral() public {
        // Preview for WBTC (8 decimals, 1:1 rate)
        uint256 preview = vault.previewDeposit(1e8);
        assertEq(preview, 1e18); // Should get 1e18 shares for 1e8 assets

        // Add some value to change share price
        vm.startPrank(manager);
        sovaBTC.approve(address(strategy), 10e8);
        strategy.depositRedemptionFunds(10e8);
        vm.stopPrank();

        // Deposit some to establish share supply
        vm.startPrank(user);
        wbtc.approve(address(vault), 1e8);
        vault.depositCollateral(address(wbtc), 1e8, user);
        vm.stopPrank();

        // Now preview should be different
        preview = vault.previewDeposit(1e8);
        assertLt(preview, 1e18); // Should get less shares due to increased value
    }

    // Test edge cases in share/asset conversions
    function testShareAssetConversionEdgeCases() public {
        // Test with 0 total supply
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.convertToShares(1e8), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e8);

        // Deposit collateral to create supply
        vm.startPrank(user);
        wbtc.approve(address(vault), 2e8);
        vault.depositCollateral(address(wbtc), 2e8, user);
        vm.stopPrank();

        // Test with supply
        assertEq(vault.totalSupply(), 2e18);
        assertEq(vault.totalAssets(), 2e8);
        assertEq(vault.convertToShares(1e8), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e8);
    }

    // Test deposit/mint/withdraw/redeem with receiver != msg.sender
    function testOperationsWithDifferentReceiver() public {
        address receiver = address(0x999);

        vm.startPrank(user);

        // depositCollateral with different receiver
        wbtc.approve(address(vault), 1e8);
        uint256 shares = vault.depositCollateral(address(wbtc), 1e8, receiver);
        assertEq(vault.balanceOf(receiver), shares);
        assertEq(vault.balanceOf(user), 0);

        // Another depositCollateral with different token
        tbtc.approve(address(vault), 1e18);
        uint256 shares2 = vault.depositCollateral(address(tbtc), 1e18, receiver);
        assertEq(vault.balanceOf(receiver), shares + shares2);

        vm.stopPrank();
    }

    // Test all view functions
    function testAllViewFunctions() public {
        assertEq(vault.name(), "Multi-Collateral Bitcoin Vault");
        assertEq(vault.symbol(), "mcBTC");
        assertEq(vault.decimals(), 18); // Always 18 for shares
        assertEq(vault.asset(), address(sovaBTC));
        assertEq(vault.underlyingAsset(), address(sovaBTC));
        assertEq(vault.strategy(), address(strategy));
        assertEq(vault.sovaBTC(), address(sovaBTC));
        assertEq(vault.totalAssets(), 0);

        // Operation types
        assertEq(vault.OP_DEPOSIT(), keccak256("DEPOSIT_OPERATION"));
        assertEq(vault.OP_WITHDRAW(), keccak256("WITHDRAW_OPERATION"));
        assertEq(vault.OP_TRANSFER(), keccak256("TRANSFER_OPERATION"));

        // Hook related views (no hooks by default)
        assertEq(vault.getHooksForOperation(vault.OP_DEPOSIT()).length, 0);
        assertEq(vault.lastExecutedBlock(vault.OP_DEPOSIT()), 0);
    }

    // Test depositCollateral with 18 decimal token
    function testDepositCollateral18Decimals() public {
        vm.startPrank(user);

        // Deposit tBTC (18 decimals)
        tbtc.approve(address(vault), 1e18);
        uint256 shares = vault.depositCollateral(address(tbtc), 1e18, user);

        // 1e18 tBTC = 1e8 SovaBTC value = 1e18 shares (first deposit)
        assertEq(shares, 1e18);
        assertEq(vault.balanceOf(user), 1e18);

        vm.stopPrank();
    }

    // Test mixed decimal deposits
    function testMixedDecimalDeposits() public {
        vm.startPrank(user);

        // Deposit WBTC (8 decimals)
        wbtc.approve(address(vault), 1e8);
        uint256 shares1 = vault.depositCollateral(address(wbtc), 1e8, user);
        assertEq(shares1, 1e18);

        // Deposit tBTC (18 decimals) - same BTC value
        tbtc.approve(address(vault), 1e18);
        uint256 shares2 = vault.depositCollateral(address(tbtc), 1e18, user);
        assertEq(shares2, 1e18); // Should get same shares for same BTC value

        // Total shares should be 2e18
        assertEq(vault.balanceOf(user), 2e18);

        vm.stopPrank();
    }

    // Test constructor validation
    function testConstructorValidation() public {
        // Test zero asset
        vm.expectRevert(ItRWA.InvalidAddress.selector);
        new tRWA("Test", "TEST", address(0), 8, address(strategy), address(sovaBTC));

        // Test zero strategy
        vm.expectRevert(ItRWA.InvalidAddress.selector);
        new tRWA("Test", "TEST", address(sovaBTC), 8, address(0), address(sovaBTC));

        // Test zero sovaBTC
        vm.expectRevert(ItRWA.InvalidAddress.selector);
        new tRWA("Test", "TEST", address(sovaBTC), 8, address(strategy), address(0));

        // Test invalid decimals
        vm.expectRevert();
        new tRWA("Test", "TEST", address(sovaBTC), 25, address(strategy), address(sovaBTC));
    }

    // Test deposit with hooks for _deposit coverage
    function testDepositWithHooks() public {
        // Create a mock conduit that will work with our deposit
        address mockConduit = address(new MockConduit());

        // Create a mock registry that returns our mock conduit
        vm.mockCall(address(roleManager), abi.encodeWithSignature("registry()"), abi.encode(address(registry)));

        vm.mockCall(address(registry), abi.encodeWithSignature("conduit()"), abi.encode(mockConduit));

        // Mock the strategy's registry() to return our registry
        vm.mockCall(address(strategy), abi.encodeWithSignature("registry()"), abi.encode(address(registry)));

        // Add deposit hooks to test the hook path in _deposit
        SimpleMockHook hook1 = new SimpleMockHook("DepositHook1");
        SimpleMockHook hook2 = new SimpleMockHook("DepositHook2");

        vm.startPrank(address(strategy));
        vault.addOperationHook(vault.OP_DEPOSIT(), address(hook1));
        vault.addOperationHook(vault.OP_DEPOSIT(), address(hook2));
        vm.stopPrank();

        // Now call deposit which will trigger _deposit with hooks
        vm.startPrank(user);
        sovaBTC.approve(address(vault), 1e8);
        sovaBTC.approve(mockConduit, 1e8);

        // This will call _deposit internally
        uint256 shares = vault.deposit(1e8, user);
        vm.stopPrank();

        assertGt(shares, 0);
        assertEq(vault.balanceOf(user), shares);
        assertEq(vault.lastExecutedBlock(vault.OP_DEPOSIT()), block.number);
    }

    // Test deposit with rejecting hook for _deposit coverage
    function testDepositWithRejectingHook() public {
        // Create mocks
        address mockConduit = address(new MockConduit());

        vm.mockCall(address(roleManager), abi.encodeWithSignature("registry()"), abi.encode(address(registry)));

        vm.mockCall(address(registry), abi.encodeWithSignature("conduit()"), abi.encode(mockConduit));

        vm.mockCall(address(strategy), abi.encodeWithSignature("registry()"), abi.encode(address(registry)));

        // Add a rejecting hook
        RejectingHook rejectHook = new RejectingHook();

        vm.startPrank(address(strategy));
        vault.addOperationHook(vault.OP_DEPOSIT(), address(rejectHook));
        vm.stopPrank();

        // Try to deposit - should fail due to hook rejection
        vm.startPrank(user);
        sovaBTC.approve(address(vault), 1e8);
        sovaBTC.approve(mockConduit, 1e8);
        vm.expectRevert(abi.encodeWithSelector(tRWA.HookCheckFailed.selector, "Deposit rejected"));
        vault.deposit(1e8, user);
        vm.stopPrank();
    }

    // Test deposit with regular ERC20 token (uses _deposit internally)
    function testDepositWithRegularAsset() public {
        // Create mocks for no-hooks path
        address mockConduit = address(new MockConduit());

        vm.mockCall(address(roleManager), abi.encodeWithSignature("registry()"), abi.encode(address(registry)));

        vm.mockCall(address(registry), abi.encodeWithSignature("conduit()"), abi.encode(mockConduit));

        vm.mockCall(address(strategy), abi.encodeWithSignature("registry()"), abi.encode(address(registry)));

        // Call deposit without any hooks - tests the no-hooks path
        vm.startPrank(user);
        sovaBTC.approve(address(vault), 1e8);
        sovaBTC.approve(mockConduit, 1e8);
        uint256 shares = vault.deposit(1e8, user);
        vm.stopPrank();

        assertGt(shares, 0);
        assertEq(vault.balanceOf(user), shares);
        // No hooks, so lastExecutedBlock should be 0
        assertEq(vault.lastExecutedBlock(vault.OP_DEPOSIT()), 0);
    }

    // Test withdraw edge cases
    function testWithdrawEdgeCases() public {
        // First, add SovaBTC to strategy for withdrawals
        vm.startPrank(manager);
        sovaBTC.approve(address(strategy), 100e8);
        strategy.depositRedemptionFunds(100e8);
        vm.stopPrank();

        // Setup: deposit some collateral first
        vm.startPrank(user);
        wbtc.approve(address(vault), 10e8);
        vault.depositCollateral(address(wbtc), 1e8, user);
        vm.stopPrank();

        // Test: Try to withdraw with receiver != owner when no allowance
        address receiver = address(0x999);

        vm.prank(receiver);
        vm.expectRevert();
        vault.withdraw(0.5e8, receiver, user);

        // Test: Withdraw with proper allowance from owner
        vm.prank(user);
        uint256 shares = vault.withdraw(0.5e8, user, user);
        assertGt(shares, 0);
    }

    // Test onlyStrategy modifier
    function testOnlyStrategyModifier() public {
        // Try to call a function that has onlyStrategy modifier from non-strategy
        bytes32 depositOp = vault.OP_DEPOSIT();
        vm.expectRevert(tRWA.NotStrategyAdmin.selector);
        vault.addOperationHook(depositOp, address(0x123));
    }

    // Test getHookInfoForOperation
    function testGetHookInfoForOperation() public {
        // First test the function without any hooks
        tRWA.HookInfo[] memory emptyHookInfos = vault.getHookInfoForOperation(vault.OP_DEPOSIT());
        assertEq(emptyHookInfos.length, 0);

        // Add a hook (needs to be called from strategy)
        SimpleMockHook hook = new SimpleMockHook("Hook1");

        vm.startPrank(address(strategy));
        vault.addOperationHook(vault.OP_DEPOSIT(), address(hook));
        vm.stopPrank();

        // Get hook info
        tRWA.HookInfo[] memory hookInfos = vault.getHookInfoForOperation(vault.OP_DEPOSIT());

        assertEq(hookInfos.length, 1);
        assertEq(address(hookInfos[0].hook), address(hook));
        assertEq(hookInfos[0].addedAtBlock, block.number);
    }

    // Test withdraw with hooks that reject
    function testWithdrawWithRejectingHook() public {
        // Setup: add funds and deposit
        vm.startPrank(manager);
        sovaBTC.approve(address(strategy), 100e8);
        strategy.depositRedemptionFunds(100e8);
        vm.stopPrank();

        vm.startPrank(user);
        wbtc.approve(address(vault), 1e8);
        vault.depositCollateral(address(wbtc), 1e8, user);
        vm.stopPrank();

        // Add a rejecting hook
        RejectingHook rejectHook = new RejectingHook();
        vm.startPrank(address(strategy));
        bytes32 withdrawOp = vault.OP_WITHDRAW();
        vault.addOperationHook(withdrawOp, address(rejectHook));
        vm.stopPrank();

        // Try to withdraw - should fail due to hook rejection
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(tRWA.HookCheckFailed.selector, "Withdrawal rejected"));
        vault.withdraw(0.5e8, user, user);
    }

    // Test withdraw with multiple hooks
    function testWithdrawWithMultipleHooks() public {
        // Setup: add funds and deposit
        vm.startPrank(manager);
        sovaBTC.approve(address(strategy), 100e8);
        strategy.depositRedemptionFunds(100e8);
        vm.stopPrank();

        vm.startPrank(user);
        wbtc.approve(address(vault), 1e8);
        vault.depositCollateral(address(wbtc), 1e8, user);
        vm.stopPrank();

        // Add multiple approving hooks
        SimpleMockHook hook1 = new SimpleMockHook("Hook1");
        SimpleMockHook hook2 = new SimpleMockHook("Hook2");

        vm.startPrank(address(strategy));
        vault.addOperationHook(vault.OP_WITHDRAW(), address(hook1));
        vault.addOperationHook(vault.OP_WITHDRAW(), address(hook2));
        vm.stopPrank();

        // Withdraw should succeed with hooks approving
        vm.prank(user);
        uint256 shares = vault.withdraw(0.5e8, user, user);
        assertGt(shares, 0);

        // Check that lastExecutedBlock was updated
        assertEq(vault.lastExecutedBlock(vault.OP_WITHDRAW()), block.number);
    }

    // Test all onlyStrategy functions to ensure modifier coverage
    function testOnlyStrategyFunctions() public {
        // removeOperationHook
        bytes32 depositOp = vault.OP_DEPOSIT();
        vm.expectRevert(tRWA.NotStrategyAdmin.selector);
        vault.removeOperationHook(depositOp, 0);

        // reorderOperationHooks
        uint256[] memory indices = new uint256[](0);
        bytes32 depositOp2 = vault.OP_DEPOSIT();
        vm.expectRevert(tRWA.NotStrategyAdmin.selector);
        vault.reorderOperationHooks(depositOp2, indices);
    }
}
