// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Registry} from "../src/registry/Registry.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {PriceOracleReporter} from "../src/reporter/PriceOracleReporter.sol";
import {ManagedWithdrawReportedStrategy} from "../src/strategy/ManagedWithdrawRWAStrategy.sol";

/**
 * @title DeployManagedWithdrawalStrategyScript
 * @notice Script to deploy a ManagedWithdrawReportedStrategy
 * @dev This script either deploys a new implementation or uses an existing one
 *      and then deploys a clone of that implementation.
 */
contract DeployManagedWithdrawalStrategyScript is Script {
    // Deployed contracts from previous scripts
    Registry public registry;
    MockERC20 public usdToken;
    PriceOracleReporter public priceOracle;

    // Implementation and clone addresses
    address public strategyImplementation;
    address public strategy;
    address public token;

    function setUp() public {
        // Parse addresses from environment variables or use defaults
        address registryAddress = vm.envOr("REGISTRY_ADDRESS", address(0x9D9f34369AaC65f1506D57a0Ce57757C2821429f));
        address usdTokenAddress = vm.envOr("USD_TOKEN_ADDRESS", address(0x0864c69458072126424029192f0250a123C6a10C));
        address priceOracleAddress =
            vm.envOr("PRICE_ORACLE_ADDRESS", address(0x42A54c50e941f438d85bDdf4216666fB6876aB18));

        // Initialize contract references
        registry = Registry(registryAddress);
        usdToken = MockERC20(usdTokenAddress);
        priceOracle = PriceOracleReporter(priceOracleAddress);

        // Check if implementation address is provided
        strategyImplementation = vm.envOr("MANAGED_WITHDRAW_IMPL", address(0));
    }

    function run() public {
        // Use the private key from the environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation if not provided
        if (strategyImplementation == address(0)) {
            console.log("Deploying new ManagedWithdrawReportedStrategy implementation");
            ManagedWithdrawReportedStrategy newImpl = new ManagedWithdrawReportedStrategy();
            strategyImplementation = address(newImpl);

            // Register the implementation in the registry
            registry.setStrategy(strategyImplementation, true);
            console.log("Registered implementation in registry");
        } else {
            console.log("Using existing implementation at:", strategyImplementation);
        }

        // Deploy strategy clone
        deployStrategy(deployer);

        // Log deployed strategy details
        logDeployedStrategy();

        vm.stopBroadcast();
    }

    function deployStrategy(address deployer) internal {
        // Get token parameters from environment or use defaults
        string memory tokenName = vm.envOr("TOKEN_NAME", string("Fountfi USD Token"));
        string memory tokenSymbol = vm.envOr("TOKEN_SYMBOL", string("fUSDC"));

        // Encode initialization data for the strategy (reporter address)
        bytes memory initData = abi.encode(address(priceOracle));

        console.log("Deploying strategy with parameters:");
        console.log("  Token Name:", tokenName);
        console.log("  Token Symbol:", tokenSymbol);
        console.log("  Asset:", address(usdToken));
        console.log("  Manager:", deployer);

        // Deploy strategy through registry
        (strategy, token) =
            registry.deploy(strategyImplementation, tokenName, tokenSymbol, address(usdToken), deployer, initData);

        console.log("Strategy successfully deployed");
    }

    function logDeployedStrategy() internal view {
        // Log deployed contract addresses
        console.log("\nDeployed Strategy:");
        console.log("Strategy Implementation:", strategyImplementation);
        console.log("Cloned Strategy:", strategy);
        console.log("Strategy Token:", token);
    }
}
