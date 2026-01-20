// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {ManagedWithdrawRWA} from "../src/token/ManagedWithdrawRWA.sol";
import {ManagedWithdrawReportedStrategy} from "../src/strategy/ManagedWithdrawRWAStrategy.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {MockReporter} from "../src/mocks/MockReporter.sol";

contract DeployManagedWithdrawSimple is Script {
    // Optimism Sepolia WBTC (or use any test token)
    address constant WBTC = 0x68f180fcCe6836688e9084f035309E29Bf0A2095;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log("Deploying Simple ManagedWithdraw system on Optimism Sepolia");
        console2.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy RoleManager
        RoleManager roleManager = new RoleManager();
        console2.log("RoleManager deployed at:", address(roleManager));

        // 2. Deploy Mock Reporter (for testing)
        MockReporter reporter = new MockReporter(1e18); // 1:1 price
        console2.log("MockReporter deployed at:", address(reporter));

        // 3. Deploy ManagedWithdrawReportedStrategy
        ManagedWithdrawReportedStrategy strategy = new ManagedWithdrawReportedStrategy();
        console2.log("Strategy deployed at:", address(strategy));

        // 4. Initialize the strategy
        bytes memory initData = abi.encode(address(reporter));
        strategy.initialize(
            "Managed WBTC Vault",
            "mWBTC",
            address(roleManager),
            deployer, // manager
            WBTC,     // asset
            8,        // decimals
            initData  // reporter address
        );
        console2.log("Strategy initialized");

        // 5. Get the deployed vault address
        address vault = strategy.sToken();
        console2.log("ManagedWithdrawRWA vault deployed at:", vault);

        // 6. Configure roles
        roleManager.grantRoles(deployer, roleManager.PROTOCOL_ADMIN());
        roleManager.grantRoles(address(strategy), roleManager.STRATEGY_OPERATOR());
        console2.log("Roles configured");

        vm.stopBroadcast();

        // Log deployment summary
        console2.log("\n=== Deployment Summary ===");
        console2.log("ManagedWithdrawRWA Vault:", vault);
        console2.log("ManagedWithdrawReportedStrategy:", address(strategy));
        console2.log("RoleManager:", address(roleManager));
        console2.log("Reporter:", address(reporter));
        console2.log("Asset (WBTC):", WBTC);
        console2.log("\nManager:", deployer);
        console2.log("\n=== Ready for Testing ===");
        console2.log("1. Users can deposit WBTC via deposit()");
        console2.log("2. Users submit redemption requests with signatures");
        console2.log("3. Manager processes redemptions via redeem() or batchRedeem()");
    }
}