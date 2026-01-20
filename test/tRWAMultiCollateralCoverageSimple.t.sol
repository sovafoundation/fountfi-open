// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {tRWA} from "../src/token/tRWA-multicollateral.sol";
import {ItRWA} from "../src/token/ItRWA.sol";
import {MultiCollateralRegistry} from "../contracts/MultiCollateralRegistry.sol";
import {SimpleMultiCollateralStrategy} from "../contracts/SimpleMultiCollateralStrategy.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {IHook} from "../src/hooks/IHook.sol";

// Simple mock hook for testing
contract SimpleMockHook is IHook {
    bool public shouldApprove;

    constructor(bool _shouldApprove) {
        shouldApprove = _shouldApprove;
    }

    function hookId() external pure override returns (bytes32) {
        return keccak256("SIMPLE_MOCK_HOOK");
    }

    function name() external pure override returns (string memory) {
        return "Simple Mock Hook";
    }

    function onBeforeDeposit(address, address, uint256, address) external view override returns (HookOutput memory) {
        return HookOutput(shouldApprove, shouldApprove ? "" : "Deposit rejected");
    }

    function onBeforeWithdraw(address, address, uint256, address, address)
        external
        view
        override
        returns (HookOutput memory)
    {
        return HookOutput(shouldApprove, shouldApprove ? "" : "Withdraw rejected");
    }

    function onBeforeTransfer(address, address, address, uint256) external view override returns (HookOutput memory) {
        return HookOutput(shouldApprove, shouldApprove ? "" : "Transfer rejected");
    }
}

contract tRWAMultiCollateralCoverageSimpleTest is Test {
    tRWA public vault;
    MultiCollateralRegistry public multiRegistry;
    SimpleMultiCollateralStrategy public strategy;
    RoleManager public roleManager;

    address public admin = address(0x1);
    address public manager = address(0x2);
    address public user = address(0x4);
    address public receiver = address(0x5);

    MockERC20 public sovaBTC;
    MockERC20 public wbtc;
    MockERC20 public tbtc;

    function setUp() public {
        // Deploy role manager
        roleManager = new RoleManager();
        roleManager.grantRole(admin, roleManager.PROTOCOL_ADMIN());
        roleManager.grantRole(manager, roleManager.STRATEGY_ADMIN());

        // Deploy tokens first to avoid address collisions
        sovaBTC = new MockERC20("SovaBTC", "SBTC", 8);
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        tbtc = new MockERC20("tBTC", "TBTC", 18);

        // Deploy a dummy contract to shift addresses
        new MockERC20("Dummy", "DUMMY", 18);

        // Deploy multi-collateral registry
        multiRegistry = new MultiCollateralRegistry(address(roleManager), address(sovaBTC));

        // Add collaterals
        vm.startPrank(admin);
        multiRegistry.addCollateral(address(wbtc), 1e18, 8);
        multiRegistry.addCollateral(address(tbtc), 1e18, 18);
        multiRegistry.addCollateral(address(sovaBTC), 1e18, 8);
        vm.stopPrank();

        // Deploy strategy
        strategy = new SimpleMultiCollateralStrategy(address(sovaBTC), 8, address(multiRegistry), manager);

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

    // Test constructor edge cases
    function testConstructorInvalidDecimals() public {
        vm.expectRevert(tRWA.InvalidDecimals.selector);
        new tRWA(
            "Test Vault",
            "TEST",
            address(sovaBTC),
            19, // > 18
            address(strategy),
            address(sovaBTC)
        );
    }

    // Test view functions
    function testGetters() public view {
        assertEq(vault.name(), "Multi-Collateral Bitcoin Vault");
        assertEq(vault.symbol(), "mcBTC");
        assertEq(vault.asset(), address(sovaBTC));
        assertEq(vault.underlyingAsset(), address(sovaBTC));
        assertEq(vault.strategy(), address(strategy));
        assertEq(vault.sovaBTC(), address(sovaBTC));
        assertEq(vault.decimals(), 18);
        assertEq(vault.totalAssets(), 0);
    }

    // Test hook management
    function testAddOperationHook() public {
        SimpleMockHook hook = new SimpleMockHook(true);

        // Use startPrank/stopPrank instead of prank
        vm.startPrank(address(strategy));
        vault.addOperationHook(vault.OP_DEPOSIT(), address(hook));
        vm.stopPrank();

        address[] memory hooks = vault.getHooksForOperation(vault.OP_DEPOSIT());
        assertEq(hooks.length, 1);
        assertEq(hooks[0], address(hook));
    }

    function testAddOperationHookZeroAddress() public {
        bytes32 opDeposit = vault.OP_DEPOSIT(); // Get constant first

        vm.startPrank(address(strategy));
        vm.expectRevert(tRWA.HookAddressZero.selector);
        vault.addOperationHook(opDeposit, address(0));
        vm.stopPrank();
    }

    function testAddOperationHookNotStrategy() public {
        SimpleMockHook hook = new SimpleMockHook(true);
        bytes32 opDeposit = vault.OP_DEPOSIT(); // Get constant first

        vm.startPrank(user);
        vm.expectRevert(tRWA.NotStrategyAdmin.selector);
        vault.addOperationHook(opDeposit, address(hook));
        vm.stopPrank();
    }

    function testRemoveOperationHook() public {
        // Add a hook
        SimpleMockHook hook = new SimpleMockHook(true);
        vm.startPrank(address(strategy));
        vault.addOperationHook(vault.OP_DEPOSIT(), address(hook));

        // Remove it
        vault.removeOperationHook(vault.OP_DEPOSIT(), 0);
        vm.stopPrank();

        address[] memory hooks = vault.getHooksForOperation(vault.OP_DEPOSIT());
        assertEq(hooks.length, 0);
    }

    function testRemoveOperationHookOutOfBounds() public {
        bytes32 opDeposit = vault.OP_DEPOSIT();

        vm.startPrank(address(strategy));
        vm.expectRevert(tRWA.HookIndexOutOfBounds.selector);
        vault.removeOperationHook(opDeposit, 0);
        vm.stopPrank();
    }

    function testRemoveOperationHookSwapAndPop() public {
        // Add multiple hooks
        SimpleMockHook hook1 = new SimpleMockHook(true);
        SimpleMockHook hook2 = new SimpleMockHook(true);
        SimpleMockHook hook3 = new SimpleMockHook(true);

        vm.startPrank(address(strategy));
        vault.addOperationHook(vault.OP_DEPOSIT(), address(hook1));
        vault.addOperationHook(vault.OP_DEPOSIT(), address(hook2));
        vault.addOperationHook(vault.OP_DEPOSIT(), address(hook3));

        // Remove the middle one (index 1)
        vault.removeOperationHook(vault.OP_DEPOSIT(), 1);
        vm.stopPrank();

        address[] memory hooks = vault.getHooksForOperation(vault.OP_DEPOSIT());
        assertEq(hooks.length, 2);
        assertEq(hooks[0], address(hook1));
        assertEq(hooks[1], address(hook3)); // hook3 was moved to index 1
    }

    function testReorderOperationHooks() public {
        // Add multiple hooks
        SimpleMockHook hook1 = new SimpleMockHook(true);
        SimpleMockHook hook2 = new SimpleMockHook(true);
        SimpleMockHook hook3 = new SimpleMockHook(true);

        vm.startPrank(address(strategy));
        vault.addOperationHook(vault.OP_DEPOSIT(), address(hook1));
        vault.addOperationHook(vault.OP_DEPOSIT(), address(hook2));
        vault.addOperationHook(vault.OP_DEPOSIT(), address(hook3));

        // Reorder: [2, 0, 1] means new order will be [hook3, hook1, hook2]
        uint256[] memory newOrder = new uint256[](3);
        newOrder[0] = 2; // hook3 goes to position 0
        newOrder[1] = 0; // hook1 goes to position 1
        newOrder[2] = 1; // hook2 goes to position 2

        vault.reorderOperationHooks(vault.OP_DEPOSIT(), newOrder);
        vm.stopPrank();

        address[] memory hooks = vault.getHooksForOperation(vault.OP_DEPOSIT());
        assertEq(hooks[0], address(hook3));
        assertEq(hooks[1], address(hook1));
        assertEq(hooks[2], address(hook2));
    }

    function testReorderOperationHooksInvalidLength() public {
        // Add hooks
        SimpleMockHook hook1 = new SimpleMockHook(true);
        SimpleMockHook hook2 = new SimpleMockHook(true);

        vm.startPrank(address(strategy));
        vault.addOperationHook(vault.OP_DEPOSIT(), address(hook1));
        vault.addOperationHook(vault.OP_DEPOSIT(), address(hook2));

        // Try to reorder with wrong length
        uint256[] memory newOrder = new uint256[](1);
        newOrder[0] = 0;

        bytes32 opDeposit = vault.OP_DEPOSIT();
        vm.expectRevert(tRWA.ReorderInvalidLength.selector);
        vault.reorderOperationHooks(opDeposit, newOrder);
        vm.stopPrank();
    }

    function testReorderOperationHooksIndexOutOfBounds() public {
        // Add hooks
        SimpleMockHook hook1 = new SimpleMockHook(true);
        SimpleMockHook hook2 = new SimpleMockHook(true);

        vm.startPrank(address(strategy));
        vault.addOperationHook(vault.OP_DEPOSIT(), address(hook1));
        vault.addOperationHook(vault.OP_DEPOSIT(), address(hook2));

        // Try to reorder with out of bounds index
        uint256[] memory newOrder = new uint256[](2);
        newOrder[0] = 0;
        newOrder[1] = 5; // Out of bounds

        bytes32 opDeposit = vault.OP_DEPOSIT();
        vm.expectRevert(tRWA.ReorderIndexOutOfBounds.selector);
        vault.reorderOperationHooks(opDeposit, newOrder);
        vm.stopPrank();
    }

    function testReorderOperationHooksDuplicateIndex() public {
        // Add hooks
        SimpleMockHook hook1 = new SimpleMockHook(true);
        SimpleMockHook hook2 = new SimpleMockHook(true);

        vm.startPrank(address(strategy));
        vault.addOperationHook(vault.OP_DEPOSIT(), address(hook1));
        vault.addOperationHook(vault.OP_DEPOSIT(), address(hook2));

        // Try to reorder with duplicate index
        uint256[] memory newOrder = new uint256[](2);
        newOrder[0] = 0;
        newOrder[1] = 0; // Duplicate

        bytes32 opDeposit = vault.OP_DEPOSIT();
        vm.expectRevert(tRWA.ReorderDuplicateIndex.selector);
        vault.reorderOperationHooks(opDeposit, newOrder);
        vm.stopPrank();
    }

    // Test getHookInfoForOperation
    function testGetHookInfoForOperation() public {
        SimpleMockHook hook = new SimpleMockHook(true);

        vm.startPrank(address(strategy));
        vault.addOperationHook(vault.OP_DEPOSIT(), address(hook));
        vm.stopPrank();

        tRWA.HookInfo[] memory hookInfos = vault.getHookInfoForOperation(vault.OP_DEPOSIT());
        assertEq(hookInfos.length, 1);
        assertEq(address(hookInfos[0].hook), address(hook));
        assertEq(hookInfos[0].addedAtBlock, block.number);
    }

    // Test hook prevents removal after execution
    function testRemoveOperationHookAfterExecution() public {
        // Add a hook
        SimpleMockHook hook = new SimpleMockHook(true);
        vm.startPrank(address(strategy));
        vault.addOperationHook(vault.OP_TRANSFER(), address(hook));
        vm.stopPrank();

        // Execute a transfer (which uses the hook) by minting shares
        vm.startPrank(address(vault));
        vault.transfer(user, 0); // Transfer 0 to trigger hook
        vm.stopPrank();

        // Try to remove the hook (should fail)
        bytes32 opTransfer = vault.OP_TRANSFER();

        vm.startPrank(address(strategy));
        vm.expectRevert(tRWA.HookHasProcessedOperations.selector);
        vault.removeOperationHook(opTransfer, 0);
        vm.stopPrank();
    }

    // Test multiple hooks with rejection
    function testMultipleHooksWithRejection() public {
        // Create hooks with different messages
        SimpleMockHook hook1 = new SimpleMockHook(true);
        SimpleMockHook hook2 = new SimpleMockHook(true);
        SimpleMockHook hook3 = new SimpleMockHook(false); // This one rejects

        vm.startPrank(address(strategy));
        vault.addOperationHook(vault.OP_TRANSFER(), address(hook1));
        vault.addOperationHook(vault.OP_TRANSFER(), address(hook2));
        vault.addOperationHook(vault.OP_TRANSFER(), address(hook3));
        vm.stopPrank();

        // Try to transfer - should fail on hook3
        vm.prank(address(vault));
        vm.expectRevert(abi.encodeWithSelector(tRWA.HookCheckFailed.selector, "Transfer rejected"));
        vault.transfer(user, 0);
    }

    // Test depositCollateral function
    function testDepositCollateralWBTC() public {
        uint256 amount = 1e8;

        vm.startPrank(user);
        wbtc.approve(address(vault), amount);
        uint256 shares = vault.depositCollateral(address(wbtc), amount, user);
        vm.stopPrank();

        assertGt(shares, 0);
        assertEq(vault.balanceOf(user), shares);
        assertEq(strategy.collateralBalances(address(wbtc)), amount);
    }

    function testDepositCollateralWithHook() public {
        // Add a hook that approves
        SimpleMockHook approvedHook = new SimpleMockHook(true);
        vm.startPrank(address(strategy));
        vault.addOperationHook(vault.OP_DEPOSIT(), address(approvedHook));
        vm.stopPrank();

        uint256 amount = 1e8;

        vm.startPrank(user);
        wbtc.approve(address(vault), amount);
        uint256 shares = vault.depositCollateral(address(wbtc), amount, receiver);
        vm.stopPrank();

        assertGt(shares, 0);
        assertEq(vault.balanceOf(receiver), shares);
        assertEq(vault.lastExecutedBlock(vault.OP_DEPOSIT()), block.number);
    }

    function testDepositCollateralWithRejectedHook() public {
        // Add a hook that rejects
        SimpleMockHook rejectedHook = new SimpleMockHook(false);
        vm.startPrank(address(strategy));
        vault.addOperationHook(vault.OP_DEPOSIT(), address(rejectedHook));
        vm.stopPrank();

        uint256 amount = 1e8;

        vm.startPrank(user);
        wbtc.approve(address(vault), amount);
        vm.expectRevert(abi.encodeWithSelector(tRWA.HookCheckFailed.selector, "Deposit rejected"));
        vault.depositCollateral(address(wbtc), amount, user);
        vm.stopPrank();
    }

    // Test operation constants
    function testOperationConstants() public view {
        assertEq(vault.OP_DEPOSIT(), keccak256("DEPOSIT_OPERATION"));
        assertEq(vault.OP_WITHDRAW(), keccak256("WITHDRAW_OPERATION"));
        assertEq(vault.OP_TRANSFER(), keccak256("TRANSFER_OPERATION"));
    }

    // Test lastExecutedBlock mapping
    function testLastExecutedBlockMapping() public view {
        // Initially all should be 0
        assertEq(vault.lastExecutedBlock(vault.OP_DEPOSIT()), 0);
        assertEq(vault.lastExecutedBlock(vault.OP_WITHDRAW()), 0);
        assertEq(vault.lastExecutedBlock(vault.OP_TRANSFER()), 0);
    }
}
