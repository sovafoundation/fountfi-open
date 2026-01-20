// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {MultiCollateralRegistry} from "../contracts/MultiCollateralRegistry.sol";
import {IMultiCollateralStrategy} from "../src/interfaces/IMultiCollateralStrategy.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

contract ManageMultiCollateralScript is Script {
    MultiCollateralRegistry public registry;
    IMultiCollateralStrategy public strategy;

    function setUp() public {
        // Load deployed addresses
        address registryAddress = vm.envOr("MC_REGISTRY_ADDRESS", address(0));
        address strategyAddress = vm.envOr("MC_STRATEGY_ADDRESS", address(0));

        require(registryAddress != address(0), "MC_REGISTRY_ADDRESS not set");
        require(strategyAddress != address(0), "MC_STRATEGY_ADDRESS not set");

        registry = MultiCollateralRegistry(registryAddress);
        strategy = IMultiCollateralStrategy(strategyAddress);
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        string memory action = vm.envOr("ACTION", string(""));

        vm.startBroadcast(privateKey);

        if (keccak256(bytes(action)) == keccak256(bytes("add_collateral"))) {
            addCollateral();
        } else if (keccak256(bytes(action)) == keccak256(bytes("update_rate"))) {
            updateRate();
        } else if (keccak256(bytes(action)) == keccak256(bytes("remove_collateral"))) {
            removeCollateral();
        } else if (keccak256(bytes(action)) == keccak256(bytes("deposit_redemption"))) {
            depositRedemptionFunds();
        } else if (keccak256(bytes(action)) == keccak256(bytes("view_status"))) {
            viewStatus();
        } else {
            revert(
                "Invalid ACTION. Use: add_collateral, update_rate, remove_collateral, deposit_redemption, view_status"
            );
        }

        vm.stopBroadcast();
    }

    function addCollateral() internal {
        address token = vm.envAddress("TOKEN_ADDRESS");
        uint256 rate = vm.envUint("RATE"); // in 1e18 format (1e18 = 1:1)
        uint8 decimals = uint8(vm.envUint("DECIMALS"));

        console.log("Adding collateral:");
        console.log("Token:", token);
        console.log("Rate:", rate);
        console.log("Decimals:", decimals);

        registry.addCollateral(token, rate, decimals);

        console.log("Collateral added successfully");
    }

    function updateRate() internal {
        address token = vm.envAddress("TOKEN_ADDRESS");
        uint256 newRate = vm.envUint("NEW_RATE"); // in 1e18 format

        console.log("Updating rate:");
        console.log("Token:", token);
        console.log("New Rate:", newRate);
        console.log("(1e18 = 1:1 with SovaBTC)");

        registry.updateRate(token, newRate);

        console.log("Rate updated successfully");
    }

    function removeCollateral() internal {
        address token = vm.envAddress("TOKEN_ADDRESS");

        console.log("Removing collateral:");
        console.log("Token:", token);

        registry.removeCollateral(token);

        console.log("Collateral removed successfully");
    }

    function depositRedemptionFunds() internal {
        uint256 amount = vm.envUint("AMOUNT");
        address sovaBTC = registry.sovaBTC();

        console.log("Depositing redemption funds:");
        console.log("Amount:", amount);
        console.log("SovaBTC:", sovaBTC);

        // Approve strategy to pull funds
        IERC20(sovaBTC).approve(address(strategy), amount);

        // Deposit redemption funds
        strategy.depositRedemptionFunds(amount);

        console.log("Redemption funds deposited successfully");
    }

    function viewStatus() internal view {
        console.log("\n=== Multi-Collateral System Status ===");

        // Registry info
        console.log("\nRegistry:", address(registry));
        console.log("SovaBTC:", registry.sovaBTC());
        console.log("Total Collateral Types:", registry.getCollateralTokenCount());

        // List all collateral tokens
        address[] memory tokens = registry.getAllCollateralTokens();
        if (tokens.length > 0) {
            console.log("\nCollateral Tokens:");
            for (uint256 i = 0; i < tokens.length; i++) {
                address token = tokens[i];
                uint256 rate = registry.collateralToSovaBTCRate(token);
                uint8 decimals = registry.collateralDecimals(token);

                console.log("\nToken", i, ":", token);
                console.log("  Rate:", rate, "(1e18 = 1:1)");
                console.log("  Decimals:", decimals);
                console.log("  Allowed:", registry.isAllowedCollateral(token));

                // Show example conversions
                uint256 oneToken = 10 ** decimals;
                uint256 sovaBTCValue = registry.convertToSovaBTC(token, oneToken);
                console.log("  1 token =", sovaBTCValue, "SovaBTC (in 8 decimals)");
            }
        }

        // Strategy info
        console.log("\nStrategy:", address(strategy));
        console.log("Total Collateral Value:", strategy.totalCollateralValue(), "SovaBTC");

        // Show SovaBTC balance (redemption funds)
        address sovaBTC = registry.sovaBTC();
        uint256 sovaBTCBalance = IERC20(sovaBTC).balanceOf(address(strategy));
        console.log("SovaBTC Balance:", sovaBTCBalance);
    }
}
