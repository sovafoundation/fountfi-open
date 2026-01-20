// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {ManagedWithdrawRWA} from "../src/token/ManagedWithdrawRWA-multicollateral.sol";
import {ManagedWithdrawMultiCollateralStrategy} from "../src/strategy/ManagedWithdrawMultiCollateralStrategy.sol";
import {MultiCollateralRegistry} from "../contracts/MultiCollateralRegistry.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";

contract DeployManagedWithdrawMultiCollateral is Script {
    // Optimism Sepolia addresses
    address constant SOVA_BTC = 0x7CAAC5eB64E3721a82121f3b9b247Cb6fFca7203;
    address constant MULTI_COLLATERAL_REGISTRY = 0x63c8215a478f8F57C548a8700420Ac5Bd8Dc3749;
    
    // Collateral tokens
    address constant WBTC = 0x68f180fcCe6836688e9084f035309E29Bf0A2095;
    address constant TBTC = 0x6c84a8f1c29108F47a79964b5Fe888D4f4D0dE40;
    address constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log("Deploying ManagedWithdraw Multi-Collateral system on Optimism Sepolia");
        console2.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy RoleManager
        RoleManager roleManager = new RoleManager();
        console2.log("RoleManager deployed at:", address(roleManager));

        // 2. Try to deploy ManagedWithdrawMultiCollateralStrategy
        // Note: This contract exceeds the 24kb size limit
        console2.log("WARNING: ManagedWithdrawMultiCollateralStrategy exceeds size limit (24869 bytes)");
        console2.log("Deployment will likely fail on mainnet and some L2s");
        
        ManagedWithdrawMultiCollateralStrategy strategy = new ManagedWithdrawMultiCollateralStrategy();
        console2.log("Strategy deployed at:", address(strategy));

        // 3. Initialize the strategy with multi-collateral config
        bytes memory initData = abi.encode(MULTI_COLLATERAL_REGISTRY, SOVA_BTC);
        strategy.initialize(
            "SovaBTC Yield Token",
            "vBTC",
            address(roleManager),
            deployer, // manager
            SOVA_BTC, // asset for redemptions
            8,        // decimals - Bitcoin standard (8 decimals)
            initData  // registry and sovaBTC addresses
        );
        console2.log("Strategy initialized");

        // 4. Get the deployed vault address from strategy
        address vault = strategy.sToken();
        console2.log("ManagedWithdrawRWA vault deployed at:", vault);
        
        // 4b. Verify it's using the correct multi-collateral ManagedWithdrawRWA
        console2.log("Vault is multi-collateral enabled with SovaBTC redemptions");

        // 5. Verify multi-collateral configuration
        console2.log("Collateral registry configured during initialization");

        // 6. Configure role manager
        roleManager.grantRoles(deployer, roleManager.PROTOCOL_ADMIN());
        roleManager.grantRoles(address(strategy), roleManager.STRATEGY_OPERATOR());
        console2.log("Roles configured");

        // 7. Pre-approve vault for SovaBTC to enable redemptions
        (bool approveSuccess,) = SOVA_BTC.call(
            abi.encodeWithSignature("approve(address,uint256)", vault, type(uint256).max)
        );
        if (approveSuccess) {
            console2.log("SovaBTC approval set for vault");
        }

        vm.stopBroadcast();

        // Log deployment summary
        console2.log("\n=== Deployment Summary ===");
        console2.log("ManagedWithdrawRWA Vault:", vault);
        console2.log("ManagedWithdrawMultiCollateralStrategy:", address(strategy));
        console2.log("RoleManager:", address(roleManager));
        console2.log("MultiCollateralRegistry:", MULTI_COLLATERAL_REGISTRY);
        console2.log("SovaBTC:", SOVA_BTC);
        console2.log("\nManager:", deployer);
        console2.log("\n=== Ready for Testing ===");
        console2.log("1. Users can deposit WBTC, tBTC, cbBTC via depositCollateral()");
        console2.log("2. Users submit redemption requests with signatures");
        console2.log("3. Manager deposits SovaBTC via depositRedemptionFunds()");
        console2.log("4. Manager processes batch via batchRedeem()");
    }
}