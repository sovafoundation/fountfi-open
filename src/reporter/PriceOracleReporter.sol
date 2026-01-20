// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IReporter} from "./IReporter.sol";
import {Ownable} from "solady/auth/Ownable.sol";

/**
 * @title PriceOracleReporter
 * @notice A reporter contract that allows a trusted party to report the price per share of the strategy
 *         with gradual price transitions to prevent arbitrage opportunities
 */
contract PriceOracleReporter is IReporter, Ownable {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidSource();
    error InvalidMaxDeviation();
    error InvalidTimePeriod();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event ForceCompleteTransition(uint256 roundNumber, uint256 targetPricePerShare);
    event PricePerShareUpdated(
        uint256 roundNumber, uint256 targetPricePerShare, uint256 startPricePerShare, string source
    );
    event SetUpdater(address indexed updater, bool isAuthorized);
    event MaxDeviationUpdated(uint256 oldMaxDeviation, uint256 newMaxDeviation, uint256 timePeriod);

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Current round number
    uint256 public currentRound;

    /// @notice The target price per share that we're transitioning to
    uint256 public targetPricePerShare;

    /// @notice The price per share at the start of the current transition
    uint256 public transitionStartPrice;

    /// @notice The timestamp of the last update
    uint256 public lastUpdateAt;

    /// @notice Maximum percentage price change allowed per time period (in basis points, e.g., 100 = 1%)
    uint256 public maxDeviationPerTimePeriod;

    /// @notice Time period for max deviation (in seconds, e.g., 300 = 5 minutes)
    uint256 public deviationTimePeriod;

    /// @notice Tracks price changes that have been applied in current period (basis points)
    uint256 public appliedChangeInPeriod;

    /// @notice The timestamp when the current tracking period started
    uint256 public periodStartTime;

    /// @notice Mapping of authorized updaters
    mapping(address => bool) public authorizedUpdaters;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Contract constructor
     * @param initialPricePerShare Initial price per share to report (18 decimals)
     * @param updater Initial authorized updater address
     * @param _maxDeviationPerTimePeriod Maximum percentage change per time period (basis points)
     * @param _deviationTimePeriod Time period in seconds
     */
    constructor(
        uint256 initialPricePerShare,
        address updater,
        uint256 _maxDeviationPerTimePeriod,
        uint256 _deviationTimePeriod
    ) {
        _initializeOwner(msg.sender);
        authorizedUpdaters[updater] = true;

        if (_maxDeviationPerTimePeriod == 0) revert InvalidMaxDeviation();
        if (_deviationTimePeriod == 0) revert InvalidTimePeriod();

        currentRound = 1;
        targetPricePerShare = initialPricePerShare;
        transitionStartPrice = initialPricePerShare;
        lastUpdateAt = block.timestamp;
        periodStartTime = block.timestamp;

        maxDeviationPerTimePeriod = _maxDeviationPerTimePeriod;
        deviationTimePeriod = _deviationTimePeriod;
        appliedChangeInPeriod = 0;
    }

    /*//////////////////////////////////////////////////////////////
                            REPORTING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update the reported price per share with gradual transition
     * @dev If a transition is already in progress, it will stop the old transition and start a new one.
     * @param newTargetPricePerShare The new target price per share to transition to (18 decimals)
     * @param source_ The source of the price update
     */
    function update(uint256 newTargetPricePerShare, string calldata source_) external {
        if (!authorizedUpdaters[msg.sender]) revert Unauthorized();
        if (bytes(source_).length == 0) revert InvalidSource();

        // Update the current price based on the ongoing transition
        uint256 currentPrice = getCurrentPrice();

        uint256 newRound = currentRound + 1;
        currentRound = newRound;

        // Reset cumulative tracking if period expired
        if (block.timestamp >= periodStartTime + deviationTimePeriod) {
            periodStartTime = block.timestamp;
            appliedChangeInPeriod = 0;
        }

        // Calculate percentage change from current price
        uint256 changePercent = _calculateChangePercent(currentPrice, newTargetPricePerShare);

        // Check if this change plus previously applied changes would exceed period limit
        uint256 newCumulativeChange = appliedChangeInPeriod + changePercent;
        bool withinDeviation = newCumulativeChange <= maxDeviationPerTimePeriod;

        // Always update target and last update time
        targetPricePerShare = newTargetPricePerShare;
        lastUpdateAt = block.timestamp;

        if (withinDeviation) {
            // Direct update without transition
            transitionStartPrice = newTargetPricePerShare;
            appliedChangeInPeriod = newCumulativeChange;
        } else {
            // Set new target and restart transition from current price
            transitionStartPrice = currentPrice;
        }

        emit PricePerShareUpdated(newRound, newTargetPricePerShare, currentPrice, source_);
    }

    /**
     * @notice Report the current price per share
     * @return The encoded current price per share
     */
    function report() external view override returns (bytes memory) {
        return abi.encode(getCurrentPrice());
    }

    /**
     * @notice Calculate percentage change between two prices
     * @param fromPrice Starting price
     * @param toPrice Target price
     * @return Change percentage in basis points
     */
    function _calculateChangePercent(uint256 fromPrice, uint256 toPrice) private pure returns (uint256) {
        if (toPrice > fromPrice) {
            return ((toPrice - fromPrice) * 10000) / fromPrice;
        } else {
            return ((fromPrice - toPrice) * 10000) / fromPrice;
        }
    }

    /**
     * @notice Get the current price, accounting for gradual transitions
     * @return The current price per share
     */
    function getCurrentPrice() public view returns (uint256) {
        if (transitionStartPrice == targetPricePerShare) {
            return targetPricePerShare;
        }

        // Calculate fractional periods for continuous transitions (basis points precision)
        uint256 timeElapsed = block.timestamp - lastUpdateAt;
        uint256 fractionalPeriods = (timeElapsed * 10000) / deviationTimePeriod;
        uint256 maxAllowedChangePercent = (fractionalPeriods * maxDeviationPerTimePeriod) / 10000;

        // Calculate max allowed change from transition start
        uint256 maxAllowedChange = (transitionStartPrice * maxAllowedChangePercent) / 10000;

        // Apply the change in the correct direction
        if (targetPricePerShare > transitionStartPrice) {
            uint256 maxPrice = transitionStartPrice + maxAllowedChange;
            return maxPrice >= targetPricePerShare ? targetPricePerShare : maxPrice;
        } else {
            // Prevent underflow
            if (maxAllowedChange >= transitionStartPrice) {
                return targetPricePerShare;
            }
            uint256 minPrice = transitionStartPrice - maxAllowedChange;
            return minPrice <= targetPricePerShare ? targetPricePerShare : minPrice;
        }
    }

    /**
     * @notice Get the progress of the current price transition
     * @return percentComplete The completion percentage in basis points (0-10000)
     */
    function getTransitionProgress() external view returns (uint256 percentComplete) {
        if (transitionStartPrice == targetPricePerShare) {
            return 10000; // 100%
        }

        uint256 currentPrice = getCurrentPrice();
        if (currentPrice == targetPricePerShare) {
            return 10000;
        }

        // Calculate total change needed
        uint256 totalChange;
        uint256 progressChange;

        if (targetPricePerShare > transitionStartPrice) {
            totalChange = targetPricePerShare - transitionStartPrice;
            progressChange = currentPrice - transitionStartPrice;
        } else {
            totalChange = transitionStartPrice - targetPricePerShare;
            progressChange = transitionStartPrice - currentPrice;
        }

        return (progressChange * 10000) / totalChange;
    }

    /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set whether an address is authorized to update values
     * @param updater Address to modify authorization for
     * @param isAuthorized Whether the address should be authorized
     */
    function setUpdater(address updater, bool isAuthorized) external onlyOwner {
        authorizedUpdaters[updater] = isAuthorized;
        emit SetUpdater(updater, isAuthorized);
    }

    /**
     * @notice Update the maximum deviation parameters
     * @dev On calls to setMaxDeviation, the last deviation time period is considered to
     *      have ended, and a new period starts immediately.
     * @param _maxDeviationPerTimePeriod New maximum percentage change per time period (basis points)
     * @param _deviationTimePeriod New time period in seconds
     */
    function setMaxDeviation(uint256 _maxDeviationPerTimePeriod, uint256 _deviationTimePeriod) external onlyOwner {
        if (_maxDeviationPerTimePeriod == 0) revert InvalidMaxDeviation();
        if (_deviationTimePeriod == 0) revert InvalidTimePeriod();

        // Get current price before changing parameters
        uint256 currentPrice = getCurrentPrice();

        // Update rate limit
        uint256 oldMaxDeviation = maxDeviationPerTimePeriod;
        maxDeviationPerTimePeriod = _maxDeviationPerTimePeriod;
        deviationTimePeriod = _deviationTimePeriod;

        // If in transition, restart from current price to apply new rate
        if (currentPrice != targetPricePerShare) {
            transitionStartPrice = currentPrice;
            lastUpdateAt = block.timestamp;
        }

        // Reset cumulative tracking
        periodStartTime = block.timestamp;
        appliedChangeInPeriod = 0;

        emit MaxDeviationUpdated(oldMaxDeviation, _maxDeviationPerTimePeriod, _deviationTimePeriod);
    }

    /**
     * @notice Force complete the current price transition (emergency function)
     * @dev Only callable by owner
     */
    function forceCompleteTransition() external onlyOwner {
        transitionStartPrice = targetPricePerShare;
        lastUpdateAt = block.timestamp;

        emit ForceCompleteTransition(currentRound, targetPricePerShare);
    }
}
