// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Script, console2} from "forge-std/Script.sol";

contract VerifyManagedWithdrawScript is Script {
    function run() external {
        // Contract addresses from deployment
        address vault = 0x385177cEa70E5340ABc0c287CDb573ec0A49Edb4;
        address strategy = 0xf85E2681274eF80Daf3065083E8545590415AF80;
        address roleManager = 0x0Aee03ce6D7fbE67e95A840d5fc36Ab081974D9B;
        
        console2.log("Verifying contracts on Optimism Sepolia:");
        console2.log("Vault:", vault);
        console2.log("Strategy:", strategy);
        console2.log("RoleManager:", roleManager);
        
        // Constructor arguments for vault verification
        string memory name = "SovaBTC Yield Token";
        string memory symbol = "vBTC";
        address asset = 0x7CAAC5eB64E3721a82121f3b9b247Cb6fFca7203; // SovaBTC
        uint8 assetDecimals = 8;
        address strategyAddr = strategy;
        address sovaBTC = 0x7CAAC5eB64E3721a82121f3b9b247Cb6fFca7203;
        
        console2.log("\nVault constructor args:");
        console2.log("name:", name);
        console2.log("symbol:", symbol);
        console2.log("asset:", asset);
        console2.log("assetDecimals:", assetDecimals);
        console2.log("strategy:", strategyAddr);
        console2.log("sovaBTC:", sovaBTC);
        
        // Print encoded constructor args
        bytes memory constructorArgs = abi.encode(name, symbol, asset, assetDecimals, strategyAddr, sovaBTC);
        console2.log("\nEncoded constructor args:");
        console2.logBytes(constructorArgs);
    }
}