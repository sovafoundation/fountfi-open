// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

/**
 * @title IRegistry
 * @notice Interface for the Registry contract
 * @dev The Registry contract is used to register strategies, hooks, and assets
 *      and to deploy new strategies and tokens.
 */
interface IRegistry {
    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroAddress();
    error UnauthorizedStrategy();
    error UnauthorizedHook();
    error UnauthorizedAsset();
    error InvalidInitialization();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event SetStrategy(address indexed implementation, bool allowed);
    event SetHook(address indexed implementation, bool allowed);
    event SetAsset(address indexed asset, uint8 decimals);
    event Deploy(address indexed strategy, address indexed sToken, address indexed asset);
    event DeployWithController(address indexed strategy, address indexed sToken, address indexed controller);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function conduit() external view returns (address);

    function allowedStrategies(address implementation) external view returns (bool);
    function allowedHooks(address implementation) external view returns (bool);
    function allowedAssets(address asset) external view returns (uint8);

    function isStrategy(address implementation) external view returns (bool);
    function allStrategies() external view returns (address[] memory);
    function isStrategyToken(address token) external view returns (bool);
    function allStrategyTokens() external view returns (address[] memory tokens);

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function deploy(
        address _implementation,
        string memory _name,
        string memory _symbol,
        address _asset,
        address _manager,
        bytes memory _initData
    ) external returns (address strategy, address token);
}
