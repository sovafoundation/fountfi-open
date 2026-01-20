// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockHook} from "../src/mocks/hooks/MockHook.sol";
import {MockReporter} from "../src/mocks/MockReporter.sol";
import {MockStrategy} from "../src/mocks/MockStrategy.sol";
import {MockRoleManager} from "../src/mocks/MockRoleManager.sol";
import {tRWA} from "../src/token/tRWA.sol";
import {Registry} from "../src/registry/Registry.sol";
import {RulesEngine} from "../src/hooks/RulesEngine.sol";
import {KycRulesHook} from "../src/hooks/KycRulesHook.sol";
import {MockCappedSubscriptionHook} from "../src/mocks/hooks/MockCappedSubscriptionHook.sol";
import {BaseHook} from "../src/hooks/BaseHook.sol";
import {IHook} from "../src/hooks/IHook.sol";
import {PriceOracleReporter} from "../src/reporter/PriceOracleReporter.sol";
import {ReportedStrategy} from "../src/strategy/ReportedStrategy.sol";
import {IStrategy} from "../src/strategy/IStrategy.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";

/**
 * @title BaseFountfiTest
 * @notice Base test contract with shared setup and utility functions
 */
abstract contract BaseFountfiTest is Test {
    // Test accounts
    address internal owner;
    address internal admin;
    address internal manager;
    address internal alice;
    address internal bob;
    address internal charlie;

    // Common contracts
    MockERC20 internal usdc;
    MockHook internal mockHook;
    MockReporter internal mockReporter;
    MockStrategy internal mockStrategy;
    Registry internal registry;

    // Base setup
    function setUp() public virtual {
        // Create test accounts
        owner = makeAddr("owner");
        admin = makeAddr("admin");
        manager = makeAddr("manager");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        // Setup initial balances
        vm.deal(owner, 100 ether);
        vm.deal(admin, 100 ether);
        vm.deal(manager, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);

        // Deploy mock contracts
        vm.startPrank(owner);
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // Mint tokens to test accounts (10,000 USDC each)
        usdc.mint(alice, 10_000 * 10 ** 6);
        usdc.mint(bob, 10_000 * 10 ** 6);
        usdc.mint(charlie, 10_000 * 10 ** 6);

        // Deploy mocks
        mockHook = new MockHook(true, "Mock rejection");
        mockReporter = new MockReporter(1000 * 10 ** 6); // 1000 USDC initial value
        mockStrategy = new MockStrategy();

        // Deploy Registry with the owner as role manager
        registry = new Registry(owner);
        vm.stopPrank();
    }

    // Helper to deploy a complete tRWA setup with mocks
    function deployMockTRWA(string memory name, string memory symbol) internal returns (MockStrategy, tRWA) {
        // Create a fresh MockHook and ensure it's initialized to allow by default
        vm.prank(owner);
        MockHook mockHookLocal = new MockHook(true, "Test rejection");

        // Register the hook in the registry
        vm.prank(owner);
        registry.setHook(address(mockHookLocal), true);

        // Create array of hooks
        address[] memory hookAddresses = new address[](1);
        hookAddresses[0] = address(mockHookLocal);

        // Deploy a new strategy
        vm.prank(owner);
        MockStrategy strategy = new MockStrategy();

        vm.prank(owner);
        strategy.initialize(
            name,
            symbol,
            owner, // roleManager
            manager,
            address(usdc),
            6,
            ""
        );

        // Get the token the strategy created
        tRWA token = tRWA(strategy.sToken());

        // Add hook to token for all operations
        vm.prank(owner);
        bytes32 opDeposit = keccak256("DEPOSIT_OPERATION");
        bytes32 opWithdraw = keccak256("WITHDRAW_OPERATION");
        bytes32 opTransfer = keccak256("TRANSFER_OPERATION");

        vm.prank(owner);
        strategy.callStrategyToken(abi.encodeCall(tRWA.addOperationHook, (opDeposit, address(mockHookLocal))));
        vm.prank(owner);
        strategy.callStrategyToken(abi.encodeCall(tRWA.addOperationHook, (opWithdraw, address(mockHookLocal))));
        vm.prank(owner);
        strategy.callStrategyToken(abi.encodeCall(tRWA.addOperationHook, (opTransfer, address(mockHookLocal))));

        return (strategy, token);
    }

    // Helper to set allowances and deposit USDC to a tRWA token
    function depositTRWA(address user, address trwaToken, uint256 assets) internal virtual returns (uint256) {
        vm.startPrank(user);
        usdc.approve(trwaToken, assets);
        uint256 shares = tRWA(trwaToken).deposit(assets, user);
        vm.stopPrank();
        return shares;
    }

    // Helper to create a complete test deployment via Registry
    function deployThroughRegistry()
        internal
        returns (address strategyAddr, address tokenAddr, KycRulesHook kycRules, MockReporter reporter)
    {
        vm.startPrank(owner);

        // Setup Registry
        registry.setAsset(address(usdc), 6);

        // Deploy real RoleManager
        RoleManager roleManager = new RoleManager();
        roleManager.initializeRegistry(address(registry));

        // Deploy hooks with the real role manager
        kycRules = new KycRulesHook(address(roleManager));

        // Grant KYC_OPERATOR role to the owner for testing KycRulesHook operations.
        roleManager.grantRole(owner, roleManager.KYC_OPERATOR());

        // Register the hook in the registry
        registry.setHook(address(kycRules), true);

        // Create hook addresses array
        address[] memory hookAddresses = new address[](1);
        hookAddresses[0] = address(kycRules);

        // Create reporter
        reporter = new MockReporter(1000 * 10 ** 6);

        // Setup an implementation of MockStrategy
        MockStrategy strategyImpl = new MockStrategy();
        registry.setStrategy(address(strategyImpl), true);

        // Deploy via registry
        (strategyAddr, tokenAddr) =
            registry.deploy(address(strategyImpl), "Test RWA", "TRWA", address(usdc), manager, "");

        vm.stopPrank();
    }
}
