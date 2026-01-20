# Multi-Collateral Vault Quick Start

## 1. Deploy Contracts

```bash
# Set environment variables
export PRIVATE_KEY=your_private_key
export ETHERSCAN_API_KEY=your_api_key

# Deploy
forge script script/DeployMultiCollateral.s.sol:DeployMultiCollateralScript \
  --rpc-url optimism-sepolia \
  --broadcast \
  --verify
```

## 2. Post-Deployment Setup

### Add Redemption Funds (Manager Only)
```bash
export STRATEGY_ADDRESS=0x... # From deployment output
export SOVABTC_ADDRESS=0x... # From deployment output
export AMOUNT=10000000000 # 100 SovaBTC (8 decimals)

forge script script/MultiCollateralHelpers.s.sol:DepositRedemptionFundsScript \
  --rpc-url optimism-sepolia \
  --broadcast
```

### Update Exchange Rates (If Needed)
```bash
export MULTI_COLLATERAL_REGISTRY=0x... # From deployment output
export TOKEN_ADDRESS=0x... # WBTC/tBTC/etc
export NEW_RATE=1100000000000000000 # 1.1 rate (10% premium)

forge script script/MultiCollateralHelpers.s.sol:UpdateRateScript \
  --rpc-url optimism-sepolia \
  --broadcast
```

## 3. User Operations

### Deposit Collateral
```bash
# Using cast
cast send <VAULT> "depositCollateral(address,uint256,address)" \
  <TOKEN> <AMOUNT> <RECEIVER> \
  --rpc-url optimism-sepolia \
  --private-key $PRIVATE_KEY

# Using helper script
export VAULT_ADDRESS=0x...
export TOKEN_ADDRESS=0x... # WBTC/tBTC/etc
export AMOUNT=100000000 # 1 WBTC (8 decimals)

forge script script/MultiCollateralHelpers.s.sol:TestDepositScript \
  --rpc-url optimism-sepolia \
  --broadcast
```

### Check Balances
```bash
export VAULT_ADDRESS=0x...
export USER_ADDRESS=0x...

forge script script/MultiCollateralHelpers.s.sol:CheckBalancesScript \
  --rpc-url optimism-sepolia
```

### Withdraw
```bash
cast send <VAULT> "withdraw(uint256,address,address)" \
  <ASSETS> <RECEIVER> <OWNER> \
  --rpc-url optimism-sepolia \
  --private-key $PRIVATE_KEY
```

## 4. Key Addresses (After Deployment)

Save these from deployment output:
- **Vault (tRWA)**: Main vault contract
- **Strategy**: Handles collateral management
- **MultiCollateralRegistry**: Manages rates and collateral types
- **Tokens**: WBTC, tBTC, cbBTC, SovaBTC addresses

## 5. Common Issues

### "Insufficient allowance"
→ Approve tokens to vault before depositing:
```bash
cast send <TOKEN> "approve(address,uint256)" <VAULT> <AMOUNT> \
  --rpc-url optimism-sepolia --private-key $PRIVATE_KEY
```

### "Invalid collateral"
→ Token not registered. Add it using AddCollateralScript

### "Insufficient redemption balance"
→ Manager needs to deposit SovaBTC to strategy first

## 6. Testing Flow

1. **Get test tokens** from deployment (minted to deployer)
2. **Approve vault** for the token you want to deposit
3. **Deposit collateral** using depositCollateral()
4. **Check shares** received
5. **Test withdrawal** (requires redemption funds)