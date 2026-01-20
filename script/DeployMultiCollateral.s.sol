// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Registry} from "../src/registry/Registry.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MultiCollateralRegistry} from "../contracts/MultiCollateralRegistry.sol";
import {SimpleMultiCollateralStrategy} from "../contracts/SimpleMultiCollateralStrategy.sol";
import {tRWA} from "../src/token/tRWA-multicollateral.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";

contract DeployMultiCollateralScript is Script {
    // Management addresses (same as DeployProtocol)
    address public constant MANAGER_1 = 0x0670faf0016E1bf591fEd8e0322689E894104F81;
    address public constant MANAGER_2 = 0xc67DD6f32147285A9e4D92774055cE3Dba5Ae8b6;

    // Deployed contracts from previous scripts
    Registry public registry;
    RoleManager public roleManager;

    // New contracts for multi-collateral
    MultiCollateralRegistry public multiCollateralRegistry;
    SimpleMultiCollateralStrategy public strategyImplementation;
    MockERC20 public sovaBTC;
    MockERC20 public wbtc;
    MockERC20 public tbtc;
    MockERC20 public cbBTC;

    // Deployment results
    address public strategy;
    address public vault;

    function setUp() public {
        // Load deployed addresses from environment or hardcode for testnet
        // These should be set based on your DeployProtocol deployment
        address registryAddress = vm.envOr("REGISTRY_ADDRESS", address(0));
        address roleManagerAddress = vm.envOr("ROLE_MANAGER_ADDRESS", address(0));

        // Initialize contract references if addresses provided
        if (registryAddress != address(0)) {
            registry = Registry(registryAddress);
        }
        if (roleManagerAddress != address(0)) {
            roleManager = RoleManager(roleManagerAddress);
        }
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy infrastructure if not already deployed
        if (address(roleManager) == address(0)) {
            deployRoleManager(deployer);
        }

        if (address(registry) == address(0)) {
            deployRegistry();
        }

        // Deploy multi-collateral infrastructure
        deployTokens(deployer);
        deployMultiCollateralRegistry();
        deployStrategy(deployer);

        // Log all deployed contracts
        logDeployedContracts();

        vm.stopBroadcast();
    }

    function deployRoleManager(address deployer) internal {
        roleManager = new RoleManager();

        // Grant admin roles to manager addresses
        roleManager.grantRole(MANAGER_1, roleManager.PROTOCOL_ADMIN());
        roleManager.grantRole(MANAGER_2, roleManager.PROTOCOL_ADMIN());
        roleManager.grantRole(MANAGER_1, roleManager.STRATEGY_ADMIN());
        roleManager.grantRole(MANAGER_2, roleManager.STRATEGY_ADMIN());

        console.log("RoleManager deployed:", address(roleManager));
    }

    function deployRegistry() internal {
        registry = new Registry(address(roleManager));
        roleManager.initializeRegistry(address(registry));
        console.log("Registry deployed:", address(registry));
    }

    function deployTokens(address deployer) internal {
        // Deploy SovaBTC (8 decimals like Bitcoin)
        sovaBTC = new MockERC20("SovaBTC", "SBTC", 8);
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        tbtc = new MockERC20("tBTC", "TBTC", 18); // tBTC uses 18 decimals
        cbBTC = new MockERC20("Coinbase Bitcoin", "cbBTC", 8);

        // Mint tokens for testing
        uint256 btcAmount8 = 100e8; // 100 BTC with 8 decimals
        uint256 btcAmount18 = 100e18; // 100 BTC with 18 decimals

        // Mint to deployer
        sovaBTC.mint(deployer, btcAmount8);
        wbtc.mint(deployer, btcAmount8);
        tbtc.mint(deployer, btcAmount18);
        cbBTC.mint(deployer, btcAmount8);

        // Mint to managers for testing
        sovaBTC.mint(MANAGER_1, btcAmount8);
        wbtc.mint(MANAGER_1, btcAmount8);
        sovaBTC.mint(MANAGER_2, btcAmount8);

        // Register tokens as allowed assets in registry
        registry.setAsset(address(sovaBTC), 8);
        registry.setAsset(address(wbtc), 8);
        registry.setAsset(address(tbtc), 18);
        registry.setAsset(address(cbBTC), 8);

        console.log("Tokens deployed and minted");
    }

    function deployMultiCollateralRegistry() internal {
        // Deploy multi-collateral registry
        multiCollateralRegistry = new MultiCollateralRegistry(address(roleManager), address(sovaBTC));

        // Add collateral types with 1:1 initial rates
        multiCollateralRegistry.addCollateral(address(wbtc), 1e18, 8);
        multiCollateralRegistry.addCollateral(address(tbtc), 1e18, 18);
        multiCollateralRegistry.addCollateral(address(cbBTC), 1e18, 8);
        multiCollateralRegistry.addCollateral(address(sovaBTC), 1e18, 8);

        console.log("MultiCollateralRegistry deployed:", address(multiCollateralRegistry));
    }

    function deployStrategy(address deployer) internal {
        // Deploy strategy implementation
        strategyImplementation =
            new SimpleMultiCollateralStrategy(address(sovaBTC), 8, address(multiCollateralRegistry), MANAGER_1);

        // Register strategy implementation in registry
        registry.setStrategy(address(strategyImplementation), true);

        // Deploy the vault (tRWA)
        vault = address(
            new tRWA(
                "Multi-Collateral Bitcoin Vault",
                "mcBTC",
                address(sovaBTC),
                8,
                address(strategyImplementation),
                address(sovaBTC)
            )
        );

        // Connect strategy to vault
        strategyImplementation.setSToken(vault);

        // Clone the strategy for actual use
        strategy = address(strategyImplementation);

        console.log("Strategy deployed:", strategy);
        console.log("Vault deployed:", vault);
    }

    function logDeployedContracts() internal view {
        console.log("\n=== Multi-Collateral Deployment Summary ===");
        console.log("\nCore Infrastructure:");
        console.log("Role Manager:", address(roleManager));
        console.log("Registry:", address(registry));

        console.log("\nTokens:");
        console.log("SovaBTC:", address(sovaBTC));
        console.log("WBTC:", address(wbtc));
        console.log("tBTC:", address(tbtc));
        console.log("cbBTC:", address(cbBTC));

        console.log("\nMulti-Collateral Infrastructure:");
        console.log("MultiCollateralRegistry:", address(multiCollateralRegistry));
        console.log("Strategy:", strategy);
        console.log("Vault (tRWA):", vault);

        console.log("\nManagers:");
        console.log("Manager 1:", MANAGER_1);
        console.log("Manager 2:", MANAGER_2);
    }
}
