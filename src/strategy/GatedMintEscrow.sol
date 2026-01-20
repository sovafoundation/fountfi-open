// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {GatedMintRWA} from "../token/GatedMintRWA.sol";

/**
 * @title GatedMintEscrow
 * @notice Contract to hold assets during the two-phase deposit process
 * @dev Deployed alongside each GatedMintRWA token to manage pending deposits
 */
contract GatedMintEscrow {
    using SafeTransferLib for address;

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized();
    error DepositNotFound();
    error DepositNotPending();
    error InvalidAddress();
    error InvalidArrayLengths();
    error BatchFailed();

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event DepositReceived(
        bytes32 indexed depositId,
        address indexed depositor,
        address indexed recipient,
        uint256 assets,
        uint256 expirationTime
    );

    event DepositAccepted(bytes32 indexed depositId, address indexed recipient, uint256 assets);
    event DepositRefunded(bytes32 indexed depositId, address indexed depositor, uint256 assets);
    event DepositReclaimed(bytes32 indexed depositId, address indexed depositor, uint256 assets);
    event BatchDepositsAccepted(bytes32[] depositIds, uint256 totalAssets);
    event BatchDepositsRefunded(bytes32[] depositIds, uint256 totalAssets);

    /*//////////////////////////////////////////////////////////////
                            STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Enum to track the deposit state
    enum DepositState {
        PENDING,
        ACCEPTED,
        REFUNDED
    }

    /// @notice Struct to track pending deposit information
    struct PendingDeposit {
        address depositor; // Address that initiated the deposit
        address recipient; // Address that will receive shares if approved
        uint256 assetAmount; // Amount of assets deposited
        uint96 expirationTime; // Timestamp after which deposit can be reclaimed
        uint96 atRound; // Round number at which the deposit was received
        DepositState state; // Current state of the deposit
    }

    /// @notice The GatedMintRWA token address
    address public immutable token;
    /// @notice The underlying asset address
    address public immutable asset;
    /// @notice The strategy contract address
    address public immutable strategy;

    /// @notice Storage for deposits
    mapping(bytes32 => PendingDeposit) public pendingDeposits;

    /// @notice Accounting for total amounts
    uint256 public totalPendingAssets;
    /// @notice Accounting for user pending assets
    mapping(address => uint256) public userPendingAssets;

    /// @notice Tracking of batch acceptances
    uint96 public currentRound;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructor
     * @param _token The GatedMintRWA token address
     * @param _asset The underlying asset address
     * @param _strategy The strategy contract address
     */
    constructor(address _token, address _asset, address _strategy) {
        if (_token == address(0)) revert InvalidAddress();
        if (_asset == address(0)) revert InvalidAddress();
        if (_strategy == address(0)) revert InvalidAddress();

        token = _token;
        asset = _asset;
        strategy = _strategy;
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Receive a deposit from the GatedMintRWA token
     * @param depositId Unique identifier for the deposit
     * @param depositor Address that initiated the deposit
     * @param recipient Address that will receive shares if approved
     * @param amount Amount of assets deposited
     * @param expirationTime Time after which deposit can be reclaimed
     */
    function handleDepositReceived(
        bytes32 depositId,
        address depositor,
        address recipient,
        uint256 amount,
        uint256 expirationTime
    ) external {
        // Only GatedMintRWA token can call this function
        if (msg.sender != token) revert Unauthorized();

        // Store the deposit data
        pendingDeposits[depositId] = PendingDeposit({
            depositor: depositor,
            recipient: recipient,
            assetAmount: amount,
            expirationTime: uint96(expirationTime),
            state: DepositState.PENDING,
            atRound: currentRound
        });

        // Update accounting
        totalPendingAssets += amount;
        userPendingAssets[depositor] += amount;

        emit DepositReceived(depositId, depositor, recipient, amount, expirationTime);
    }

    /**
     * @notice Accept a pending deposit
     * @param depositId The deposit ID to accept
     */
    function acceptDeposit(bytes32 depositId) external {
        // Only strategy can call this function
        if (msg.sender != strategy) revert Unauthorized();

        PendingDeposit storage deposit = pendingDeposits[depositId];
        if (deposit.depositor == address(0)) revert DepositNotFound();
        if (deposit.state != DepositState.PENDING) revert DepositNotPending();

        // Mark as accepted
        deposit.state = DepositState.ACCEPTED;

        // Update accounting
        totalPendingAssets -= deposit.assetAmount;
        userPendingAssets[deposit.depositor] -= deposit.assetAmount;

        // Increment the round number, even for a single deposit
        currentRound++;

        // Transfer assets to the strategy
        asset.safeTransfer(strategy, deposit.assetAmount);

        // Tell the GatedMintRWA token to mint shares
        GatedMintRWA(token).mintShares(deposit.recipient, deposit.assetAmount);

        emit DepositAccepted(depositId, deposit.recipient, deposit.assetAmount);
    }

    /**
     * @notice Accept multiple pending deposits as a batch with equal share accounting
     * @param depositIds Array of deposit IDs to accept
     */
    function batchAcceptDeposits(bytes32[] calldata depositIds) external {
        // Only strategy can call this function
        if (msg.sender != strategy) revert Unauthorized();

        // Skip empty arrays
        if (depositIds.length == 0) return;

        uint256 totalBatchAssets = 0;

        address[] memory recipients = new address[](depositIds.length);
        uint256[] memory assetAmounts = new uint256[](depositIds.length);

        // First pass: validate all deposits and collect information
        for (uint256 i = 0; i < depositIds.length;) {
            bytes32 depositId = depositIds[i];
            PendingDeposit storage deposit = pendingDeposits[depositId];

            // Validate deposit
            if (deposit.depositor == address(0)) revert DepositNotFound();
            if (deposit.state != DepositState.PENDING) revert DepositNotPending();

            // Mark as accepted
            deposit.state = DepositState.ACCEPTED;

            // Accumulate total assets and store recipient and asset amount
            totalBatchAssets += deposit.assetAmount;
            userPendingAssets[deposit.depositor] -= deposit.assetAmount;

            recipients[i] = deposit.recipient;
            assetAmounts[i] = deposit.assetAmount;

            unchecked {
                ++i;
            }
        }

        totalPendingAssets -= totalBatchAssets;

        // Increment the round number
        currentRound++;

        // Transfer all assets to the strategy in one transaction
        asset.safeTransfer(strategy, totalBatchAssets);

        // Tell the GatedMintRWA token to mint shares for all deposits with equal treatment
        GatedMintRWA(token).batchMintShares(recipients, assetAmounts, totalBatchAssets);

        emit BatchDepositsAccepted(depositIds, totalBatchAssets);
    }

    /**
     * @notice Refund a pending deposit
     * @param depositId The deposit ID to refund
     */
    function refundDeposit(bytes32 depositId) external {
        // Only strategy can call this function
        if (msg.sender != strategy) revert Unauthorized();

        PendingDeposit storage deposit = pendingDeposits[depositId];
        if (deposit.depositor == address(0)) revert DepositNotFound();
        if (deposit.state != DepositState.PENDING) revert DepositNotPending();

        // Mark as refunded
        deposit.state = DepositState.REFUNDED;

        // Update accounting
        totalPendingAssets -= deposit.assetAmount;
        userPendingAssets[deposit.depositor] -= deposit.assetAmount;

        // Return assets to the depositor
        asset.safeTransfer(deposit.depositor, deposit.assetAmount);

        emit DepositRefunded(depositId, deposit.depositor, deposit.assetAmount);
    }

    /**
     * @notice Refund multiple pending deposits in a batch
     * @param depositIds Array of deposit IDs to refund
     */
    function batchRefundDeposits(bytes32[] calldata depositIds) external {
        // Only strategy can call this function
        if (msg.sender != strategy) revert Unauthorized();

        // Skip empty arrays
        if (depositIds.length == 0) return;

        uint256 totalRefundedAssets = 0;

        // Process each deposit
        for (uint256 i = 0; i < depositIds.length;) {
            bytes32 depositId = depositIds[i];
            PendingDeposit storage deposit = pendingDeposits[depositId];

            // Validate deposit
            if (deposit.depositor == address(0)) revert DepositNotFound();
            if (deposit.state != DepositState.PENDING) revert DepositNotPending();

            // Mark as refunded
            deposit.state = DepositState.REFUNDED;
            userPendingAssets[deposit.depositor] -= deposit.assetAmount;
            totalRefundedAssets += deposit.assetAmount;

            // Return assets to the depositor (individual transfers for each depositor)
            asset.safeTransfer(deposit.depositor, deposit.assetAmount);

            // Emit individual refund event
            emit DepositRefunded(depositId, deposit.depositor, deposit.assetAmount);

            unchecked {
                ++i;
            }
        }

        // Update accounting
        totalPendingAssets -= totalRefundedAssets;

        // Emit batch event
        emit BatchDepositsRefunded(depositIds, totalRefundedAssets);
    }

    /**
     * @notice Allow a user to reclaim their expired deposit
     * @param depositId The deposit ID to reclaim
     */
    function reclaimDeposit(bytes32 depositId) external {
        PendingDeposit storage deposit = pendingDeposits[depositId];
        if (deposit.depositor == address(0)) revert DepositNotFound();
        if (deposit.state != DepositState.PENDING) revert DepositNotPending();
        if (msg.sender != deposit.depositor) revert Unauthorized();

        // Allow reclamation if round has passed without acceptance
        if (block.timestamp < deposit.expirationTime && deposit.atRound == currentRound) revert Unauthorized();

        // Mark as refunded
        deposit.state = DepositState.REFUNDED;

        // Update accounting
        totalPendingAssets -= deposit.assetAmount;
        userPendingAssets[deposit.depositor] -= deposit.assetAmount;

        // Return assets to the depositor
        asset.safeTransfer(deposit.depositor, deposit.assetAmount);

        emit DepositReclaimed(depositId, deposit.depositor, deposit.assetAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the details of a pending deposit
     * @param depositId The deposit ID
     * @return The deposit details
     */
    function getPendingDeposit(bytes32 depositId) external view returns (PendingDeposit memory) {
        return pendingDeposits[depositId];
    }
}
