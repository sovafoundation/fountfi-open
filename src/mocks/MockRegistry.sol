// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title MockRegistry
 * @notice Mock implementation of IRegistry for testing
 */
contract MockRegistry {
    mapping(address => uint8) public allowedAssets;
    mapping(address => bool) public validStrategies;
    mapping(address => bool) public isStrategyToken;
    address public conduit;

    /**
     * @notice Set an asset as allowed
     * @param asset The asset address
     * @param decimals The asset decimals
     */
    function setAsset(address asset, uint8 decimals) external {
        allowedAssets[asset] = decimals;
    }

    /**
     * @notice Set a token as strategy token
     * @param token The token address
     * @param value Whether the token is a strategy token
     */
    function setStrategyToken(address token, bool value) external {
        isStrategyToken[token] = value;
    }

    /**
     * @notice Set a strategy as valid
     * @param strategy The strategy address
     * @param value Whether the strategy is valid
     */
    function setStrategy(address strategy, bool value) external {
        validStrategies[strategy] = value;
    }

    /**
     * @notice Set the conduit address
     * @param _conduit The conduit address
     */
    function setConduit(address _conduit) external {
        conduit = _conduit;
    }
}
