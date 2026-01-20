// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IReporter} from "./IReporter.sol";
import {Ownable} from "solady/auth/Ownable.sol";

/**
 * @title SimpleOracleReporter
 * @notice A reporter contract that allows a trusted party to report the price per share of the strategy
 */
contract SimpleOracleReporter is IReporter, Ownable {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidSource();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event PricePerShareUpdated(uint256 roundNumber, uint256 pricePerShare, string source);
    event SetUpdater(address indexed updater, bool isAuthorized);

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Current round number
    uint256 public currentRound;

    /// @notice The current price per share (in wei, 18 decimals)
    uint256 public pricePerShare;

    /// @notice The timestamp of the last update
    uint256 public lastUpdateAt;

    /// @notice Mapping of authorized updaters
    mapping(address => bool) public authorizedUpdaters;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Contract constructor
     * @param initialPricePerShare Initial price per share to report (18 decimals)
     */
    constructor(uint256 initialPricePerShare, address updater) {
        _initializeOwner(msg.sender);
        authorizedUpdaters[updater] = true;

        currentRound = 1;
        pricePerShare = initialPricePerShare;
        lastUpdateAt = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                            REPORTING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update the reported price per share
     * @param newPricePerShare The new price per share to report (18 decimals)
     * @param source_ The source of the price update
     */
    function update(uint256 newPricePerShare, string calldata source_) external {
        if (!authorizedUpdaters[msg.sender]) revert Unauthorized();
        if (bytes(source_).length == 0) revert InvalidSource();

        // Cache currentRound to memory and increment
        uint256 newRound = currentRound + 1;
        currentRound = newRound;
        pricePerShare = newPricePerShare;
        lastUpdateAt = block.timestamp;

        emit PricePerShareUpdated(newRound, newPricePerShare, source_);
    }

    /**
     * @notice Report the current price per share
     * @return The encoded current price per share
     */
    function report() external view override returns (bytes memory) {
        return abi.encode(pricePerShare);
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
}
