// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/**
 * @title MockConduit
 * @notice Simple mock implementation of conduit for testing
 */
contract MockConduit {
    using SafeTransferLib for address;

    /**
     * @notice Simulates collecting deposits, just transfers tokens directly
     */
    function collectDeposit(address token, address from, address to, uint256 amount) external returns (bool) {
        token.safeTransferFrom(from, to, amount);
        return true;
    }
}
