# Multi-Collateral Deployment Guide

This guide explains how to deploy and manage the multi-collateral FountFi vault system.

## Overview

The multi-collateral system allows the vault to accept multiple Bitcoin-backed tokens (WBTC, tBTC, cbBTC, SovaBTC) as collateral while always redeeming in SovaBTC.

## Deployment Scripts

### 1. DeployMultiCollateral.s.sol
A simple deployment script for testing that deploys mock tokens and the basic multi-collateral infrastructure.

```bash
forge script script/DeployMultiCollateral.s.sol:DeployMultiCollateralScript \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### 2. DeployMultiCollateralProduction.s.sol
Production deployment script that integrates with existing FountFi infrastructure and uses real token addresses.

Required environment variables:
- `PRIVATE_KEY`: Deployer's private key
- `REGISTRY_ADDRESS`: Address of deployed Registry contract
- `ROLE_MANAGER_ADDRESS`: Address of deployed RoleManager
- `PRICE_REPORTER_ADDRESS`: (Optional) Address of price reporter
- `SOVABTC_ADDRESS`: Address of SovaBTC token on the target chain

For testnet deployments, you may also need:
- `WBTC_ADDRESS`: WBTC token address
- `TBTC_ADDRESS`: tBTC token address
- `CBBTC_ADDRESS`: cbBTC token address

```bash
forge script script/DeployMultiCollateralProduction.s.sol:DeployMultiCollateralProductionScript \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvvv
```

### 3. ManageMultiCollateral.s.sol
Management script for post-deployment operations.

#### View System Status
```bash
ACTION=view_status forge script script/ManageMultiCollateral.s.sol:ManageMultiCollateralScript \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

#### Add New Collateral
```bash
ACTION=add_collateral \
TOKEN_ADDRESS=0x... \
RATE=1000000000000000000 \
DECIMALS=8 \
forge script script/ManageMultiCollateral.s.sol:ManageMultiCollateralScript \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

#### Update Collateral Rate
```bash
ACTION=update_rate \
TOKEN_ADDRESS=0x... \
NEW_RATE=950000000000000000 \
forge script script/ManageMultiCollateral.s.sol:ManageMultiCollateralScript \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

#### Deposit Redemption Funds
```bash
ACTION=deposit_redemption \
AMOUNT=1000000000 \
forge script script/ManageMultiCollateral.s.sol:ManageMultiCollateralScript \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

## Deployment Process

### Step 1: Deploy Core Infrastructure (if needed)
If you haven't deployed the core FountFi infrastructure:
```bash
forge script script/DeployProtocol.s.sol:DeployProtocolScript \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### Step 2: Deploy Multi-Collateral System
Set the required environment variables and run:
```bash
export REGISTRY_ADDRESS=0x...
export ROLE_MANAGER_ADDRESS=0x...
export SOVABTC_ADDRESS=0x...

forge script script/DeployMultiCollateralProduction.s.sol:DeployMultiCollateralProductionScript \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvvv
```

### Step 3: Verify Deployment
```bash
export MC_REGISTRY_ADDRESS=0x... # From deployment output
export MC_STRATEGY_ADDRESS=0x... # From deployment output

ACTION=view_status forge script script/ManageMultiCollateral.s.sol:ManageMultiCollateralScript \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

### Step 4: Fund Strategy with Redemption SovaBTC
The vault manager should deposit SovaBTC for redemptions:
```bash
ACTION=deposit_redemption \
AMOUNT=10000000000 \
forge script script/ManageMultiCollateral.s.sol:ManageMultiCollateralScript \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

## Chain-Specific Addresses

### Ethereum Mainnet
- WBTC: `0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599`
- tBTC: `0x18084fbA666a33d37592fA2633fD49a74DD93a88`
- cbBTC: `0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf`

### Sepolia Testnet
Set via environment variables as tokens may vary.

### Ink Sepolia
Set via environment variables as tokens may vary.

## Rate Configuration

Rates are set in 1e18 format where:
- `1e18` (1000000000000000000) = 1:1 with SovaBTC
- `0.95e18` (950000000000000000) = 0.95:1 (5% discount)
- `1.05e18` (1050000000000000000) = 1.05:1 (5% premium)

## Security Considerations

1. Only accounts with `PROTOCOL_ADMIN` role can manage collateral types
2. Only the strategy manager can deposit redemption funds
3. Conversion rates should be carefully managed to reflect market conditions
4. Always verify token decimals before adding new collateral types

## Testing on Testnet

1. Deploy mock tokens first if needed
2. Use the simple deployment script for initial testing
3. Test all collateral types and conversion rates
4. Verify redemption flow works correctly
5. Test rate updates and their effects

## Monitoring

After deployment, monitor:
- Total collateral value in the strategy
- Individual collateral balances
- Redemption fund levels
- Conversion rates vs market rates