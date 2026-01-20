# ManagedWithdrawRWA Vault Verification Guide

## Contract Details
- **Address**: `0x385177cEa70E5340ABc0c287CDb573ec0A49Edb4`
- **Chain**: Optimism Sepolia (Chain ID: 11155420)
- **Deployed via**: Strategy contract (CREATE opcode)

## Constructor Arguments (Decoded)

The vault was deployed by the strategy with these parameters:
1. **name**: "SovaBTC Yield Token"
2. **symbol**: "vBTC"
3. **asset**: `0x7CAAC5eB64E3721a82121f3b9b247Cb6fFca7203` (SovaBTC)
4. **assetDecimals**: 18 (0x12 in hex) - Note: Using 18 decimals, not 8
5. **strategy**: `0xf85E2681274eF80Daf3065083E8545590415AF80`
6. **sovaBTC**: `0x7CAAC5eB64E3721a82121f3b9b247Cb6fFca7203`

## Constructor Arguments (ABI-Encoded)

```
0x00000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000001000000000000000000000000007caac5eb64e3721a82121f3b9b247cb6ffca72030000000000000000000000000000000000000000000000000000000000000012000000000000000000000000f85e2681274ef80daf3065083e8545590415af800000000000000000000000007caac5eb64e3721a82121f3b9b247cb6ffca72030000000000000000000000000000000000000000000000000000000000000013536f7661425443205969656c6420546f6b656e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000047642544300000000000000000000000000000000000000000000000000000000
```

## Verification Steps

### Option 1: Using Forge (Recommended)

```bash
# First, flatten the contract
forge flatten src/token/ManagedWithdrawRWA-multicollateral.sol > ManagedWithdrawRWA-flat.sol

# Then verify with the exact constructor args
forge verify-contract 0x385177cEa70E5340ABc0c287CDb573ec0A49Edb4 \
  src/token/ManagedWithdrawRWA-multicollateral.sol:ManagedWithdrawRWA \
  --chain-id 11155420 \
  --constructor-args 0x00000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000001000000000000000000000000007caac5eb64e3721a82121f3b9b247cb6ffca72030000000000000000000000000000000000000000000000000000000000000012000000000000000000000000f85e2681274ef80daf3065083e8545590415af800000000000000000000000007caac5eb64e3721a82121f3b9b247cb6ffca72030000000000000000000000000000000000000000000000000000000000000013536f7661425443205969656c6420546f6b656e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000047642544300000000000000000000000000000000000000000000000000000000 \
  --optimizer-runs 200 \
  --via-ir \
  --watch
```

### Option 2: Manual via Etherscan

1. Go to: https://sepolia-optimism.etherscan.io/address/0x385177cEa70E5340ABc0c287CDb573ec0A49Edb4#code
2. Click "Verify and Publish"
3. Use these settings:
   - **Compiler Type**: Solidity (Single file)
   - **Compiler Version**: v0.8.25+commit.b61c2a91
   - **License**: BUSL-1.1
   - **Optimization**: Yes
   - **Optimizer Runs**: 200
   - **EVM Version**: paris (default)
   - **Via IR**: Yes ✓

4. Paste the flattened source code
5. In the "Constructor Arguments ABI-encoded" field, paste the encoded args above
6. Complete verification

## Important Notes

1. The assetDecimals is 18 (0x12), not 8 as might be expected for BTC
2. The contract was deployed via CREATE from the strategy, not directly
3. Both `asset` and `sovaBTC` parameters point to the same address
4. The optimizer settings must match exactly: 200 runs with --via-ir enabled

## Already Verified Contracts
- Strategy: ✅ https://sepolia-optimism.etherscan.io/address/0xf85e2681274ef80daf3065083e8545590415af80#code
- RoleManager: ✅ https://sepolia-optimism.etherscan.io/address/0x0Aee03ce6D7fbE67e95A840d5fc36Ab081974D9B#code