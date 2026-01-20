// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IReporter} from "../reporter/IReporter.sol";

/**
 * @title MockReporter
 * @notice A simple reporter implementation for testing
 */
contract MockReporter is IReporter {
    uint256 private _value;

    constructor(uint256 initialValue) {
        _value = initialValue;
    }

    /**
     * @notice Set a new value for the reporter
     * @param newValue The new value to report
     */
    function setValue(uint256 newValue) external {
        _value = newValue;
    }

    /**
     * @notice Report the current value
     * @return The encoded current value
     */
    function report() external view override returns (bytes memory) {
        return abi.encode(_value);
    }
}
