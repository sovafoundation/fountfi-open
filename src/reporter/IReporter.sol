// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

/**
 * @title IReporter
 * @notice Interface for reporters that return strategy info
 */
interface IReporter {
    /*//////////////////////////////////////////////////////////////
                            FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Report the current value of an asset
     * @return the content of the report
     */
    function report() external view returns (bytes memory);
}
