// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {MultiCollateralRegistry} from "../contracts/MultiCollateralRegistry.sol";
import {SimpleMultiCollateralStrategy} from "../contracts/SimpleMultiCollateralStrategy.sol";
import {tRWA} from "../src/token/tRWA-multicollateral.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/**
 * @title MultiCollateralHelpers
 * @notice Helper scripts for common multi-collateral operations
 * @dev Usage: forge script script/MultiCollateralHelpers.s.sol:<FunctionName> --rpc-url optimism-sepolia --broadcast
 */
contract AddCollateralScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address registryAddress = vm.envAddress("MULTI_COLLATERAL_REGISTRY");
        address tokenAddress = vm.envAddress("NEW_TOKEN_ADDRESS");
        uint256 rate = vm.envUint("RATE"); // in wei, e.g., 1e18 for 1:1
        uint8 decimals = uint8(vm.envUint("DECIMALS"));

        vm.startBroadcast(deployerPrivateKey);

        MultiCollateralRegistry registry = MultiCollateralRegistry(registryAddress);
        registry.addCollateral(tokenAddress, rate, decimals);

        console.log("Added collateral:");
        console.log("Token:", tokenAddress);
        console.log("Rate:", rate);
        console.log("Decimals:", decimals);

        vm.stopBroadcast();
    }
}

contract UpdateRateScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address registryAddress = vm.envAddress("MULTI_COLLATERAL_REGISTRY");
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        uint256 newRate = vm.envUint("NEW_RATE");

        vm.startBroadcast(deployerPrivateKey);

        MultiCollateralRegistry registry = MultiCollateralRegistry(registryAddress);
        registry.updateRate(tokenAddress, newRate);

        console.log("Updated rate for token:", tokenAddress);
        console.log("New rate:", newRate);

        vm.stopBroadcast();
    }
}

contract DepositRedemptionFundsScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address strategyAddress = vm.envAddress("STRATEGY_ADDRESS");
        address sovaBTCAddress = vm.envAddress("SOVABTC_ADDRESS");
        uint256 amount = vm.envUint("AMOUNT");

        vm.startBroadcast(deployerPrivateKey);

        SimpleMultiCollateralStrategy strategy = SimpleMultiCollateralStrategy(strategyAddress);
        MockERC20 sovaBTC = MockERC20(sovaBTCAddress);

        // Approve and deposit
        sovaBTC.approve(strategyAddress, amount);
        strategy.depositRedemptionFunds(amount);

        console.log("Deposited redemption funds:", amount);
        console.log("New SovaBTC balance in strategy:", sovaBTC.balanceOf(strategyAddress));

        vm.stopBroadcast();
    }
}

contract TestDepositScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        uint256 amount = vm.envUint("AMOUNT");
        address receiver = vm.envOr("RECEIVER", vm.addr(deployerPrivateKey));

        vm.startBroadcast(deployerPrivateKey);

        tRWA vault = tRWA(vaultAddress);
        MockERC20 token = MockERC20(tokenAddress);

        // Approve and deposit
        token.approve(vaultAddress, amount);
        uint256 shares = vault.depositCollateral(tokenAddress, amount, receiver);

        console.log("Deposited:", amount);
        console.log("Received shares:", shares);
        console.log("Vault balance:", vault.balanceOf(receiver));

        vm.stopBroadcast();
    }
}

contract CheckBalancesScript is Script {
    function run() external view {
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        address userAddress = vm.envAddress("USER_ADDRESS");

        tRWA vault = tRWA(vaultAddress);

        console.log("=== Vault Balances ===");
        console.log("User:", userAddress);
        console.log("Share balance:", vault.balanceOf(userAddress));
        console.log("Total supply:", vault.totalSupply());
        console.log("Total assets:", vault.totalAssets());

        // Calculate user's share of assets
        if (vault.totalSupply() > 0) {
            uint256 userAssets = vault.convertToAssets(vault.balanceOf(userAddress));
            console.log("User's asset value:", userAssets);
        }
    }
}
