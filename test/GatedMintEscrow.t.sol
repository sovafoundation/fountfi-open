// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {BaseFountfiTest} from "./BaseFountfiTest.t.sol";
import {GatedMintEscrow} from "../src/strategy/GatedMintEscrow.sol";
import {GatedMintRWA} from "../src/token/GatedMintRWA.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockStrategy} from "../src/mocks/MockStrategy.sol";

/**
 * @title GatedMintEscrowTest
 * @notice Comprehensive tests for GatedMintEscrow contract to achieve 100% coverage
 */
contract GatedMintEscrowTest is BaseFountfiTest {
    GatedMintEscrow internal escrow;
    GatedMintRWA internal gatedToken;
    MockStrategy internal strategy;

    // Test constants
    uint256 internal constant DEPOSIT_AMOUNT = 1000 * 10 ** 6; // 1000 USDC
    uint256 internal constant EXPIRATION_TIME = 7 days;

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);

        // Deploy strategy
        strategy = new MockStrategy();
        strategy.initialize("Gated RWA", "GRWA", owner, manager, address(usdc), 6, "");

        // Deploy GatedMintRWA token
        gatedToken = new GatedMintRWA("Gated RWA", "GRWA", address(usdc), 6, address(strategy));

        // Get the escrow from the token
        escrow = GatedMintEscrow(gatedToken.escrow());

        // Fund accounts
        usdc.mint(address(escrow), DEPOSIT_AMOUNT * 10);
        usdc.mint(alice, DEPOSIT_AMOUNT * 10);
        usdc.mint(bob, DEPOSIT_AMOUNT * 10);

        vm.stopPrank();
    }

    // ============ Constructor Tests ============

    function test_Constructor() public {
        // Test successful construction
        GatedMintEscrow newEscrow = new GatedMintEscrow(address(gatedToken), address(usdc), address(strategy));

        assertEq(newEscrow.token(), address(gatedToken));
        assertEq(newEscrow.asset(), address(usdc));
        assertEq(newEscrow.strategy(), address(strategy));
    }

    function test_Constructor_RevertZeroAddressToken() public {
        vm.expectRevert(GatedMintEscrow.InvalidAddress.selector);
        new GatedMintEscrow(address(0), address(usdc), address(strategy));
    }

    function test_Constructor_RevertZeroAddressAsset() public {
        vm.expectRevert(GatedMintEscrow.InvalidAddress.selector);
        new GatedMintEscrow(address(gatedToken), address(0), address(strategy));
    }

    function test_Constructor_RevertZeroAddressStrategy() public {
        vm.expectRevert(GatedMintEscrow.InvalidAddress.selector);
        new GatedMintEscrow(address(gatedToken), address(usdc), address(0));
    }

    // ============ Deposit Handling Tests ============

    function test_HandleDepositReceived() public {
        bytes32 depositId = keccak256("test_deposit");
        uint256 expirationTime = block.timestamp + EXPIRATION_TIME;

        vm.prank(address(gatedToken));
        escrow.handleDepositReceived(depositId, alice, bob, DEPOSIT_AMOUNT, expirationTime);

        // Verify deposit was stored
        GatedMintEscrow.PendingDeposit memory deposit = escrow.getPendingDeposit(depositId);
        assertEq(deposit.depositor, alice);
        assertEq(deposit.recipient, bob);
        assertEq(deposit.assetAmount, DEPOSIT_AMOUNT);
        assertEq(deposit.expirationTime, uint96(expirationTime));
        assertEq(uint8(deposit.state), 0); // PENDING

        // Verify accounting updates
        assertEq(escrow.totalPendingAssets(), DEPOSIT_AMOUNT);
        assertEq(escrow.userPendingAssets(alice), DEPOSIT_AMOUNT);
    }

    function test_HandleDepositReceived_UnauthorizedCaller() public {
        bytes32 depositId = keccak256("test_deposit");
        uint256 expirationTime = block.timestamp + EXPIRATION_TIME;

        vm.prank(alice);
        vm.expectRevert(GatedMintEscrow.Unauthorized.selector);
        escrow.handleDepositReceived(depositId, alice, bob, DEPOSIT_AMOUNT, expirationTime);
    }

    function test_HandleDepositReceived_EmitsEvent() public {
        bytes32 depositId = keccak256("test_deposit");
        uint256 expirationTime = block.timestamp + EXPIRATION_TIME;

        vm.prank(address(gatedToken));
        vm.expectEmit(true, true, true, true);
        emit GatedMintEscrow.DepositReceived(depositId, alice, bob, DEPOSIT_AMOUNT, expirationTime);

        escrow.handleDepositReceived(depositId, alice, bob, DEPOSIT_AMOUNT, expirationTime);
    }

    // ============ Single Deposit Operations ============

    function test_AcceptDeposit() public {
        // Setup deposit
        bytes32 depositId = _createTestDeposit(alice, bob, DEPOSIT_AMOUNT);

        vm.prank(address(strategy));
        vm.expectEmit(true, true, true, true);
        emit GatedMintEscrow.DepositAccepted(depositId, bob, DEPOSIT_AMOUNT);

        escrow.acceptDeposit(depositId);

        // Verify deposit state
        GatedMintEscrow.PendingDeposit memory deposit = escrow.getPendingDeposit(depositId);
        assertEq(uint8(deposit.state), 1); // ACCEPTED

        // Verify accounting updates
        assertEq(escrow.totalPendingAssets(), 0);
        assertEq(escrow.userPendingAssets(alice), 0);

        // Verify round increment
        assertEq(escrow.currentRound(), 1);
    }

    function test_AcceptDeposit_UnauthorizedCaller() public {
        bytes32 depositId = _createTestDeposit(alice, bob, DEPOSIT_AMOUNT);

        vm.prank(alice);
        vm.expectRevert(GatedMintEscrow.Unauthorized.selector);
        escrow.acceptDeposit(depositId);
    }

    function test_AcceptDeposit_DepositNotFound() public {
        bytes32 invalidDepositId = keccak256("invalid");

        vm.prank(address(strategy));
        vm.expectRevert(GatedMintEscrow.DepositNotFound.selector);
        escrow.acceptDeposit(invalidDepositId);
    }

    function test_AcceptDeposit_DepositNotPending() public {
        bytes32 depositId = _createTestDeposit(alice, bob, DEPOSIT_AMOUNT);

        // Accept deposit first time
        vm.prank(address(strategy));
        escrow.acceptDeposit(depositId);

        // Try to accept again
        vm.prank(address(strategy));
        vm.expectRevert(GatedMintEscrow.DepositNotPending.selector);
        escrow.acceptDeposit(depositId);
    }

    function test_RefundDeposit() public {
        bytes32 depositId = _createTestDeposit(alice, bob, DEPOSIT_AMOUNT);

        vm.prank(address(strategy));
        vm.expectEmit(true, true, true, true);
        emit GatedMintEscrow.DepositRefunded(depositId, alice, DEPOSIT_AMOUNT);

        escrow.refundDeposit(depositId);

        // Verify deposit state
        GatedMintEscrow.PendingDeposit memory deposit = escrow.getPendingDeposit(depositId);
        assertEq(uint8(deposit.state), 2); // REFUNDED

        // Verify accounting updates
        assertEq(escrow.totalPendingAssets(), 0);
        assertEq(escrow.userPendingAssets(alice), 0);
    }

    function test_RefundDeposit_UnauthorizedCaller() public {
        bytes32 depositId = _createTestDeposit(alice, bob, DEPOSIT_AMOUNT);

        vm.prank(alice);
        vm.expectRevert(GatedMintEscrow.Unauthorized.selector);
        escrow.refundDeposit(depositId);
    }

    function test_RefundDeposit_DepositNotFound() public {
        bytes32 invalidDepositId = keccak256("invalid");

        vm.prank(address(strategy));
        vm.expectRevert(GatedMintEscrow.DepositNotFound.selector);
        escrow.refundDeposit(invalidDepositId);
    }

    function test_RefundDeposit_DepositNotPending() public {
        bytes32 depositId = _createTestDeposit(alice, bob, DEPOSIT_AMOUNT);

        // Refund deposit first time
        vm.prank(address(strategy));
        escrow.refundDeposit(depositId);

        // Try to refund again
        vm.prank(address(strategy));
        vm.expectRevert(GatedMintEscrow.DepositNotPending.selector);
        escrow.refundDeposit(depositId);
    }

    // ============ Batch Operations ============

    function test_BatchAcceptDeposits() public {
        // Create multiple deposits
        bytes32[] memory depositIds = new bytes32[](3);
        depositIds[0] = _createTestDeposit(alice, alice, DEPOSIT_AMOUNT);
        depositIds[1] = _createTestDeposit(bob, bob, DEPOSIT_AMOUNT * 2);
        depositIds[2] = _createTestDeposit(charlie, charlie, DEPOSIT_AMOUNT / 2);

        uint256 totalExpected = DEPOSIT_AMOUNT + (DEPOSIT_AMOUNT * 2) + (DEPOSIT_AMOUNT / 2);

        vm.prank(address(strategy));
        vm.expectEmit(true, true, true, true);
        emit GatedMintEscrow.BatchDepositsAccepted(depositIds, totalExpected);

        escrow.batchAcceptDeposits(depositIds);

        // Verify all deposits are accepted
        for (uint256 i = 0; i < depositIds.length; i++) {
            GatedMintEscrow.PendingDeposit memory deposit = escrow.getPendingDeposit(depositIds[i]);
            assertEq(uint8(deposit.state), 1); // ACCEPTED
        }

        // Verify accounting
        assertEq(escrow.totalPendingAssets(), 0);
        assertEq(escrow.userPendingAssets(alice), 0);
        assertEq(escrow.userPendingAssets(bob), 0);
        assertEq(escrow.userPendingAssets(charlie), 0);

        // Verify round increment
        assertEq(escrow.currentRound(), 1);
    }

    function test_BatchAcceptDeposits_EmptyArray() public {
        bytes32[] memory emptyArray = new bytes32[](0);

        vm.prank(address(strategy));
        escrow.batchAcceptDeposits(emptyArray);

        // Should not revert and round should not increment
        assertEq(escrow.currentRound(), 0);
    }

    function test_BatchAcceptDeposits_UnauthorizedCaller() public {
        bytes32[] memory depositIds = new bytes32[](1);
        depositIds[0] = _createTestDeposit(alice, bob, DEPOSIT_AMOUNT);

        vm.prank(alice);
        vm.expectRevert(GatedMintEscrow.Unauthorized.selector);
        escrow.batchAcceptDeposits(depositIds);
    }

    function test_BatchRefundDeposits() public {
        // Create multiple deposits
        bytes32[] memory depositIds = new bytes32[](2);
        depositIds[0] = _createTestDeposit(alice, alice, DEPOSIT_AMOUNT);
        depositIds[1] = _createTestDeposit(bob, bob, DEPOSIT_AMOUNT * 2);

        uint256 totalExpected = DEPOSIT_AMOUNT + (DEPOSIT_AMOUNT * 2);

        vm.prank(address(strategy));
        vm.expectEmit(true, true, true, true);
        emit GatedMintEscrow.BatchDepositsRefunded(depositIds, totalExpected);

        escrow.batchRefundDeposits(depositIds);

        // Verify all deposits are refunded
        for (uint256 i = 0; i < depositIds.length; i++) {
            GatedMintEscrow.PendingDeposit memory deposit = escrow.getPendingDeposit(depositIds[i]);
            assertEq(uint8(deposit.state), 2); // REFUNDED
        }

        // Verify accounting
        assertEq(escrow.totalPendingAssets(), 0);
        assertEq(escrow.userPendingAssets(alice), 0);
        assertEq(escrow.userPendingAssets(bob), 0);
    }

    function test_BatchRefundDeposits_EmptyArray() public {
        bytes32[] memory emptyArray = new bytes32[](0);

        vm.prank(address(strategy));
        escrow.batchRefundDeposits(emptyArray);

        // Should not revert
        assertEq(escrow.totalPendingAssets(), 0);
    }

    function test_BatchRefundDeposits_UnauthorizedCaller() public {
        bytes32[] memory depositIds = new bytes32[](1);
        depositIds[0] = _createTestDeposit(alice, bob, DEPOSIT_AMOUNT);

        vm.prank(alice);
        vm.expectRevert(GatedMintEscrow.Unauthorized.selector);
        escrow.batchRefundDeposits(depositIds);
    }

    function test_BatchRefundDeposits_DepositNotFound() public {
        bytes32[] memory depositIds = new bytes32[](1);
        depositIds[0] = keccak256("invalid");

        vm.prank(address(strategy));
        vm.expectRevert(GatedMintEscrow.DepositNotFound.selector);
        escrow.batchRefundDeposits(depositIds);
    }

    function test_BatchRefundDeposits_DepositNotPending() public {
        bytes32[] memory depositIds = new bytes32[](1);
        depositIds[0] = _createTestDeposit(alice, bob, DEPOSIT_AMOUNT);

        // Refund first time
        vm.prank(address(strategy));
        escrow.batchRefundDeposits(depositIds);

        // Try to refund again
        vm.prank(address(strategy));
        vm.expectRevert(GatedMintEscrow.DepositNotPending.selector);
        escrow.batchRefundDeposits(depositIds);
    }

    // ============ User Reclaim Tests ============

    function test_ReclaimDeposit_AfterExpiration() public {
        bytes32 depositId = _createTestDepositWithExpiration(alice, bob, DEPOSIT_AMOUNT, block.timestamp + 1);

        // Fast forward past expiration
        vm.warp(block.timestamp + 2);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit GatedMintEscrow.DepositReclaimed(depositId, alice, DEPOSIT_AMOUNT);

        escrow.reclaimDeposit(depositId);

        // Verify deposit state
        GatedMintEscrow.PendingDeposit memory deposit = escrow.getPendingDeposit(depositId);
        assertEq(uint8(deposit.state), 2); // REFUNDED

        // Verify accounting
        assertEq(escrow.totalPendingAssets(), 0);
        assertEq(escrow.userPendingAssets(alice), 0);
    }

    function test_ReclaimDeposit_AfterRoundChange() public {
        bytes32 depositId = _createTestDepositWithExpiration(alice, bob, DEPOSIT_AMOUNT, block.timestamp + 1000);

        // Create and accept another deposit to increment round
        bytes32 otherDepositId = _createTestDeposit(charlie, charlie, DEPOSIT_AMOUNT);
        vm.prank(address(strategy));
        escrow.acceptDeposit(otherDepositId);

        // Now alice can reclaim even before expiration because round changed
        vm.prank(alice);
        escrow.reclaimDeposit(depositId);

        // Verify deposit state
        GatedMintEscrow.PendingDeposit memory deposit = escrow.getPendingDeposit(depositId);
        assertEq(uint8(deposit.state), 2); // REFUNDED
    }

    function test_ReclaimDeposit_UnauthorizedUser() public {
        bytes32 depositId = _createTestDeposit(alice, bob, DEPOSIT_AMOUNT);

        vm.prank(bob); // Bob tries to reclaim Alice's deposit
        vm.expectRevert(GatedMintEscrow.Unauthorized.selector);
        escrow.reclaimDeposit(depositId);
    }

    function test_ReclaimDeposit_DepositNotFound() public {
        bytes32 invalidDepositId = keccak256("invalid");

        vm.prank(alice);
        vm.expectRevert(GatedMintEscrow.DepositNotFound.selector);
        escrow.reclaimDeposit(invalidDepositId);
    }

    function test_ReclaimDeposit_DepositNotPending() public {
        bytes32 depositId = _createTestDeposit(alice, bob, DEPOSIT_AMOUNT);

        // Accept deposit first
        vm.prank(address(strategy));
        escrow.acceptDeposit(depositId);

        // Try to reclaim accepted deposit
        vm.prank(alice);
        vm.expectRevert(GatedMintEscrow.DepositNotPending.selector);
        escrow.reclaimDeposit(depositId);
    }

    function test_ReclaimDeposit_BeforeExpirationSameRound() public {
        bytes32 depositId = _createTestDepositWithExpiration(alice, bob, DEPOSIT_AMOUNT, block.timestamp + 1000);

        // Try to reclaim before expiration and round hasn't changed
        vm.prank(alice);
        vm.expectRevert(GatedMintEscrow.Unauthorized.selector);
        escrow.reclaimDeposit(depositId);
    }

    // ============ View Function Tests ============

    function test_GetPendingDeposit() public {
        bytes32 depositId = _createTestDeposit(alice, bob, DEPOSIT_AMOUNT);

        GatedMintEscrow.PendingDeposit memory deposit = escrow.getPendingDeposit(depositId);
        assertEq(deposit.depositor, alice);
        assertEq(deposit.recipient, bob);
        assertEq(deposit.assetAmount, DEPOSIT_AMOUNT);
        assertEq(uint8(deposit.state), 0); // PENDING
    }

    function test_GetPendingDeposit_NonExistent() public view {
        bytes32 invalidDepositId = keccak256("invalid");

        GatedMintEscrow.PendingDeposit memory deposit = escrow.getPendingDeposit(invalidDepositId);
        assertEq(deposit.depositor, address(0));
        assertEq(deposit.recipient, address(0));
        assertEq(deposit.assetAmount, 0);
    }

    // ============ Accounting Tests ============

    function test_MultipleDepositsAccounting() public {
        // Create multiple deposits from same user
        bytes32 deposit1 = _createTestDeposit(alice, alice, DEPOSIT_AMOUNT);
        bytes32 deposit2 = _createTestDeposit(alice, bob, DEPOSIT_AMOUNT * 2);

        // Verify cumulative accounting
        assertEq(escrow.totalPendingAssets(), DEPOSIT_AMOUNT * 3);
        assertEq(escrow.userPendingAssets(alice), DEPOSIT_AMOUNT * 3);

        // Accept one deposit
        vm.prank(address(strategy));
        escrow.acceptDeposit(deposit1);

        // Verify updated accounting
        assertEq(escrow.totalPendingAssets(), DEPOSIT_AMOUNT * 2);
        assertEq(escrow.userPendingAssets(alice), DEPOSIT_AMOUNT * 2);

        // Refund other deposit
        vm.prank(address(strategy));
        escrow.refundDeposit(deposit2);

        // Verify final accounting
        assertEq(escrow.totalPendingAssets(), 0);
        assertEq(escrow.userPendingAssets(alice), 0);
    }

    // ============ Additional Coverage Tests ============

    function test_BatchAcceptDeposits_DepositNotFound() public {
        bytes32[] memory depositIds = new bytes32[](2);
        depositIds[0] = _createTestDeposit(alice, bob, DEPOSIT_AMOUNT);
        depositIds[1] = keccak256("invalid"); // Invalid deposit ID

        vm.prank(address(strategy));
        vm.expectRevert(GatedMintEscrow.DepositNotFound.selector);
        escrow.batchAcceptDeposits(depositIds);
    }

    function test_BatchAcceptDeposits_DepositNotPending() public {
        bytes32[] memory depositIds = new bytes32[](2);
        depositIds[0] = _createTestDeposit(alice, bob, DEPOSIT_AMOUNT);
        depositIds[1] = _createTestDeposit(charlie, charlie, DEPOSIT_AMOUNT);

        // Accept second deposit individually first
        vm.prank(address(strategy));
        escrow.acceptDeposit(depositIds[1]);

        // Now try to batch accept including the already accepted deposit
        vm.prank(address(strategy));
        vm.expectRevert(GatedMintEscrow.DepositNotPending.selector);
        escrow.batchAcceptDeposits(depositIds);
    }

    function test_ReclaimDeposit_ExactExpirationTime() public {
        uint256 expirationTime = block.timestamp + 100;
        bytes32 depositId = _createTestDepositWithExpiration(alice, bob, DEPOSIT_AMOUNT, expirationTime);

        // Warp to exact expiration time
        vm.warp(expirationTime);

        vm.prank(alice);
        escrow.reclaimDeposit(depositId);

        // Verify deposit state
        GatedMintEscrow.PendingDeposit memory deposit = escrow.getPendingDeposit(depositId);
        assertEq(uint8(deposit.state), 2); // REFUNDED
    }

    // ============ Helper Functions ============

    function _createTestDeposit(address depositor, address recipient, uint256 amount) internal returns (bytes32) {
        return _createTestDepositWithExpiration(depositor, recipient, amount, block.timestamp + EXPIRATION_TIME);
    }

    function _createTestDepositWithExpiration(
        address depositor,
        address recipient,
        uint256 amount,
        uint256 expirationTime
    ) internal returns (bytes32) {
        bytes32 depositId = keccak256(abi.encodePacked(depositor, recipient, amount, block.timestamp));

        vm.prank(address(gatedToken));
        escrow.handleDepositReceived(depositId, depositor, recipient, amount, expirationTime);

        return depositId;
    }
}
