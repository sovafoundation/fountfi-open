// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {BaseFountfiTest} from "./BaseFountfiTest.t.sol";
import {Conduit} from "../src/conduit/Conduit.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {Registry} from "../src/registry/Registry.sol";
import {tRWA} from "../src/token/tRWA.sol";
import {MockRegistry} from "../src/mocks/MockRegistry.sol";
import {MockStrategy} from "../src/mocks/MockStrategy.sol";
import {LibRoleManaged} from "../src/auth/LibRoleManaged.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/**
 * @title ConduitTest
 * @notice Comprehensive tests for Conduit contract to achieve 100% coverage
 */
contract ConduitTest is BaseFountfiTest {
    // Contracts under test
    Conduit public conduit;
    RoleManager public conduitRoleManager;
    Registry public conduitRegistry;
    MockERC20 public testToken;
    MockStrategy public strategy;
    tRWA public trwaToken;

    // Test constants
    uint256 public constant DEPOSIT_AMOUNT = 1000 * 10 ** 6;

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);

        // Deploy role manager
        conduitRoleManager = new RoleManager();
        conduitRoleManager.initializeRegistry(address(this)); // Use test contract as placeholder registry

        // Deploy registry with the registry() method
        conduitRegistry = new Registry(address(conduitRoleManager));

        // Deploy conduit
        conduit = new Conduit(address(conduitRoleManager));

        // Registry is already initialized, so we'll mock the registry() call
        vm.mockCall(
            address(conduitRoleManager), abi.encodeWithSignature("registry()"), abi.encode(address(conduitRegistry))
        );

        // For the registry to track the conduit, we need to set it properly
        // Since we can't directly set the conduit in Registry, we'll use VM mocking
        vm.mockCall(address(conduitRegistry), abi.encodeWithSignature("conduit()"), abi.encode(address(conduit)));

        // Create test token
        testToken = new MockERC20("Test Token", "TEST", 6);

        // Register token in registry
        conduitRegistry.setAsset(address(testToken), 6);

        // Deploy a strategy
        strategy = new MockStrategy();
        strategy.initialize("Test Strategy", "TEST", address(conduitRoleManager), manager, address(testToken), 6, "");

        // Register strategy in registry
        conduitRegistry.setStrategy(address(strategy), true);

        // Get the token that the strategy created
        trwaToken = tRWA(strategy.sToken());

        // Now we need to mock isStrategyToken to return true for our token
        vm.mockCall(
            address(conduitRegistry),
            abi.encodeWithSignature("isStrategyToken(address)", address(trwaToken)),
            abi.encode(true)
        );

        // Mock the trwaToken's asset function to return testToken
        vm.mockCall(address(trwaToken), abi.encodeWithSignature("asset()"), abi.encode(address(testToken)));

        // Mint tokens to test accounts
        testToken.mint(alice, DEPOSIT_AMOUNT * 10);
        testToken.mint(bob, DEPOSIT_AMOUNT * 10);
        testToken.mint(address(conduit), DEPOSIT_AMOUNT); // Some tokens directly to the conduit for rescue tests

        vm.stopPrank();

        // Set approvals
        vm.prank(alice);
        testToken.approve(address(conduit), type(uint256).max);

        vm.prank(bob);
        testToken.approve(address(conduit), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public view {
        // Verify constructor set up the role manager correctly
        assertEq(address(conduit.roleManager()), address(conduitRoleManager));
    }

    /*//////////////////////////////////////////////////////////////
                        COLLECT DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CollectDeposit_Success() public {
        // Make sure we're pretending to be the strategy token to call collect deposit
        vm.startPrank(address(trwaToken));

        address currentStrategy = trwaToken.strategy();
        uint256 initialTRWABalance = testToken.balanceOf(address(trwaToken));
        uint256 initialAliceBalance = testToken.balanceOf(alice);

        // Call collect deposit
        bool success = conduit.collectDeposit(address(testToken), alice, currentStrategy, DEPOSIT_AMOUNT);

        // Verify transfer happened
        assertTrue(success, "Collect deposit should return true");
        assertEq(
            testToken.balanceOf(currentStrategy),
            initialTRWABalance + DEPOSIT_AMOUNT,
            "strategy should receive the tokens"
        );
        assertEq(testToken.balanceOf(alice), initialAliceBalance - DEPOSIT_AMOUNT, "Alice's balance should decrease");

        vm.stopPrank();
    }

    function test_CollectDeposit_InvalidAmount() public {
        // Try to collect 0 tokens
        vm.startPrank(address(trwaToken));

        vm.expectRevert(Conduit.InvalidAmount.selector);
        conduit.collectDeposit(address(testToken), alice, address(trwaToken), 0);

        vm.stopPrank();
    }

    function test_CollectDeposit_InvalidToken() public {
        // Create a token that isn't registered in the registry
        MockERC20 invalidToken = new MockERC20("Invalid Token", "INVALID", 18);

        vm.startPrank(address(trwaToken));

        vm.expectRevert(Conduit.InvalidToken.selector);
        conduit.collectDeposit(address(invalidToken), alice, address(trwaToken), DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function test_CollectDeposit_InvalidDestination() public {
        // Call from an address that's not a registered strategy token
        vm.startPrank(alice);

        // First we need to update our mock to return false for alice
        vm.mockCall(
            address(conduitRegistry), abi.encodeWithSignature("isStrategyToken(address)", alice), abi.encode(false)
        );

        vm.expectRevert(Conduit.InvalidDestination.selector);
        conduit.collectDeposit(address(testToken), alice, address(trwaToken), DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function test_CollectDeposit_NonMatchingAsset() public {
        // Create another token that is registered in the registry but not the asset of the strategy
        MockERC20 differentToken = new MockERC20("Different Token", "DIFF", 6);

        vm.prank(owner);
        conduitRegistry.setAsset(address(differentToken), 6);

        vm.startPrank(address(trwaToken));

        vm.expectRevert(Conduit.InvalidToken.selector);
        conduit.collectDeposit(address(differentToken), alice, address(trwaToken), DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function test_CollectDeposit_TransferFails() public {
        // Try to transfer more than the user has approved

        // First, reset approval to a low amount
        vm.prank(alice);
        testToken.approve(address(conduit), DEPOSIT_AMOUNT / 2);

        vm.startPrank(address(trwaToken));

        address currentStrategy = trwaToken.strategy();

        // Should revert with the underlying SafeTransferLib error
        vm.expectRevert(abi.encodeWithSelector(SafeTransferLib.TransferFromFailed.selector));
        conduit.collectDeposit(address(testToken), alice, currentStrategy, DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function test_CollectDeposit_InvalidDestination_WrongStrategy() public {
        // Test case where the 'to' address doesn't match the strategy of the calling token
        address wrongDestination = address(0x999);

        vm.startPrank(address(trwaToken));

        vm.expectRevert(Conduit.InvalidDestination.selector);
        conduit.collectDeposit(
            address(testToken),
            alice,
            wrongDestination, // This doesn't match trwaToken.strategy()
            DEPOSIT_AMOUNT
        );

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                          RESCUE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RescueERC20_Success() public {
        // Tokens are already in the conduit from setUp
        uint256 initialConduitBalance = testToken.balanceOf(address(conduit));
        uint256 initialBobBalance = testToken.balanceOf(bob);

        // Call rescue as protocol admin
        vm.prank(owner);
        conduit.rescueERC20(address(testToken), bob, initialConduitBalance);

        // Verify the transfer
        assertEq(testToken.balanceOf(address(conduit)), 0, "Conduit should have 0 tokens left");
        assertEq(
            testToken.balanceOf(bob), initialBobBalance + initialConduitBalance, "Bob should receive the rescued tokens"
        );
    }

    function test_RescueERC20_Unauthorized() public {
        // Try to call rescue as non-admin
        vm.startPrank(alice);

        vm.expectRevert(
            abi.encodeWithSelector(LibRoleManaged.UnauthorizedRole.selector, alice, conduitRoleManager.PROTOCOL_ADMIN())
        ); // Will revert with UnauthorizedRole
        conduit.rescueERC20(address(testToken), bob, DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function test_RescueERC20_TransferFails() public {
        // Test with an amount greater than what the conduit has
        uint256 excessiveAmount = testToken.balanceOf(address(conduit)) * 2;

        vm.startPrank(owner);

        // Should revert with the underlying SafeTransferLib error
        vm.expectRevert(abi.encodeWithSelector(SafeTransferLib.TransferFailed.selector));
        conduit.rescueERC20(address(testToken), bob, excessiveAmount);

        vm.stopPrank();
    }
}
