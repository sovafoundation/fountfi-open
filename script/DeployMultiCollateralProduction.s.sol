// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Registry} from "../src/registry/Registry.sol";
import {MultiCollateralRegistry} from "../contracts/MultiCollateralRegistry.sol";
import {SimpleMultiCollateralStrategy} from "../contracts/SimpleMultiCollateralStrategy.sol";
import {IReporter} from "../src/reporter/IReporter.sol";
import {PriceOracleReporter} from "../src/reporter/PriceOracleReporter.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {tRWA} from "../src/token/tRWA-multicollateral.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract DeployMultiCollateralProductionScript is Script {
    // Management addresses
    address public constant MANAGER_1 = 0x0670faf0016E1bf591fEd8e0322689E894104F81;
    address public constant MANAGER_2 = 0xc67DD6f32147285A9e4D92774055cE3Dba5Ae8b6;

    // Chain-specific token addresses (update based on deployment chain)
    struct TokenAddresses {
        address sovaBTC;
        address wbtc;
        address tbtc;
        address cbBTC;
    }

    // Deployed contracts
    Registry public registry;
    RoleManager public roleManager;
    MultiCollateralRegistry public multiCollateralRegistry;
    SimpleMultiCollateralStrategy public strategyImplementation;
    IReporter public priceReporter;

    // Deployment results
    address public strategy;
    address public vault;

    function setUp() public {
        // Load deployed addresses from environment
        address registryAddress = vm.envOr("REGISTRY_ADDRESS", address(0));
        address roleManagerAddress = vm.envOr("ROLE_MANAGER_ADDRESS", address(0));
        address priceReporterAddress = vm.envOr("PRICE_REPORTER_ADDRESS", address(0));

        require(registryAddress != address(0), "REGISTRY_ADDRESS not set");
        require(roleManagerAddress != address(0), "ROLE_MANAGER_ADDRESS not set");

        registry = Registry(registryAddress);
        roleManager = RoleManager(roleManagerAddress);

        if (priceReporterAddress != address(0)) {
            priceReporter = IReporter(priceReporterAddress);
        }
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Get token addresses for the current chain
        TokenAddresses memory tokens = getTokenAddresses();

        // Deploy price reporter if not provided
        if (address(priceReporter) == address(0)) {
            deployPriceReporter();
        }

        // Deploy multi-collateral infrastructure
        deployMultiCollateralRegistry(tokens);
        deployStrategyImplementation(tokens);
        deployVault(deployer, tokens);

        // Configure access controls
        configureAccessControls();

        // Log deployment
        logDeployedContracts(tokens);

        vm.stopBroadcast();
    }

    function getTokenAddresses() internal view returns (TokenAddresses memory) {
        uint256 chainId = block.chainid;
        TokenAddresses memory tokens;

        if (chainId == 1) {
            // Ethereum Mainnet
            tokens.sovaBTC = vm.envOr("SOVABTC_ADDRESS", address(0));
            tokens.wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
            tokens.tbtc = 0x18084fbA666a33d37592fA2633fD49a74DD93a88;
            tokens.cbBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
        } else if (chainId == 11155111) {
            // Sepolia Testnet
            tokens.sovaBTC = vm.envOr("SOVABTC_ADDRESS", address(0));
            tokens.wbtc = vm.envOr("WBTC_ADDRESS", address(0));
            tokens.tbtc = vm.envOr("TBTC_ADDRESS", address(0));
            tokens.cbBTC = vm.envOr("CBBTC_ADDRESS", address(0));
        } else if (chainId == 763373) {
            // Ink Sepolia
            tokens.sovaBTC = vm.envOr("SOVABTC_ADDRESS", address(0));
            tokens.wbtc = vm.envOr("WBTC_ADDRESS", address(0));
            tokens.tbtc = vm.envOr("TBTC_ADDRESS", address(0));
            tokens.cbBTC = vm.envOr("CBBTC_ADDRESS", address(0));
        } else {
            revert("Unsupported chain ID");
        }

        require(tokens.sovaBTC != address(0), "SovaBTC address not set");

        return tokens;
    }

    function deployPriceReporter() internal {
        // Deploy a simple price reporter with initial price of 1 USD per share
        uint256 initialPrice = 1e18; // 1:1 with 18 decimals
        priceReporter = new PriceOracleReporter(
            initialPrice,
            MANAGER_1,
            100, // 1% max deviation
            3600 // 1 hour transition period
        );

        // Add second manager as updater
        PriceOracleReporter(address(priceReporter)).setUpdater(MANAGER_2, true);

        console.log("PriceReporter deployed:", address(priceReporter));
    }

    function deployMultiCollateralRegistry(TokenAddresses memory tokens) internal {
        multiCollateralRegistry = new MultiCollateralRegistry(address(roleManager), tokens.sovaBTC);

        // Add collateral types with 1:1 initial rates
        // Note: Check actual decimals on deployment chain
        if (tokens.wbtc != address(0)) {
            uint8 decimals = getTokenDecimals(tokens.wbtc);
            multiCollateralRegistry.addCollateral(tokens.wbtc, 1e18, decimals);
            registry.setAsset(tokens.wbtc, decimals);
        }

        if (tokens.tbtc != address(0)) {
            uint8 decimals = getTokenDecimals(tokens.tbtc);
            multiCollateralRegistry.addCollateral(tokens.tbtc, 1e18, decimals);
            registry.setAsset(tokens.tbtc, decimals);
        }

        if (tokens.cbBTC != address(0)) {
            uint8 decimals = getTokenDecimals(tokens.cbBTC);
            multiCollateralRegistry.addCollateral(tokens.cbBTC, 1e18, decimals);
            registry.setAsset(tokens.cbBTC, decimals);
        }

        // Add SovaBTC as both collateral and redemption asset
        uint8 sovaBTCDecimals = getTokenDecimals(tokens.sovaBTC);
        multiCollateralRegistry.addCollateral(tokens.sovaBTC, 1e18, sovaBTCDecimals);
        registry.setAsset(tokens.sovaBTC, sovaBTCDecimals);

        console.log("MultiCollateralRegistry deployed:", address(multiCollateralRegistry));
    }

    function deployStrategyImplementation(TokenAddresses memory tokens) internal {
        // Deploy the SimpleMultiCollateralStrategy
        // Note: In production, you would deploy the full MultiCollateralStrategy
        strategyImplementation = new SimpleMultiCollateralStrategy(
            tokens.sovaBTC, getTokenDecimals(tokens.sovaBTC), address(multiCollateralRegistry), MANAGER_1
        );

        // Register strategy implementation in registry
        registry.setStrategy(address(strategyImplementation), true);

        console.log("SimpleMultiCollateralStrategy implementation deployed:", address(strategyImplementation));
    }

    function deployVault(address deployer, TokenAddresses memory tokens) internal {
        // For SimpleMultiCollateralStrategy, we deploy the vault directly
        // since it doesn't use the registry's deploy pattern

        vault = address(
            new tRWA(
                "Multi-Collateral Bitcoin Vault",
                "mcBTC",
                tokens.sovaBTC,
                getTokenDecimals(tokens.sovaBTC),
                address(strategyImplementation),
                tokens.sovaBTC
            )
        );

        // Connect strategy to vault
        strategyImplementation.setSToken(vault);

        // Set strategy as the deployed instance
        strategy = address(strategyImplementation);

        console.log("Strategy deployed:", strategy);
        console.log("Vault deployed:", vault);
    }

    function configureAccessControls() internal {
        // Grant necessary roles for multi-collateral operations
        roleManager.grantRole(strategy, roleManager.STRATEGY_OPERATOR());

        // SimpleMultiCollateralStrategy already has manager set in constructor

        console.log("Access controls configured");
    }

    function getTokenDecimals(address token) internal view returns (uint8) {
        // Simple interface to get decimals
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSignature("decimals()"));
        require(success && data.length > 0, "Failed to get token decimals");
        return abi.decode(data, (uint8));
    }

    function logDeployedContracts(TokenAddresses memory tokens) internal view {
        console.log("\n=== Multi-Collateral Production Deployment ===");
        console.log("\nCore Contracts:");
        console.log("MultiCollateralRegistry:", address(multiCollateralRegistry));
        console.log("Strategy Implementation:", address(strategyImplementation));
        console.log("Deployed Strategy:", strategy);
        console.log("Vault (mcBTC):", vault);
        console.log("Price Reporter:", address(priceReporter));

        console.log("\nCollateral Tokens:");
        console.log("SovaBTC:", tokens.sovaBTC);
        if (tokens.wbtc != address(0)) console.log("WBTC:", tokens.wbtc);
        if (tokens.tbtc != address(0)) console.log("tBTC:", tokens.tbtc);
        if (tokens.cbBTC != address(0)) console.log("cbBTC:", tokens.cbBTC);

        console.log("\nManagement:");
        console.log("Manager 1:", MANAGER_1);
        console.log("Manager 2:", MANAGER_2);

        // Log initial configuration
        console.log("\nConfiguration:");
        console.log("Total Collateral Types:", multiCollateralRegistry.getCollateralTokenCount());
    }
}
