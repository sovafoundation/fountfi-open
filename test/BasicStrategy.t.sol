// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseFountfiTest} from "./BaseFountfiTest.t.sol";
import {BasicStrategy} from "../src/strategy/BasicStrategy.sol";
import {IStrategy} from "../src/strategy/IStrategy.sol";
import {tRWA} from "../src/token/tRWA.sol";
import {RoleManaged} from "../src/auth/RoleManaged.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {LibRoleManaged} from "../src/auth/LibRoleManaged.sol";
import {CloneableRoleManaged} from "../src/auth/CloneableRoleManaged.sol";
import {MockHook} from "../src/mocks/hooks/MockHook.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/**
 * @title TestableBasicStrategy
 * @notice Concrete implementation of BasicStrategy for testing
 */
contract TestableBasicStrategy is BasicStrategy {
    constructor() {}

    /**
     * @notice Get the balance of the strategy
     * @return The balance of the strategy in the underlying asset
     */
    function balance() external view override returns (uint256) {
        return MockERC20(asset).balanceOf(address(this));
    }
}

/**
 * @title PayableTest
 * @notice Helper contract for testing payable calls
 */
contract PayableTest {
    receive() external payable {}
}

/**
 * @title BasicStrategyTest
 * @notice Tests for BasicStrategy
 */
contract BasicStrategyTest is BaseFountfiTest {
    // Test contracts
    TestableBasicStrategy public strategy;
    tRWA public token;
    RoleManager public roleManager;
    MockHook public strategyHook;
    MockERC20 public daiToken;

    // Strategy parameters
    string constant TOKEN_NAME = "Test Token";
    string constant TOKEN_SYMBOL = "TT";

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);

        // Deploy RoleManager. 'owner' will be the contract owner and PROTOCOL_ADMIN.
        roleManager = new RoleManager();
        // Initialize the registry for RoleManager.
        // Using address(this) as a placeholder for the registry address.
        roleManager.initializeRegistry(address(this)); // It's owner who calls this.

        // Deploy test DAI token as the asset
        daiToken = new MockERC20("DAI Stablecoin", "DAI", 18);

        // Deploy hooks
        strategyHook = new MockHook(true, "");

        // Deploy the strategy
        strategy = new TestableBasicStrategy();

        // Initialize the strategy (without hooks)
        strategy.initialize(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            address(roleManager),
            manager, // 'manager' from BaseFountfiTest.t.sol will be the strategy manager
            address(daiToken),
            18,
            ""
        );

        // Get the token that was deployed during initialization
        token = tRWA(strategy.sToken());

        // Add the hook to the token for all operations
        bytes32 opDeposit = keccak256("DEPOSIT_OPERATION");
        bytes32 opWithdraw = keccak256("WITHDRAW_OPERATION");
        bytes32 opTransfer = keccak256("TRANSFER_OPERATION");

        strategy.callStrategyToken(abi.encodeCall(tRWA.addOperationHook, (opDeposit, address(strategyHook))));
        strategy.callStrategyToken(abi.encodeCall(tRWA.addOperationHook, (opWithdraw, address(strategyHook))));
        strategy.callStrategyToken(abi.encodeCall(tRWA.addOperationHook, (opTransfer, address(strategyHook))));

        // Fund the strategy with some DAI
        daiToken.mint(address(strategy), 1000 * 10 ** 18);

        vm.stopPrank();
    }

    function test_Initialization() public view {
        // Check that the strategy was initialized correctly
        assertEq(strategy.registry(), address(this), "Registry should be set to test contract address");
        assertEq(strategy.manager(), manager, "Manager should be set correctly");
        assertEq(strategy.asset(), address(daiToken), "Asset should be set correctly");
        assertEq(address(token), strategy.sToken(), "Token should be set correctly");

        // Check that the token was initialized correctly
        assertEq(token.name(), TOKEN_NAME, "Token name should be set correctly");
        assertEq(token.symbol(), TOKEN_SYMBOL, "Token symbol should be set correctly");
        assertEq(address(token.asset()), address(daiToken), "Token asset should be set correctly");
        assertEq(address(token.strategy()), address(strategy), "Token strategy should be set correctly");
    }

    function test_Reinitialization() public {
        vm.startPrank(owner);

        // Attempting to reinitialize should revert
        vm.expectRevert(IStrategy.AlreadyInitialized.selector);
        strategy.initialize("New Name", "NEW", address(roleManager), alice, address(daiToken), 18, "");

        vm.stopPrank();
    }

    function test_InitWithInvalidParams() public {
        vm.startPrank(owner);

        // Deploy a new strategy to test initialization with invalid params
        TestableBasicStrategy newStrategy = new TestableBasicStrategy();

        // Test zero address for manager
        vm.expectRevert(IStrategy.InvalidAddress.selector);
        newStrategy.initialize(TOKEN_NAME, TOKEN_SYMBOL, address(roleManager), address(0), address(daiToken), 18, "");

        // Test zero address for asset
        vm.expectRevert(IStrategy.InvalidAddress.selector);
        newStrategy.initialize(TOKEN_NAME, TOKEN_SYMBOL, address(roleManager), manager, address(0), 18, "");

        // Test zero address for roleManager (covers CloneableRoleManaged branch)
        TestableBasicStrategy newStrategy2 = new TestableBasicStrategy();
        vm.expectRevert(CloneableRoleManaged.InvalidRoleManager.selector);
        newStrategy2.initialize(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            address(0), // Zero address roleManager
            manager,
            address(daiToken),
            18,
            ""
        );

        vm.stopPrank();
    }

    function test_ManagerChange() public {
        vm.startPrank(owner);

        // Looking at the contract code, we need to have the STRATEGY_ADMIN role to set the manager
        // First grant the role to the owner
        // roleManager.grantRole(owner, roleManager.STRATEGY_ADMIN()); // Remove this line

        // Change manager to alice
        strategy.setManager(alice);
        assertEq(strategy.manager(), alice, "Manager should be changed to alice");

        // We shouldn't set the manager to address(0) as this might be prevented by the contract
        // Let's change to a different address instead
        strategy.setManager(bob);
        assertEq(strategy.manager(), bob, "Manager should be changed to bob");

        vm.stopPrank();
    }

    function test_ManagerChangeUnauthorized() public {
        vm.startPrank(alice);

        // Alice is not authorized to change the manager
        vm.expectRevert(
            abi.encodeWithSelector(LibRoleManaged.UnauthorizedRole.selector, alice, roleManager.STRATEGY_ADMIN())
        );
        strategy.setManager(bob);

        vm.stopPrank();
    }

    function test_Balance() public view {
        uint256 bal = strategy.balance();
        assertEq(bal, 1000 * 10 ** 18, "Balance should match minted amount");
    }

    function test_SendETH() public {
        // Fund the strategy with some ETH
        vm.deal(address(strategy), 1 ether);

        vm.startPrank(manager);

        uint256 initialBob = address(bob).balance;

        // Send all ETH to bob
        strategy.sendETH(bob);

        assertEq(address(bob).balance, initialBob + 1 ether, "Bob should receive 1 ETH");
        assertEq(address(strategy).balance, 0, "Strategy should have 0 ETH left");

        vm.stopPrank();
    }

    function test_SendETHUnauthorized() public {
        vm.deal(address(strategy), 1 ether);

        vm.startPrank(alice);

        // Alice is not the manager
        vm.expectRevert(IStrategy.Unauthorized.selector);
        strategy.sendETH(bob);

        vm.stopPrank();
    }

    function test_SendToken() public {
        // Deploy a new token
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);
        newToken.mint(address(strategy), 500 * 10 ** 18);

        vm.startPrank(manager);

        uint256 initialBob = newToken.balanceOf(bob);
        uint256 initialStrategy = newToken.balanceOf(address(strategy));

        // Send 200 tokens to bob
        strategy.sendToken(address(newToken), bob, 200 * 10 ** 18);

        assertEq(newToken.balanceOf(bob), initialBob + 200 * 10 ** 18, "Bob should receive 200 tokens");
        assertEq(
            newToken.balanceOf(address(strategy)), initialStrategy - 200 * 10 ** 18, "Strategy should send 200 tokens"
        );

        vm.stopPrank();
    }

    function test_SendTokenUnauthorized() public {
        vm.startPrank(alice);

        // Alice is not the manager
        vm.expectRevert(IStrategy.Unauthorized.selector);
        strategy.sendToken(address(daiToken), bob, 100 * 10 ** 18);

        vm.stopPrank();
    }

    function test_PullToken() public {
        vm.startPrank(owner);
        // Mint some tokens to charlie
        daiToken.mint(charlie, 300 * 10 ** 18);
        vm.stopPrank();

        vm.startPrank(charlie);
        daiToken.approve(address(strategy), 300 * 10 ** 18);
        vm.stopPrank();

        vm.startPrank(manager);

        uint256 initialCharlie = daiToken.balanceOf(charlie);
        uint256 initialStrategy = daiToken.balanceOf(address(strategy));

        // Pull 200 tokens from charlie
        strategy.pullToken(address(daiToken), charlie, 200 * 10 ** 18);

        assertEq(daiToken.balanceOf(charlie), initialCharlie - 200 * 10 ** 18, "Charlie should lose 200 tokens");
        assertEq(
            daiToken.balanceOf(address(strategy)), initialStrategy + 200 * 10 ** 18, "Strategy should gain 200 tokens"
        );

        vm.stopPrank();
    }

    function test_PullTokenUnauthorized() public {
        vm.startPrank(alice);

        // Alice is not the manager
        vm.expectRevert(IStrategy.Unauthorized.selector);
        strategy.pullToken(address(daiToken), charlie, 100 * 10 ** 18);

        vm.stopPrank();
    }

    function test_SetAllowance() public {
        vm.startPrank(manager);

        // Check initial allowance is 0
        assertEq(daiToken.allowance(address(strategy), alice), 0, "Initial allowance should be 0");

        // Set allowance to 500 tokens
        strategy.setAllowance(address(daiToken), alice, 500 * 10 ** 18);

        assertEq(daiToken.allowance(address(strategy), alice), 500 * 10 ** 18, "Allowance should be 500 tokens");

        vm.stopPrank();
    }

    function test_SetAllowanceUnauthorized() public {
        vm.startPrank(alice);

        // Alice is not the manager
        vm.expectRevert(IStrategy.Unauthorized.selector);
        strategy.setAllowance(address(daiToken), bob, 100 * 10 ** 18);

        vm.stopPrank();
    }

    function test_Call() public {
        vm.startPrank(manager);

        // Setup a call to the token transfer function
        bytes memory callData = abi.encodeWithSignature("transfer(address,uint256)", bob, 100 * 10 ** 18);

        uint256 initialBob = daiToken.balanceOf(bob);

        // Call the transfer function
        (bool success, bytes memory returnData) = strategy.call(address(daiToken), 0, callData);

        assertTrue(success, "Call should succeed");
        assertEq(abi.decode(returnData, (bool)), true, "Transfer should return true");
        assertEq(daiToken.balanceOf(bob), initialBob + 100 * 10 ** 18, "Bob should receive 100 tokens");

        vm.stopPrank();
    }

    function test_CallWithValue() public {
        // Fund the strategy with ETH
        vm.deal(address(strategy), 2 ether);

        // Deploy a simple payable contract
        PayableTest payableContract = new PayableTest();

        vm.startPrank(manager);

        // Call the contract with 1 ETH
        (bool success,) = strategy.call(address(payableContract), 1 ether, "");

        assertTrue(success, "Call should succeed");
        assertEq(address(payableContract).balance, 1 ether, "Contract should receive 1 ETH");

        vm.stopPrank();
    }

    function test_CallRevert() public {
        vm.startPrank(manager);

        // Try to call a non-existent function that will revert
        bytes memory callData = abi.encodeWithSignature("nonExistentFunction()");

        vm.expectRevert(); // low-level solidity error
        strategy.call(address(daiToken), 0, callData);

        vm.stopPrank();
    }

    function test_CallZeroAddress() public {
        vm.startPrank(manager);

        // Try to call address(0)
        vm.expectRevert(IStrategy.InvalidAddress.selector);
        strategy.call(address(0), 0, "");

        vm.stopPrank();
    }

    function test_CallCannotCallToken() public {
        vm.startPrank(manager);

        // Get the strategy token address first
        address strategyToken = strategy.sToken();

        // Try to call the strategy token directly through call() function
        // This should revert with CannotCallToken error
        vm.expectRevert(IStrategy.CannotCallToken.selector);
        strategy.call(strategyToken, 0, "");

        vm.stopPrank();
    }

    function test_CallUnauthorized() public {
        vm.startPrank(alice);

        // Alice is not the manager
        vm.expectRevert(IStrategy.Unauthorized.selector);
        strategy.call(address(daiToken), 0, "");

        vm.stopPrank();
    }

    function test_CallStrategyToken() public {
        vm.startPrank(owner);

        // First, we need the STRATEGY_ADMIN role to use the addOperationHook function
        // roleManager.grantRole(address(strategy), roleManager.STRATEGY_ADMIN()); // Remove this line

        // Test the callStrategyToken function
        MockHook newHook = new MockHook(true, "");

        // Call the token through the strategy (this should work now with the role)
        bytes32 opDeposit = keccak256("DEPOSIT_OPERATION");
        strategy.callStrategyToken(abi.encodeCall(tRWA.addOperationHook, (opDeposit, address(newHook))));

        // Verify hook was added - one way to test is to check if the operation succeeds
        // If the hook was not added correctly, the operation would fail
        vm.stopPrank();

        // Create a separate test for the actual callStrategyToken function
        testCallStrategyTokenDirectly();
    }

    function testCallStrategyTokenDirectly() public {
        vm.startPrank(owner);

        // Get initial token balance
        uint256 initialBalance = token.totalAssets();

        // Call a safe known function on the token
        strategy.callStrategyToken(abi.encodeCall(token.name, ()));

        // Verify state is unchanged
        assertEq(token.totalAssets(), initialBalance, "Token balance should be unchanged");

        vm.stopPrank();
    }

    /**
     * @notice Test callStrategyToken when call fails (line 170)
     * @dev Tests the revert case in callStrategyToken
     */
    function test_CallStrategyToken_Reverts() public {
        // Create calldata that will cause the token to revert
        // Trying to call a non-existent function
        bytes memory invalidCalldata = abi.encodeWithSignature("nonExistentFunction()");

        // Attempt the call as admin
        vm.prank(owner);
        vm.expectRevert(); // low-level solidity error
        strategy.callStrategyToken(invalidCalldata);
    }

    /**
     * @notice Test callStrategyToken with a call that returns data but fails
     * @dev Tests the CallRevert error with return data
     */
    function test_CallStrategyToken_RevertsWithData() public {
        // Create calldata that will fail with a specific error
        // Try to transfer from the strategy without approval
        bytes memory invalidCalldata =
            abi.encodeWithSignature("transferFrom(address,address,uint256)", address(strategy), alice, 100e18);

        // Attempt the call as admin
        vm.prank(owner);
        vm.expectRevert(); // low-level solidity error
        strategy.callStrategyToken(invalidCalldata);
    }
}
