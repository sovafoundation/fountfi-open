// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {Conduit} from "../src/conduit/ConduitMultiCollateral.sol";
import {Conduit as BaseConduit} from "../src/conduit/Conduit.sol";
import {Registry} from "../src/registry/Registry.sol";
import {IRegistry} from "../src/registry/IRegistry.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {IStrategy} from "../src/strategy/IStrategy.sol";
import {ItRWA} from "../src/token/ItRWA.sol";
import {IMultiCollateralStrategy} from "../src/interfaces/IMultiCollateralStrategy.sol";
import {IMultiCollateralRegistry} from "../src/interfaces/IMultiCollateralRegistry.sol";

// Mock contracts for testing
contract MockStrategy is IStrategy, IMultiCollateralStrategy {
    address public override sToken;
    address public immutable override asset;
    address public immutable override collateralRegistry;

    constructor(address _asset, address _registry) {
        asset = _asset;
        collateralRegistry = _registry;
    }

    function setSToken(address _sToken) external {
        sToken = _sToken;
    }

    // IStrategy implementations
    function initialize(string memory, string memory, address, address, address, uint8, bytes memory) external {}

    function balance() external view returns (uint256) {
        return 0;
    }

    function deposit(uint256 amount) external returns (bool) {
        return true;
    }

    function redeem(address to, uint256 amount) external returns (bool) {
        return true;
    }

    function withdraw(address to, uint256 amount) external {}
    function rescueERC20(address tokenAddress, address to, uint256 amount) external {}

    function name() external view returns (string memory) {
        return "Mock Strategy";
    }

    function symbol() external view returns (string memory) {
        return "MOCK";
    }

    function setManager(address newManager) external {}

    // IMultiCollateralStrategy implementations
    function assetDecimals() external pure returns (uint8) {
        return 8;
    }

    function manager() external pure returns (address) {
        return address(0);
    }

    function isHeldCollateral(address) external pure returns (bool) {
        return false;
    }

    function heldCollateralTokens(uint256) external pure returns (address) {
        return address(0);
    }

    function collateralBalances(address) external pure returns (uint256) {
        return 0;
    }

    function totalCollateralValue() external pure returns (uint256) {
        return 0;
    }

    function depositCollateral(address, uint256) external {}
    function withdrawCollateral(address, uint256, address) external {}
    function depositRedemptionFunds(uint256) external {}
}

contract MockTRWA is ItRWA {
    address public immutable override asset;
    address public immutable override strategy;

    constructor(address _asset, address _strategy) {
        asset = _asset;
        strategy = _strategy;
    }

    function redeem(uint256, address, address) external returns (uint256) {
        return 0;
    }

    function withdraw(uint256, address, address) external returns (uint256) {
        return 0;
    }
}

contract MockCollateralRegistry is IMultiCollateralRegistry {
    mapping(address => bool) public allowedCollateral;
    mapping(address => uint256) private _collateralToSovaBTCRate;
    mapping(address => uint8) private _collateralDecimals;
    address[] public collateralTokens;
    address public immutable override sovaBTC;

    constructor(address _sovaBTC) {
        sovaBTC = _sovaBTC;
    }

    function addCollateral(address token, uint256 rate, uint8 decimals) external {
        allowedCollateral[token] = true;
        _collateralToSovaBTCRate[token] = rate;
        _collateralDecimals[token] = decimals;
        collateralTokens.push(token);
    }

    function collateralToSovaBTCRate(address token) external view override returns (uint256) {
        return _collateralToSovaBTCRate[token];
    }

    function collateralDecimals(address token) external view override returns (uint8) {
        return _collateralDecimals[token];
    }

    function isAllowedCollateral(address token) external view override returns (bool) {
        return allowedCollateral[token];
    }

    function removeCollateral(address) external {}
    function updateRate(address, uint256) external {}

    function convertToSovaBTC(address, uint256) external pure returns (uint256) {
        return 0;
    }

    function convertFromSovaBTC(address, uint256) external pure returns (uint256) {
        return 0;
    }

    function getCollateralTokenCount() external view returns (uint256) {
        return collateralTokens.length;
    }

    function getAllCollateralTokens() external view returns (address[] memory) {
        return collateralTokens;
    }
}

contract ConduitMultiCollateralTest is Test {
    Conduit public conduit;
    Registry public registry;
    RoleManager public roleManager;
    MockStrategy public strategy;
    MockTRWA public vault;
    MockCollateralRegistry public collateralRegistry;

    address public admin = address(0x1);
    address public user = address(0x2);

    MockERC20 public sovaBTC;
    MockERC20 public wbtc;
    MockERC20 public tbtc;
    MockERC20 public randomToken;

    function setUp() public {
        // Deploy role manager
        roleManager = new RoleManager();
        roleManager.grantRole(admin, roleManager.PROTOCOL_ADMIN());

        // Deploy registry (which creates regular conduit)
        registry = new Registry(address(roleManager));

        // Deploy our multi-collateral conduit separately for testing
        conduit = new Conduit(address(roleManager));

        // Initialize registry in role manager
        vm.prank(roleManager.owner());
        roleManager.initializeRegistry(address(registry));

        // Deploy tokens
        sovaBTC = new MockERC20("SovaBTC", "SBTC", 8);
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        tbtc = new MockERC20("tBTC", "TBTC", 18);
        randomToken = new MockERC20("Random", "RND", 18);

        // Deploy collateral registry
        collateralRegistry = new MockCollateralRegistry(address(sovaBTC));
        collateralRegistry.addCollateral(address(wbtc), 1e18, 8);
        collateralRegistry.addCollateral(address(tbtc), 1e18, 18);
        collateralRegistry.addCollateral(address(sovaBTC), 1e18, 8);

        // Deploy strategy
        strategy = new MockStrategy(address(sovaBTC), address(collateralRegistry));

        // Deploy vault
        vault = new MockTRWA(address(sovaBTC), address(strategy));
        strategy.setSToken(address(vault));

        // Register strategy in registry so vault is recognized
        // First we need to mark strategy as allowed
        vm.prank(roleManager.owner());
        roleManager.grantRole(address(this), roleManager.STRATEGY_ADMIN());
        registry.setStrategy(address(strategy), true);

        // Mock isStrategyToken to return true for our vault
        // This bypasses all the complex registry checks
        vm.mockCall(
            address(registry), abi.encodeWithSignature("isStrategyToken(address)", address(vault)), abi.encode(true)
        );

        // Mint tokens for testing
        wbtc.mint(user, 10e8);
        tbtc.mint(user, 10e18);
        sovaBTC.mint(user, 10e8);
        randomToken.mint(user, 10e18);
    }

    // Test collectDeposit function
    function testCollectDepositSuccess() public {
        uint256 amount = 1e8;

        // Approve conduit
        vm.prank(user);
        sovaBTC.approve(address(conduit), amount);

        // Call from vault
        vm.prank(address(vault));
        bool success = conduit.collectDeposit(address(sovaBTC), user, address(strategy), amount);

        assertTrue(success);
        assertEq(sovaBTC.balanceOf(address(strategy)), amount);
    }

    function testCollectDepositZeroAmount() public {
        vm.expectRevert(Conduit.InvalidAmount.selector);
        vm.prank(address(vault));
        conduit.collectDeposit(address(sovaBTC), user, address(strategy), 0);
    }

    function testCollectDepositNotFromTRWA() public {
        // When not called from a registered tRWA, the registry check will fail
        vm.prank(user);
        vm.expectRevert();
        conduit.collectDeposit(address(sovaBTC), user, address(strategy), 1e8);
    }

    function testCollectDepositWrongToken() public {
        // Try to deposit WBTC when vault expects SovaBTC
        vm.prank(user);
        wbtc.approve(address(conduit), 1e8);

        vm.expectRevert(Conduit.InvalidToken.selector);
        vm.prank(address(vault));
        conduit.collectDeposit(address(wbtc), user, address(strategy), 1e8);
    }

    function testCollectDepositWrongDestination() public {
        vm.prank(user);
        sovaBTC.approve(address(conduit), 1e8);

        // Try to send to wrong destination
        vm.expectRevert(Conduit.InvalidDestination.selector);
        vm.prank(address(vault));
        conduit.collectDeposit(address(sovaBTC), user, address(0x999), 1e8);
    }

    // Test collectTokens function
    function testCollectTokensSuccess() public {
        uint256 amount = 1e8;

        // Debug: Check if registry is set correctly
        console2.log("Conduit address:", address(conduit));
        console2.log("Registry address:", address(registry));
        console2.log("Conduit.registry():", conduit.registry());

        // Test the mock
        console2.log("isStrategyToken(vault):", registry.isStrategyToken(address(vault)));

        // Approve conduit
        vm.prank(user);
        wbtc.approve(address(conduit), amount);

        // Call from vault
        vm.prank(address(vault));
        bool success = conduit.collectTokens(address(wbtc), user, amount);

        assertTrue(success);
        assertEq(wbtc.balanceOf(address(strategy)), amount);
    }

    function testCollectTokensZeroAmount() public {
        vm.expectRevert(Conduit.InvalidAmount.selector);
        vm.prank(address(vault));
        conduit.collectTokens(address(wbtc), user, 0);
    }

    function testCollectTokensNotFromTRWA() public {
        // When not called from a registered tRWA, the registry check will fail
        vm.prank(user);
        vm.expectRevert();
        conduit.collectTokens(address(wbtc), user, 1e8);
    }

    function testCollectTokensInvalidCollateral() public {
        // Approve random token
        vm.prank(user);
        randomToken.approve(address(conduit), 1e18);

        // Try to collect non-allowed collateral
        vm.prank(address(vault));
        vm.expectRevert("Invalid collateral");
        conduit.collectTokens(address(randomToken), user, 1e18);
    }

    function testCollectTokensAllCollateralTypes() public {
        // Test WBTC (8 decimals)
        vm.prank(user);
        wbtc.approve(address(conduit), 1e8);

        vm.prank(address(vault));
        assertTrue(conduit.collectTokens(address(wbtc), user, 1e8));
        assertEq(wbtc.balanceOf(address(strategy)), 1e8);

        // Test tBTC (18 decimals)
        vm.prank(user);
        tbtc.approve(address(conduit), 1e18);

        vm.prank(address(vault));
        assertTrue(conduit.collectTokens(address(tbtc), user, 1e18));
        assertEq(tbtc.balanceOf(address(strategy)), 1e18);

        // Test SovaBTC
        vm.prank(user);
        sovaBTC.approve(address(conduit), 1e8);

        vm.prank(address(vault));
        assertTrue(conduit.collectTokens(address(sovaBTC), user, 1e8));
        assertEq(sovaBTC.balanceOf(address(strategy)), 1e8);
    }

    // Test rescueERC20
    function testRescueERC20Success() public {
        // Send tokens to conduit
        wbtc.mint(address(conduit), 5e8);

        // Rescue as admin
        vm.prank(admin);
        conduit.rescueERC20(address(wbtc), admin, 5e8);

        assertEq(wbtc.balanceOf(admin), 5e8);
        assertEq(wbtc.balanceOf(address(conduit)), 0);
    }

    function testRescueERC20Unauthorized() public {
        wbtc.mint(address(conduit), 1e8);

        // Try to rescue as non-admin
        vm.expectRevert();
        vm.prank(user);
        conduit.rescueERC20(address(wbtc), user, 1e8);
    }

    function testRescueERC20PartialAmount() public {
        // Send tokens to conduit
        sovaBTC.mint(address(conduit), 10e8);

        // Rescue partial amount
        vm.prank(admin);
        conduit.rescueERC20(address(sovaBTC), admin, 3e8);

        assertEq(sovaBTC.balanceOf(admin), 3e8);
        assertEq(sovaBTC.balanceOf(address(conduit)), 7e8);
    }

    // Test when isStrategyToken returns false (not reverting)
    function testCollectDepositIsStrategyTokenFalse() public {
        // Clear the mock to make isStrategyToken return false
        vm.clearMockedCalls();

        // Mock isStrategyToken to return false
        vm.mockCall(
            address(registry), abi.encodeWithSignature("isStrategyToken(address)", address(vault)), abi.encode(false)
        );

        vm.prank(user);
        sovaBTC.approve(address(conduit), 1e8);

        // Should revert with InvalidDestination when isStrategyToken returns false
        vm.expectRevert(Conduit.InvalidDestination.selector);
        vm.prank(address(vault));
        conduit.collectDeposit(address(sovaBTC), user, address(strategy), 1e8);
    }

    // Edge cases
    function testCollectTokensInsufficientBalance() public {
        // User has 10e8 WBTC, try to transfer 20e8
        vm.prank(user);
        wbtc.approve(address(conduit), 20e8);

        vm.expectRevert();
        vm.prank(address(vault));
        conduit.collectTokens(address(wbtc), user, 20e8);
    }

    function testCollectTokensInsufficientAllowance() public {
        // Approve less than transfer amount
        vm.prank(user);
        wbtc.approve(address(conduit), 0.5e8);

        vm.expectRevert();
        vm.prank(address(vault));
        conduit.collectTokens(address(wbtc), user, 1e8);
    }

    function testCollectDepositTransferFromZeroAddress() public {
        // This should revert in the token contract
        vm.expectRevert();
        vm.prank(address(vault));
        conduit.collectDeposit(address(sovaBTC), address(0), address(strategy), 1e8);
    }

    // Test with unregistered vault
    function testCollectTokensUnregisteredVault() public {
        // Create a new vault that's not registered
        MockTRWA unregisteredVault = new MockTRWA(address(sovaBTC), address(strategy));

        vm.prank(user);
        wbtc.approve(address(conduit), 1e8);

        vm.expectRevert(Conduit.InvalidDestination.selector);
        vm.prank(address(unregisteredVault));
        conduit.collectTokens(address(wbtc), user, 1e8);
    }
}
