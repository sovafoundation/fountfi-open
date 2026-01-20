// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IMultiCollateralStrategy} from "../src/interfaces/IMultiCollateralStrategy.sol";
import {IMultiCollateralRegistry} from "../src/interfaces/IMultiCollateralRegistry.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/**
 * @title SimpleMultiCollateralStrategy
 * @notice Simplified multi-collateral strategy for testing
 */
contract SimpleMultiCollateralStrategy is IMultiCollateralStrategy {
    using SafeTransferLib for address;

    address public sToken;
    address public collateralRegistry;
    address public manager;
    address public asset;
    uint8 public assetDecimals;
    
    mapping(address => uint256) public collateralBalances;
    address[] public heldCollateralTokens;
    mapping(address => bool) public isHeldCollateral;

    event CollateralDeposited(address indexed token, uint256 amount);

    constructor(
        address _asset,
        uint8 _assetDecimals,
        address _registry,
        address _manager
    ) {
        asset = _asset;
        assetDecimals = _assetDecimals;
        collateralRegistry = _registry;
        manager = _manager;
    }

    function setSToken(address _sToken) external {
        require(sToken == address(0), "Already set");
        sToken = _sToken;
        // Pre-approve the vault to pull SovaBTC for withdrawals
        asset.safeApprove(_sToken, type(uint256).max);
    }

    function depositCollateral(address token, uint256 amount) external override {
        require(msg.sender == sToken, "Only vault");
        require(amount > 0, "Zero amount");
        
        IMultiCollateralRegistry registry = IMultiCollateralRegistry(collateralRegistry);
        require(registry.isAllowedCollateral(token), "Not allowed");
        
        collateralBalances[token] += amount;
        
        if (!isHeldCollateral[token]) {
            heldCollateralTokens.push(token);
            isHeldCollateral[token] = true;
        }
        
        emit CollateralDeposited(token, amount);
    }

    function depositRedemptionFunds(uint256 amount) external override {
        require(msg.sender == manager, "Only manager");
        asset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function totalCollateralValue() external view override returns (uint256 total) {
        IMultiCollateralRegistry registry = IMultiCollateralRegistry(collateralRegistry);
        
        for (uint256 i = 0; i < heldCollateralTokens.length; i++) {
            address token = heldCollateralTokens[i];
            uint256 tokenBalance = collateralBalances[token];
            if (tokenBalance > 0) {
                total += registry.convertToSovaBTC(token, tokenBalance);
            }
        }
        
        // Add any SovaBTC that's not tracked as collateral (e.g., redemption funds)
        uint256 sovaBTCBalance = asset.balanceOf(address(this));
        uint256 sovaBTCCollateral = collateralBalances[asset];
        if (sovaBTCBalance > sovaBTCCollateral) {
            total += sovaBTCBalance - sovaBTCCollateral;
        }
    }

    function balance() external view override returns (uint256) {
        return this.totalCollateralValue();
    }

    function withdraw(address to, uint256 amount) external {
        require(msg.sender == sToken, "Only vault");
        // Note: The vault will pull the funds via _collect
        // Approval is already set in setSToken
    }

    // Required interface methods
    function initialize(
        string calldata,
        string calldata,
        address,
        address,
        address,
        uint8,
        bytes memory
    ) external pure override {
        revert("Use constructor");
    }

    function name() external pure returns (string memory) {
        return "Simple Multi-Collateral Strategy";
    }

    function symbol() external pure returns (string memory) {
        return "SMCS";
    }
    
    function setManager(address newManager) external override {
        require(msg.sender == manager, "Only manager");
        manager = newManager;
    }
}