# Manual Contract Verification Instructions

## Optimized Managed Withdrawal Contracts

### 1. ManagedWithdrawRWA Vault
**Address**: `0x385177cEa70E5340ABc0c287CDb573ec0A49Edb4`
**URL**: https://sepolia-optimism.etherscan.io/address/0x385177cEa70E5340ABc0c287CDb573ec0A49Edb4#code

**Verification Settings**:
- **Compiler Type**: Solidity (Single file)
- **Compiler Version**: v0.8.25+commit.b61c2a91
- **Open Source License Type**: BUSL-1.1
- **Optimization**: Yes
- **Optimizer Runs**: 200
- **EVM Version**: paris
- **Via IR**: Yes (checked)

**Constructor Arguments ABI-encoded**:
```
0x00000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000001000000000000000000000000007caac5eb64e3721a82121f3b9b247cb6ffca72030000000000000000000000000000000000000000000000000000000000000008000000000000000000000000f85e2681274ef80daf3065083e8545590415af800000000000000000000000007caac5eb64e3721a82121f3b9b247cb6ffca72030000000000000000000000000000000000000000000000000000000000000013536f7661425443205969656c6420546f6b656e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000047642544300000000000000000000000000000000000000000000000000000000
```

**Source Code**:
Copy the entire content from: `src/token/ManagedWithdrawRWA-multicollateral.sol`

### 2. ManagedWithdrawMultiCollateralStrategy
**Address**: `0xf85E2681274eF80Daf3065083E8545590415AF80`
**Status**: ✅ Already Verified
**URL**: https://sepolia-optimism.etherscan.io/address/0xf85e2681274ef80daf3065083e8545590415af80#code

### 3. RoleManager
**Address**: `0x0Aee03ce6D7fbE67e95A840d5fc36Ab081974D9B`
**Status**: ✅ Already Verified
**URL**: https://sepolia-optimism.etherscan.io/address/0x0Aee03ce6D7fbE67e95A840d5fc36Ab081974D9B#code

## Steps to Manually Verify ManagedWithdrawRWA Vault

1. Go to https://sepolia-optimism.etherscan.io/address/0x385177cEa70E5340ABc0c287CDb573ec0A49Edb4#code
2. Click "Verify and Publish"
3. Select "Solidity (Single file)" as compiler type
4. Enter the settings above exactly as shown
5. Paste the full source code from `src/token/ManagedWithdrawRWA-multicollateral.sol`
6. Include all imports (the file should be flattened)
7. Paste the constructor arguments
8. Complete the CAPTCHA and submit

## Alternative: Using Forge Flatten

If single file doesn't work, try flattening:
```bash
forge flatten src/token/ManagedWithdrawRWA-multicollateral.sol > ManagedWithdrawRWA-flat.sol
```

Then use the flattened file for verification with the same settings.

## Contract Functionality Summary

The optimized managed withdrawal contracts provide:
- **Multi-collateral deposits**: Accept WBTC, tBTC, cbBTC
- **Managed withdrawals**: Users sign EIP-712 requests, manager processes in batches
- **SovaBTC redemptions**: All redemptions paid in SovaBTC
- **Optimized for mainnet**: Contract size reduced to 24,556 bytes (under 24,576 limit)
- **Custom errors**: Replaced require statements to save gas and size
- **Shortened domain separator**: "MWMCS" instead of full name