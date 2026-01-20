// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {tRWA} from "../token/tRWA.sol";

/**
 * @title MocktRWA
 * @notice Mock tRWA token that implements burn for testing
 */
contract MocktRWA is tRWA {
    constructor(string memory name_, string memory symbol_, address asset_, uint8 assetDecimals_, address strategy_)
        tRWA(name_, symbol_, asset_, assetDecimals_, strategy_)
    {}

    /**
     * @notice Utility function to burn tokens - ONLY FOR TESTING
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
