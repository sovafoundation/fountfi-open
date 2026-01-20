// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IStrategy} from "../strategy/IStrategy.sol";

/**
 * @title IMultiCollateralStrategy
 * @notice Interface for strategies that support multiple collateral types
 */
interface IMultiCollateralStrategy is IStrategy {
    /**
     * @notice Get the collateral registry address
     * @return The address of the MultiCollateralRegistry
     */
    function collateralRegistry() external view returns (address);

    /**
     * @notice Deposit collateral tokens into the strategy
     * @param token The collateral token to deposit
     * @param amount The amount to deposit
     */
    function depositCollateral(address token, uint256 amount) external;

    /**
     * @notice Get the balance of a specific collateral token
     * @param token The collateral token address
     * @return The balance of the specified collateral
     */
    function collateralBalances(address token) external view returns (uint256);

    /**
     * @notice Get the total value of all collateral in SovaBTC terms
     * @return The total value in SovaBTC (8 decimals)
     */
    function totalCollateralValue() external view returns (uint256);

    /**
     * @notice Deposit SovaBTC for redemptions (manager only)
     * @param amount The amount of SovaBTC to deposit
     */
    function depositRedemptionFunds(uint256 amount) external;
}
