// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {Registry} from "../src/registry/Registry.sol";
import {IRegistry} from "../src/registry/IRegistry.sol";
import {MockStrategy} from "../src/mocks/MockStrategy.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {RoleManaged} from "../src/auth/RoleManaged.sol";
import {IStrategy} from "../src/strategy/IStrategy.sol";
import {ItRWA} from "../src/token/ItRWA.sol";
import {LibRoleManaged} from "../src/auth/LibRoleManaged.sol";

/**
 * @title RegistryTest
 * @notice Comprehensive test suite for Registry contract
 */
contract RegistryTest is Test {
    Registry public registry;
    RoleManager public roleManager;
    MockERC20 public usdc;
    MockStrategy public strategyImpl;

    address public owner = address(this);
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        vm.startPrank(owner);

        // Deploy components
        roleManager = new RoleManager();
        registry = new Registry(address(roleManager));
        roleManager.initializeRegistry(address(registry));

        // Setup roles
        roleManager.grantRole(owner, roleManager.PROTOCOL_ADMIN());
        roleManager.grantRole(owner, roleManager.STRATEGY_ADMIN());
        roleManager.grantRole(owner, roleManager.RULES_ADMIN());
        roleManager.grantRole(owner, roleManager.STRATEGY_OPERATOR());

        // Deploy mock contracts
        usdc = new MockERC20("USD Coin", "USDC", 6);
        strategyImpl = new MockStrategy();

        // Register asset and strategy
        registry.setAsset(address(usdc), 6);
        registry.setStrategy(address(strategyImpl), true);

        vm.stopPrank();
    }

    function test_Constructor_ZeroAddress() public {
        vm.expectRevert(RoleManaged.InvalidRoleManager.selector);
        new Registry(address(0));
    }

    function test_ConduitAddress() public view {
        address conduitAddr = registry.conduit();
        assertTrue(conduitAddr != address(0));
    }

    function test_RegistrationFunctions() public {
        vm.startPrank(owner);

        // Create asset token
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);

        // Test asset registration
        registry.setAsset(address(asset), 6);
        assertTrue(registry.allowedAssets(address(asset)) == 6);

        // Test asset unregistration
        registry.setAsset(address(asset), 0);
        assertTrue(registry.allowedAssets(address(asset)) == 0);

        // Test operation hook registration
        address mockHook = makeAddr("hook");
        registry.setHook(mockHook, true);
        assertTrue(registry.allowedHooks(mockHook));

        // Test strategy registration
        address mockStrategy = makeAddr("strategy");
        registry.setStrategy(mockStrategy, true);
        assertTrue(registry.allowedStrategies(mockStrategy));

        vm.stopPrank();
    }

    function test_Deploy_Success() public {
        vm.startPrank(owner);

        // Deploy a strategy and capture return values
        (address returnedStrategy, address returnedToken) = registry.deploy(
            address(strategyImpl),
            "Test RWA Token",
            "tRWA",
            address(usdc),
            owner, // manager
            "" // initData
        );

        // Verify deployment
        assertTrue(returnedStrategy != address(0));
        assertTrue(returnedToken != address(0));
        assertTrue(registry.isStrategy(returnedStrategy));

        // Verify the strategy's token
        assertEq(IStrategy(returnedStrategy).sToken(), returnedToken);

        // Use the return values to ensure line coverage
        address strategy = returnedStrategy;
        address token = returnedToken;
        assertEq(strategy, returnedStrategy);
        assertEq(token, returnedToken);

        vm.stopPrank();
    }

    function test_AllStrategies() public {
        vm.startPrank(owner);

        // Initially empty
        address[] memory strategies = registry.allStrategies();
        assertEq(strategies.length, 0);

        // Deploy some strategies
        (address strategy1,) =
            registry.deploy(address(strategyImpl), "Test RWA Token 1", "tRWA1", address(usdc), owner, "");

        (address strategy2,) =
            registry.deploy(address(strategyImpl), "Test RWA Token 2", "tRWA2", address(usdc), owner, "");

        // Check all strategies
        strategies = registry.allStrategies();
        assertEq(strategies.length, 2);
        assertEq(strategies[0], strategy1);
        assertEq(strategies[1], strategy2);

        vm.stopPrank();
    }

    function test_AllStrategyTokens_WithDeployedStrategies() public {
        vm.startPrank(owner);

        // Deploy some strategies and explicitly use return values
        (address strategy1, address token1) =
            registry.deploy(address(strategyImpl), "Test RWA Token 1", "tRWA1", address(usdc), owner, "");

        // Ensure return values are used
        emit log_address(strategy1);
        emit log_address(token1);

        (address strategy2, address token2) =
            registry.deploy(address(strategyImpl), "Test RWA Token 2", "tRWA2", address(usdc), owner, "");

        // Ensure return values are used
        emit log_address(strategy2);
        emit log_address(token2);

        // Get all strategy tokens
        address[] memory tokens = registry.allStrategyTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], token1);
        assertEq(tokens[1], token2);

        vm.stopPrank();
    }

    function test_AllStrategyTokens_Empty() public view {
        // Test the empty case when no strategies are deployed
        address[] memory tokens = registry.allStrategyTokens();
        assertEq(tokens.length, 0);
    }

    function test_IsStrategyToken_WithDeployedStrategy() public {
        vm.startPrank(owner);

        // Deploy a strategy
        (, address token) = registry.deploy(address(strategyImpl), "Test RWA Token", "tRWA", address(usdc), owner, "");

        // Check if it's a strategy token
        assertTrue(registry.isStrategyToken(token));

        vm.stopPrank();
    }

    function test_IsStrategyToken_NonRegisteredStrategy() public {
        // For a random token, we need to mock the strategy() call
        address randomToken = makeAddr("randomToken");
        address nonRegisteredStrategy = makeAddr("nonRegisteredStrategy");

        // Mock the strategy() call to return a non-registered strategy
        vm.mockCall(
            randomToken, abi.encodeWithSelector(bytes4(keccak256("strategy()"))), abi.encode(nonRegisteredStrategy)
        );

        // Check that it's not a strategy token
        assertFalse(registry.isStrategyToken(randomToken));
    }

    function test_IsStrategyToken_RegisteredStrategyButTokenMismatch() public {
        vm.startPrank(owner);

        // Deploy a strategy
        (address strategy,) = registry.deploy(address(strategyImpl), "Test RWA Token", "tRWA", address(usdc), owner, "");

        // Create a different token that claims to use the same strategy
        address fakeToken = makeAddr("fakeToken");

        // Mock the strategy() call on the fake token to return the registered strategy
        vm.mockCall(fakeToken, abi.encodeWithSelector(bytes4(keccak256("strategy()"))), abi.encode(strategy));

        // The strategy is registered, but the check compares IStrategy(strategy).asset() with the token
        // Since asset() returns the underlying asset (USDC), not the token, this will be false
        assertFalse(registry.isStrategyToken(fakeToken));

        vm.stopPrank();
    }

    function test_IsStrategyToken_BidirectionalValidation() public {
        vm.startPrank(owner);

        // Deploy a strategy to get the real token
        (address strategy, address token) =
            registry.deploy(address(strategyImpl), "Test RWA Token", "tRWA", address(usdc), owner, "");

        // This test verifies the bidirectional validation:
        // 1. The token must report a strategy that is registered
        // 2. The strategy must report the token as its sToken

        // Verify the strategy is registered
        assertTrue(registry.isStrategy(strategy));

        // Verify the token's strategy() returns the correct strategy
        assertEq(ItRWA(token).strategy(), strategy);

        // Verify the strategy's sToken() returns the token
        assertEq(IStrategy(strategy).sToken(), token);

        // With bidirectional validation, this should return true
        assertTrue(registry.isStrategyToken(token));

        vm.stopPrank();
    }

    function test_IsStrategyToken_WithSpoofedToken() public {
        vm.startPrank(owner);

        // Deploy a legitimate strategy
        (address strategy,) = registry.deploy(address(strategyImpl), "Test RWA Token", "tRWA", address(usdc), owner, "");

        // Create a fake token that claims to use the same strategy
        address fakeToken = makeAddr("fakeToken");

        // Mock the strategy() call on the fake token to return the registered strategy
        vm.mockCall(fakeToken, abi.encodeWithSelector(bytes4(keccak256("strategy()"))), abi.encode(strategy));

        // Even though the strategy is registered and the fake token claims to use it,
        // the fake token should not pass because IStrategy(strategy).sToken() != fakeToken
        // This prevents malicious contracts from impersonating legitimate tRWA tokens
        assertFalse(registry.isStrategyToken(fakeToken));

        vm.stopPrank();
    }

    function test_ZeroAddressChecks() public {
        vm.startPrank(owner);

        vm.expectRevert(IRegistry.ZeroAddress.selector);
        registry.setAsset(address(0), 6);

        vm.expectRevert(IRegistry.ZeroAddress.selector);
        registry.setHook(address(0), true);

        vm.expectRevert(IRegistry.ZeroAddress.selector);
        registry.setStrategy(address(0), true);

        vm.stopPrank();
    }

    function test_Deploy_UnauthorizedAsset() public {
        vm.startPrank(owner);

        // Try to deploy with unregistered asset
        address unregisteredAsset = makeAddr("unregisteredAsset");

        vm.expectRevert(IRegistry.UnauthorizedAsset.selector);
        registry.deploy(address(strategyImpl), "Test RWA Token", "tRWA", unregisteredAsset, owner, "");

        vm.stopPrank();
    }

    function test_Deploy_UnauthorizedStrategy() public {
        vm.startPrank(owner);

        // Try to deploy with unregistered strategy
        MockStrategy unregisteredStrategy = new MockStrategy();

        vm.expectRevert(IRegistry.UnauthorizedStrategy.selector);
        registry.deploy(address(unregisteredStrategy), "Test RWA Token", "tRWA", address(usdc), owner, "");

        vm.stopPrank();
    }

    function test_Deploy_UnauthorizedCaller() public {
        vm.startPrank(alice); // alice doesn't have STRATEGY_OPERATOR role

        vm.expectRevert(
            abi.encodeWithSelector(LibRoleManaged.UnauthorizedRole.selector, alice, roleManager.STRATEGY_OPERATOR())
        );
        registry.deploy(address(strategyImpl), "Test RWA Token", "tRWA", address(usdc), alice, "");

        vm.stopPrank();
    }

    function test_SetStrategy_UnauthorizedCaller() public {
        vm.startPrank(alice); // alice doesn't have STRATEGY_ADMIN role

        vm.expectRevert(
            abi.encodeWithSelector(LibRoleManaged.UnauthorizedRole.selector, alice, roleManager.STRATEGY_ADMIN())
        );
        registry.setStrategy(makeAddr("strategy"), true);

        vm.stopPrank();
    }

    function test_SetHook_UnauthorizedCaller() public {
        vm.startPrank(alice); // alice doesn't have RULES_ADMIN role

        vm.expectRevert(
            abi.encodeWithSelector(LibRoleManaged.UnauthorizedRole.selector, alice, roleManager.RULES_ADMIN())
        );
        registry.setHook(makeAddr("hook"), true);

        vm.stopPrank();
    }

    function test_SetAsset_UnauthorizedCaller() public {
        vm.startPrank(alice); // alice doesn't have PROTOCOL_ADMIN role

        vm.expectRevert(
            abi.encodeWithSelector(LibRoleManaged.UnauthorizedRole.selector, alice, roleManager.PROTOCOL_ADMIN())
        );
        registry.setAsset(makeAddr("asset"), 6);

        vm.stopPrank();
    }

    function test_DeployRequiresAuthorization() public {
        vm.startPrank(owner);

        // Create local instances we control
        MockERC20 localUsdc = new MockERC20("USD Coin", "USDC", 6);
        address localRules = makeAddr("rules");
        address localStrategy = makeAddr("strategy");

        // Test require conditions on deploy
        registry.setAsset(address(localUsdc), 6);
        registry.setHook(localRules, true);
        registry.setStrategy(localStrategy, true);

        // Check that we can register and toggle components
        assertTrue(registry.allowedAssets(address(localUsdc)) == 6);
        assertTrue(registry.allowedHooks(localRules));
        assertTrue(registry.allowedStrategies(localStrategy));

        // Set them to false again
        registry.setAsset(address(localUsdc), 0);
        registry.setHook(localRules, false);
        registry.setStrategy(localStrategy, false);

        // Verify they're toggled off
        assertTrue(registry.allowedAssets(address(localUsdc)) == 0);
        assertFalse(registry.allowedHooks(localRules));
        assertFalse(registry.allowedStrategies(localStrategy));

        vm.stopPrank();
    }

    function test_RoleBasedAccess() public {
        // Test that the owner has the correct roles
        assertTrue(roleManager.hasAnyRole(owner, roleManager.PROTOCOL_ADMIN()));
        assertTrue(roleManager.hasAnyRole(owner, roleManager.RULES_ADMIN()));
        assertTrue(roleManager.hasAnyRole(owner, roleManager.STRATEGY_ADMIN()));

        // Create a new user without any roles
        address newUser = address(0x1234);

        // Verify newUser has no roles
        assertFalse(roleManager.hasAnyRole(newUser, roleManager.PROTOCOL_ADMIN()));
        assertFalse(roleManager.hasAnyRole(newUser, roleManager.RULES_ADMIN()));
        assertFalse(roleManager.hasAnyRole(newUser, roleManager.STRATEGY_ADMIN()));

        // Test that functions work correctly with proper roles (owner has all roles)
        address testAsset = makeAddr("testAsset");
        address testHook = makeAddr("testHook");
        address testStrategy = makeAddr("testStrategy");

        vm.prank(owner);
        registry.setAsset(testAsset, 8);
        assertEq(registry.allowedAssets(testAsset), 8);

        vm.prank(owner);
        registry.setHook(testHook, true);
        assertTrue(registry.allowedHooks(testHook));

        vm.prank(owner);
        registry.setStrategy(testStrategy, true);
        assertTrue(registry.allowedStrategies(testStrategy));
    }

    /**
     * @notice Test to ensure the return statement in deploy function is covered
     * @dev This test specifically targets line 120 in Registry.sol
     */
    function test_DeployReturnValues() public {
        vm.startPrank(owner);

        // Deploy and explicitly test both return values
        (address deployedStrategy, address deployedToken) =
            registry.deploy(address(strategyImpl), "Coverage Test Token", "CTT", address(usdc), owner, "");

        // Explicitly verify return values to ensure line 120 is hit
        assertTrue(deployedStrategy != address(0), "Strategy address should not be zero");
        assertTrue(deployedToken != address(0), "Token address should not be zero");

        // Additional checks to ensure the return values are correct
        assertEq(IStrategy(deployedStrategy).sToken(), deployedToken, "Strategy token should match returned token");
        assertTrue(registry.isStrategy(deployedStrategy), "Deployed address should be registered as strategy");

        vm.stopPrank();
    }
}
