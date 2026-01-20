# Optimism Sepolia Deployment - Multi-Collateral Contracts

**Deployment Date**: 2025-08-02
**Network**: Optimism Sepolia
**Chain ID**: 11155420

## Deployed Contract Addresses

### Core Infrastructure
- **RoleManager**: `0xE401DF98cA0e73371111A76AAbC067a84Eda1f7D`
- **Registry**: `0xcBBf02D619F4C53B1826B64Cc07Ea39Fb8442f13`
- **Conduit**: `0x2BE0922fC3732b840d42A8912F0296321D9C4a2E`

### Tokens
- **SovaBTC**: `0x7CAAC5eB64E3721a82121f3b9b247Cb6fFca7203`
- **WBTC**: `0xc9FE3e6fF20fE4EB4F48B3993C947be51007D2C1`
- **tBTC**: `0x0b00093Dcc35c1a887789e079453c64b641872b6`
- **cbBTC**: `0xfa4f9504B0f922221c209B8aC56294A31bC22618`

### Multi-Collateral Infrastructure
- **MultiCollateralRegistry**: `0x63c8215a478f8F57C548a8700420Ac5Bd8Dc3749`
- **Strategy**: `0xe7Ced7592F323a798A3aF6Cb3E041A9a7179F9A4`
- **Vault (tRWA)**: `0x2b82b75A0bF1AA01C9474546904bb446FD4E75C7`

### Managed Withdrawal Multi-Collateral Contracts (FIXED - 8 Decimals)
**Deployment Date**: 2025-08-03 (Updated with decimal fix)

#### Current Active Deployment (Use These)
- **ManagedWithdrawRWA Vault**: `0x2005f3675f1D712716c1fcc0D79bB68522c21Cf4` ✅ ACTIVE
- **ManagedWithdrawMultiCollateralStrategy**: `0x053b6D8a84814fC34720Ba6495E6d810C442aca2` ✅ ACTIVE
- **RoleManager**: `0x948ca01B31626dc2fd6A0C597204Bd024045CadC` ✅ ACTIVE

#### Previous Deployment (DEPRECATED - Had 18 decimal issue)
- ~~ManagedWithdrawRWA Vault: `0x385177cEa70E5340ABc0c287CDb573ec0A49Edb4`~~ ❌ DO NOT USE
- ~~Strategy: `0xf85E2681274eF80Daf3065083E8545590415AF80`~~ ❌ DO NOT USE
- ~~RoleManager: `0x0Aee03ce6D7fbE67e95A840d5fc36Ab081974D9B`~~ ❌ DO NOT USE

## Deployment Transaction
- **Transaction Hash**: `0x08fa5c8e0c5f37d1a6cf97b23c96f5f7f9b39c6f10e1d90c088ad87cc9e6a10e`
- **Block Number**: 21227089
- **Gas Used**: 15,473,476

## Contract Verification Status
All contracts have been successfully verified on Optimism Sepolia Etherscan.

## View on Etherscan
- [RoleManager](https://sepolia-optimistic.etherscan.io/address/0xE401DF98cA0e73371111A76AAbC067a84Eda1f7D#code)
- [Registry](https://sepolia-optimistic.etherscan.io/address/0xcBBf02D619F4C53B1826B64Cc07Ea39Fb8442f13#code)
- [Conduit](https://sepolia-optimistic.etherscan.io/address/0x2BE0922fC3732b840d42A8912F0296321D9C4a2E#code)
- [SovaBTC](https://sepolia-optimistic.etherscan.io/address/0x7CAAC5eB64E3721a82121f3b9b247Cb6fFca7203#code)
- [WBTC](https://sepolia-optimistic.etherscan.io/address/0xc9FE3e6fF20fE4EB4F48B3993C947be51007D2C1#code)
- [tBTC](https://sepolia-optimistic.etherscan.io/address/0x0b00093Dcc35c1a887789e079453c64b641872b6#code)
- [cbBTC](https://sepolia-optimistic.etherscan.io/address/0xfa4f9504B0f922221c209B8aC56294A31bC22618#code)
- [MultiCollateralRegistry](https://sepolia-optimistic.etherscan.io/address/0x63c8215a478f8F57C548a8700420Ac5Bd8Dc3749#code)
- [Strategy](https://sepolia-optimistic.etherscan.io/address/0xe7Ced7592F323a798A3aF6Cb3E041A9a7179F9A4#code)
- [Vault (tRWA)](https://sepolia-optimistic.etherscan.io/address/0x2b82b75A0bF1AA01C9474546904bb446FD4E75C7#code)

### Managed Withdrawal Contracts (Current Active)
- [ManagedWithdrawRWA Vault](https://sepolia-optimistic.etherscan.io/address/0x2005f3675f1D712716c1fcc0D79bB68522c21Cf4#code) ✅ ACTIVE
- [ManagedWithdrawMultiCollateralStrategy](https://sepolia-optimistic.etherscan.io/address/0x053b6D8a84814fC34720Ba6495E6d810C442aca2#code) ✅ ACTIVE
- [RoleManager (Managed)](https://sepolia-optimistic.etherscan.io/address/0x948ca01B31626dc2fd6A0C597204Bd024045CadC#code) ✅ ACTIVE

## Next Steps

1. **Update `.env` file** with deployed addresses:
   ```bash
   # Original Multi-Collateral Contracts
   VAULT_ADDRESS=0x2b82b75A0bF1AA01C9474546904bb446FD4E75C7
   STRATEGY_ADDRESS=0xe7Ced7592F323a798A3aF6Cb3E041A9a7179F9A4
   
   # Managed Withdrawal Contracts (FIXED - Use These!)
   MANAGED_VAULT_ADDRESS=0x2005f3675f1D712716c1fcc0D79bB68522c21Cf4
   MANAGED_STRATEGY_ADDRESS=0x053b6D8a84814fC34720Ba6495E6d810C442aca2
   MANAGED_ROLE_MANAGER=0x948ca01B31626dc2fd6A0C597204Bd024045CadC
   
   # Infrastructure
   MULTI_COLLATERAL_REGISTRY=0x63c8215a478f8F57C548a8700420Ac5Bd8Dc3749
   SOVABTC_ADDRESS=0x7CAAC5eB64E3721a82121f3b9b247Cb6fFca7203
   WBTC_ADDRESS=0xc9FE3e6fF20fE4EB4F48B3993C947be51007D2C1
   TBTC_ADDRESS=0x0b00093Dcc35c1a887789e079453c64b641872b6
   CBBTC_ADDRESS=0xfa4f9504B0f922221c209B8aC56294A31bC22618
   ```

2. **Add redemption funds** to the strategy (as manager):
   ```bash
   forge script script/MultiCollateralHelpers.s.sol:DepositRedemptionFundsScript \
     --rpc-url optimism-sepolia \
     --broadcast
   ```

3. **Test the deployment** with a small deposit:
   ```bash
   export TOKEN_ADDRESS=$WBTC_ADDRESS
   export AMOUNT=100000  # 0.001 WBTC
   
   forge script script/MultiCollateralHelpers.s.sol:TestDepositScript \
     --rpc-url optimism-sepolia \
     --broadcast
   ```

## Configuration Details
- **Managers**: 
  - `0x0670faf0016E1bf591fEd8e0322689E894104F81`
  - `0xc67DD6f32147285A9e4D92774055cE3Dba5Ae8b6`
- **Initial Exchange Rates**: All tokens set to 1:1 with SovaBTC (1e18)
- **Test Tokens Minted**: 1,000,000 of each token minted to deployer