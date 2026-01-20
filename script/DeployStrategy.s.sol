// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Registry} from "../src/registry/Registry.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {PriceOracleReporter} from "../src/reporter/PriceOracleReporter.sol";
import {ReportedStrategy} from "../src/strategy/ReportedStrategy.sol";
import {GatedMintReportedStrategy} from "../src/strategy/GatedMintRWAStrategy.sol";
import {ManagedWithdrawReportedStrategy} from "../src/strategy/ManagedWithdrawRWAStrategy.sol";

contract DeployStrategyScript is Script {
    // Deployed contracts from previous scripts
    Registry public registry;
    MockERC20 public usdToken;
    PriceOracleReporter public priceOracle;
    address public strategyImplementation;

    // Deployment results
    address public strategy;
    address public token;

    function setUp() public {
        // // Load deployed addresses from latest.json broadcast
        // string memory root = vm.projectRoot();
        // string memory path = string.concat(root, "/broadcast/DeployProtocol.s.sol/120893/run-latest.json");
        // string memory json = vm.readFile(path);

        // Parse addresses from the JSON file
        address registryAddress = 0xB2873092aFB2826118A4fb990241d4776598E207;
        address usdTokenAddress = 0x69866D1f674d86D028A9B95eBfd5A2d3dd9AA35B;
        address priceOracleAddress = 0x67edFBF8c1D46992D415631f6D65De9Cf94cde7D;

        // Initialize contract references
        registry = Registry(registryAddress);
        usdToken = MockERC20(usdTokenAddress);
        priceOracle = PriceOracleReporter(priceOracleAddress);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy ManagedWithdrawRWAStrategy implementation
        ManagedWithdrawReportedStrategy newImpl = new ManagedWithdrawReportedStrategy();
        registry.setStrategy(address(newImpl), true);

        console.log("ManagedWithdrawRWAStrategy implementation deployed:", address(newImpl));

        // Determine which strategy implementation to use based on environment variable
        string memory strategyType = vm.envOr("STRATEGY_TYPE", string("standard"));

        if (keccak256(abi.encodePacked(strategyType)) == keccak256(abi.encodePacked("gated"))) {
            // Use GatedMintReportedStrategy
            address gatedImpl = 0x98975467905E1e63cC78B35997de82488100e66e;
            strategyImplementation = gatedImpl;
            console.log("Using GatedMintReportedStrategy implementation");
        } else if (keccak256(abi.encodePacked(strategyType)) == keccak256(abi.encodePacked("managed-withdraw"))) {
            // Use ManagedWithdrawReportedStrategy
            strategyImplementation = address(newImpl);
            console.log("Using ManagedWithdrawReportedStrategy implementation");
        } else {
            // Default to standard ReportedStrategy
            address standardImpl = 0xa8f206F6bC165BbCE0B3346469c1cCEF3d7936f1;
            strategyImplementation = standardImpl;
            console.log("Using ReportedStrategy implementation");
        }

        vm.stopBroadcast();
    }

    function run() public {
        // Use the private key directly from the command line parameter
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy strategy
        deployStrategy(deployer);

        // Log deployed strategy
        logDeployedStrategy();

        vm.stopBroadcast();
    }

    function deployStrategy(address deployer) internal {
        // Encode initialization data for the strategy (reporter address)
        bytes memory initData = abi.encode(address(priceOracle));

        // Deploy strategy through registry
        (strategy, token) = registry.deploy(
            strategyImplementation,
            "Fountfi USD Token", // name
            "fUSDC", // symbol
            address(usdToken),
            deployer, // Manager of the strategy
            initData
        );

        console.log("Strategy successfully deployed");
    }

    function logDeployedStrategy() internal view {
        // Log deployed strategy addresses
        console.log("\nDeployed Strategy:");
        console.log("Strategy Implementation:", strategyImplementation);
        console.log("Cloned Strategy:", strategy);
        console.log("Strategy Token:", token);
    }
}
