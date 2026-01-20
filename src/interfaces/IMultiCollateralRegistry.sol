// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

/**
 * @title IMultiCollateralRegistry
 * @notice Interface for the multi-collateral registry
 */
interface IMultiCollateralRegistry {
    /**
     * @notice Get the SovaBTC token address
     * @return The SovaBTC token address
     */
    function sovaBTC() external view returns (address);

    /**
     * @notice Check if a token is allowed as collateral
     * @param token The token to check
     * @return Whether the token is allowed
     */
    function isAllowedCollateral(address token) external view returns (bool);

    /**
     * @notice Convert collateral amount to SovaBTC value
     * @param token The collateral token
     * @param amount The amount of collateral
     * @return The equivalent SovaBTC value (8 decimals)
     */
    function convertToSovaBTC(address token, uint256 amount) external view returns (uint256);

    /**
     * @notice Convert SovaBTC value to collateral amount
     * @param token The collateral token
     * @param sovaBTCAmount The SovaBTC amount (8 decimals)
     * @return The equivalent collateral amount
     */
    function convertFromSovaBTC(address token, uint256 sovaBTCAmount) external view returns (uint256);

    /**
     * @notice Get all allowed collateral tokens
     * @return Array of collateral token addresses
     */
    function getAllCollateralTokens() external view returns (address[] memory);

    /**
     * @notice Get the conversion rate for a collateral token
     * @param token The collateral token
     * @return The conversion rate to SovaBTC (18 decimals)
     */
    function collateralToSovaBTCRate(address token) external view returns (uint256);

    /**
     * @notice Get the decimals for a collateral token
     * @param token The collateral token
     * @return The token decimals
     */
    function collateralDecimals(address token) external view returns (uint8);
}
