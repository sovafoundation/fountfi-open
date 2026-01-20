// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {LibClone} from "solady/utils/LibClone.sol";
import {IStrategy} from "../strategy/IStrategy.sol";
import {RoleManaged} from "../auth/RoleManaged.sol";
import {ItRWA} from "../token/ItRWA.sol";
import {Conduit} from "../conduit/Conduit.sol";
import {IRegistry} from "./IRegistry.sol";

/**
 * @title Registry
 * @notice Central registry for strategies, rules, assets, and reporters
 * @dev Uses minimal proxy pattern for cloning templates
 */
contract Registry is IRegistry, RoleManaged {
    using LibClone for address;

    /*//////////////////////////////////////////////////////////////
                            STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Singleton contracts
    address public immutable override conduit;

    /// @notice Registry mappings
    mapping(address => bool) public override allowedStrategies;
    mapping(address => bool) public override allowedHooks;

    /// @notice asset => decimals (0 if not allowed)
    mapping(address => uint8) public override allowedAssets;

    /// @notice Deployed strategies
    address[] internal _allStrategies;
    mapping(address => bool) public override isStrategy;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructor
     * @param _roleManager Address of the role manager - singleton contract for managing protocol roles
     */
    constructor(address _roleManager) RoleManaged(_roleManager) {
        // Initialize the conduit with the role manager address
        conduit = address(new Conduit(_roleManager));
    }

    /*//////////////////////////////////////////////////////////////
                        REGISTRATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register a strategy implementation template
     * @param implementation Address of the strategy implementation
     * @param allowed Whether the implementation is allowed
     */
    function setStrategy(address implementation, bool allowed) external onlyRoles(roleManager.STRATEGY_ADMIN()) {
        if (implementation == address(0)) revert ZeroAddress();
        allowedStrategies[implementation] = allowed;
        emit SetStrategy(implementation, allowed);
    }

    /**
     * @notice Register an operation hook implementation template
     * @param implementation Address of the hook implementation
     * @param allowed Whether the implementation is allowed
     */
    function setHook(address implementation, bool allowed) external onlyRoles(roleManager.RULES_ADMIN()) {
        if (implementation == address(0)) revert ZeroAddress();
        allowedHooks[implementation] = allowed;
        emit SetHook(implementation, allowed);
    }

    /**
     * @notice Register an asset
     * @param asset Address of the asset
     * @param decimals Decimals of the asset (set 0 to disallow)
     */
    function setAsset(address asset, uint8 decimals) external onlyRoles(roleManager.PROTOCOL_ADMIN()) {
        if (asset == address(0)) revert ZeroAddress();
        allowedAssets[asset] = decimals;
        emit SetAsset(asset, decimals);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if a token is a tRWA token
     * @param token Address of the token
     * @return bool True if the token is a tRWA token, false otherwise
     */
    function isStrategyToken(address token) external view override returns (bool) {
        address strategy = ItRWA(token).strategy();

        if (!isStrategy[strategy]) return false;

        return IStrategy(strategy).sToken() == token;
    }

    /**
     * @notice Get all tRWA tokens
     * @return tokens Array of tRWA token addresses
     */
    function allStrategyTokens() external view override returns (address[] memory tokens) {
        tokens = new address[](_allStrategies.length);

        for (uint256 i = 0; i < _allStrategies.length;) {
            tokens[i] = IStrategy(_allStrategies[i]).sToken();

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Get all strategies
     * @return strategies Array of strategy addresses
     */
    function allStrategies() external view override returns (address[] memory strategies) {
        return _allStrategies;
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy a new strategy and its associated tRWA token
     * @param _strategyImpl Address of the strategy implementation
     * @param _name Token name
     * @param _symbol Token symbol
     * @param _asset Asset address
     * @param _manager Manager address for the strategy
     * @param _initData Initialization data
     * @return strategy Address of the deployed strategy
     * @return token Address of the deployed tRWA token
     */
    function deploy(
        address _strategyImpl,
        string memory _name,
        string memory _symbol,
        address _asset,
        address _manager,
        bytes memory _initData
    ) external override onlyRoles(roleManager.STRATEGY_OPERATOR()) returns (address strategy, address token) {
        if (allowedAssets[_asset] == 0) revert UnauthorizedAsset();
        if (!allowedStrategies[_strategyImpl]) revert UnauthorizedStrategy();

        // Clone the implementation
        strategy = _strategyImpl.clone();

        // Initialize the strategy
        IStrategy(strategy).initialize(
            _name, _symbol, address(roleManager), _manager, _asset, allowedAssets[_asset], _initData
        );

        // Get the token address
        token = IStrategy(strategy).sToken();

        // Register strategy in the factory
        _allStrategies.push(strategy);
        isStrategy[strategy] = true;

        emit Deploy(strategy, token, _asset);
    }
}
