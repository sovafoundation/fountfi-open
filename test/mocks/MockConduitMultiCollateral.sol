// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Conduit} from "../../src/conduit/Conduit.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IMultiCollateralStrategy} from "../../src/interfaces/IMultiCollateralStrategy.sol";
import {IMultiCollateralRegistry} from "../../src/interfaces/IMultiCollateralRegistry.sol";
import {ItRWA} from "../../src/token/ItRWA.sol";
import {IRegistry} from "../../src/registry/IRegistry.sol";

/**
 * @title MockConduitMultiCollateral
 * @notice Mock conduit with multi-collateral support for testing
 */
contract MockConduitMultiCollateral is Conduit {
    using SafeTransferLib for address;

    constructor(address _roleManager) Conduit(_roleManager) {}

    /**
     * @notice Collect any token for multi-collateral deposits
     * @dev Mock implementation for testing
     */
    function collectTokens(address token, address from, uint256 amount) external returns (bool) {
        if (amount == 0) revert InvalidAmount();
        if (!IRegistry(registry()).isStrategyToken(msg.sender)) revert InvalidDestination();

        // Get the strategy from the calling tRWA
        address strategyAddress = ItRWA(msg.sender).strategy();

        // For multi-collateral, verify token is allowed by strategy
        IMultiCollateralStrategy strategy = IMultiCollateralStrategy(strategyAddress);
        IMultiCollateralRegistry collateralRegistry = IMultiCollateralRegistry(strategy.collateralRegistry());

        require(collateralRegistry.isAllowedCollateral(token), "Invalid collateral");

        // Transfer to strategy
        token.safeTransferFrom(from, strategyAddress, amount);

        return true;
    }
}
