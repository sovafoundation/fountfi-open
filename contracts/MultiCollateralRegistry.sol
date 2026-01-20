// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {RoleManaged} from "../src/auth/RoleManaged.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

/**
 * @title MultiCollateralRegistry
 * @notice Registry for managing multiple collateral types and their conversion rates to SovaBTC
 * @dev This contract is designed to be a minimal addition to the FountFi protocol
 */
contract MultiCollateralRegistry is RoleManaged {
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidCollateral();
    error InvalidRate();
    error CollateralNotAllowed();

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event CollateralAdded(address indexed token, uint256 rate, uint8 decimals);
    event CollateralRemoved(address indexed token);
    event RateUpdated(address indexed token, uint256 oldRate, uint256 newRate);

    /*//////////////////////////////////////////////////////////////
                            STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice The SovaBTC token address
    address public immutable sovaBTC;

    /// @notice Mapping of collateral token to whether it's allowed
    mapping(address => bool) public allowedCollateral;

    /// @notice Mapping of collateral token to its conversion rate to SovaBTC (18 decimals)
    mapping(address => uint256) public collateralToSovaBTCRate;

    /// @notice Mapping of collateral token to its decimals
    mapping(address => uint8) public collateralDecimals;

    /// @notice Array of all allowed collateral tokens
    address[] public collateralTokens;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructor
     * @param _roleManager Address of the role manager
     * @param _sovaBTC Address of the SovaBTC token
     */
    constructor(address _roleManager, address _sovaBTC) RoleManaged(_roleManager) {
        if (_sovaBTC == address(0)) revert InvalidCollateral();
        sovaBTC = _sovaBTC;
    }

    /*//////////////////////////////////////////////////////////////
                        COLLATERAL MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add a new collateral token
     * @param token The collateral token address
     * @param rate The conversion rate to SovaBTC (18 decimals)
     * @param decimals The decimals of the collateral token
     */
    function addCollateral(
        address token,
        uint256 rate,
        uint8 decimals
    ) external onlyRoles(roleManager.PROTOCOL_ADMIN()) {
        if (token == address(0)) revert InvalidCollateral();
        if (rate == 0) revert InvalidRate();
        if (allowedCollateral[token]) revert InvalidCollateral();

        allowedCollateral[token] = true;
        collateralToSovaBTCRate[token] = rate;
        collateralDecimals[token] = decimals;
        collateralTokens.push(token);

        emit CollateralAdded(token, rate, decimals);
    }

    /**
     * @notice Remove a collateral token
     * @param token The collateral token address
     */
    function removeCollateral(address token) external onlyRoles(roleManager.PROTOCOL_ADMIN()) {
        if (!allowedCollateral[token]) revert CollateralNotAllowed();

        allowedCollateral[token] = false;
        delete collateralToSovaBTCRate[token];
        delete collateralDecimals[token];

        // Remove from array
        uint256 length = collateralTokens.length;
        for (uint256 i = 0; i < length; i++) {
            if (collateralTokens[i] == token) {
                collateralTokens[i] = collateralTokens[length - 1];
                collateralTokens.pop();
                break;
            }
        }

        emit CollateralRemoved(token);
    }

    /**
     * @notice Update the conversion rate for a collateral token
     * @param token The collateral token address
     * @param newRate The new conversion rate (18 decimals)
     */
    function updateRate(
        address token,
        uint256 newRate
    ) external onlyRoles(roleManager.PROTOCOL_ADMIN()) {
        if (!allowedCollateral[token]) revert CollateralNotAllowed();
        if (newRate == 0) revert InvalidRate();

        uint256 oldRate = collateralToSovaBTCRate[token];
        collateralToSovaBTCRate[token] = newRate;

        emit RateUpdated(token, oldRate, newRate);
    }

    /*//////////////////////////////////////////////////////////////
                        CONVERSION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Convert collateral amount to SovaBTC value
     * @param token The collateral token
     * @param amount The amount of collateral
     * @return The equivalent SovaBTC value (8 decimals)
     */
    function convertToSovaBTC(address token, uint256 amount) public view returns (uint256) {
        if (!allowedCollateral[token]) revert CollateralNotAllowed();

        // Special case: SovaBTC to SovaBTC is always 1:1
        if (token == sovaBTC) {
            return amount;
        }

        uint256 rate = collateralToSovaBTCRate[token];
        uint8 tokenDecimals = collateralDecimals[token];

        // Convert to 18 decimals, apply rate, then scale to 8 decimals (SovaBTC decimals)
        // amount * rate / 10^(18 + tokenDecimals - 8)
        uint256 scalingFactor = 10 ** (18 + tokenDecimals - 8);
        return amount.mulDiv(rate, scalingFactor);
    }

    /**
     * @notice Convert SovaBTC value to collateral amount
     * @param token The collateral token
     * @param sovaBTCAmount The SovaBTC amount (8 decimals)
     * @return The equivalent collateral amount
     */
    function convertFromSovaBTC(address token, uint256 sovaBTCAmount) public view returns (uint256) {
        if (!allowedCollateral[token]) revert CollateralNotAllowed();

        uint256 rate = collateralToSovaBTCRate[token];
        uint8 tokenDecimals = collateralDecimals[token];

        // Scale SovaBTC to collateral decimals
        // sovaBTCAmount * 10^(18 + tokenDecimals - 8) / rate
        uint256 scalingFactor = 10 ** (18 + tokenDecimals - 8);
        return sovaBTCAmount.mulDiv(scalingFactor, rate);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get all allowed collateral tokens
     * @return Array of collateral token addresses
     */
    function getAllCollateralTokens() external view returns (address[] memory) {
        return collateralTokens;
    }

    /**
     * @notice Get the number of allowed collateral tokens
     * @return The count of collateral tokens
     */
    function getCollateralTokenCount() external view returns (uint256) {
        return collateralTokens.length;
    }

    /**
     * @notice Check if a token is allowed as collateral
     * @param token The token to check
     * @return Whether the token is allowed
     */
    function isAllowedCollateral(address token) external view returns (bool) {
        return allowedCollateral[token];
    }
}