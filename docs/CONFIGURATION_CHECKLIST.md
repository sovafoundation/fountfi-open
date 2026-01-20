# Multi-Collateral Configuration Checklist

## Pre-Deployment Configuration

### 1. Environment Variables (.env file)
```bash
# Required
PRIVATE_KEY=your_private_key_without_0x
ETHERSCAN_API_KEY=your_etherscan_api_key

# Optional (if reusing existing contracts)
REGISTRY_ADDRESS=0x...
ROLE_MANAGER_ADDRESS=0x...
```

### 2. Manager Addresses
Update in deployment script if needed:
- `MANAGER_1`: Current: `0x0670faf0016E1bf591fEd8e0322689E894104F81`
- `MANAGER_2`: Current: `0xc67DD6f32147285A9e4D92774055cE3Dba5Ae8b6`

### 3. Token Configuration
The deployment creates mock tokens. For production:
- Replace with actual token addresses
- Verify decimal places (WBTC: 8, tBTC: 18, etc.)
- Set appropriate initial exchange rates

## Post-Deployment Configuration

### 1. Role Management
```bash
# Grant additional roles if needed
cast send <ROLE_MANAGER> "grantRole(address,uint256)" \
  <USER_ADDRESS> <ROLE_ID> \
  --rpc-url optimism-sepolia \
  --private-key $PRIVATE_KEY
```

Role IDs:
- `1`: DEPOSITOR_WHITELIST
- `2`: PROTOCOL_ADMIN  
- `4`: STRATEGY_ADMIN
- `8`: WITHDRAW_WHITELIST
- `16`: KYC_ADMIN
- `32`: KYC_OPERATOR
- `64`: RULES_ADMIN

### 2. Collateral Configuration

#### Add New Collateral Types
```bash
cast send <MULTI_COLLATERAL_REGISTRY> "addCollateral(address,uint256,uint8)" \
  <TOKEN_ADDRESS> <RATE_IN_WEI> <DECIMALS> \
  --rpc-url optimism-sepolia \
  --private-key $PRIVATE_KEY
```

#### Update Exchange Rates
```bash
cast send <MULTI_COLLATERAL_REGISTRY> "updateRate(address,uint256)" \
  <TOKEN_ADDRESS> <NEW_RATE_IN_WEI> \
  --rpc-url optimism-sepolia \
  --private-key $PRIVATE_KEY
```

### 3. Strategy Configuration

#### Add Redemption Funds (Manager Only)
```bash
# First approve SovaBTC to strategy
cast send <SOVABTC> "approve(address,uint256)" \
  <STRATEGY_ADDRESS> <AMOUNT> \
  --rpc-url optimism-sepolia \
  --private-key $PRIVATE_KEY

# Then deposit redemption funds
cast send <STRATEGY> "depositRedemptionFunds(uint256)" \
  <AMOUNT> \
  --rpc-url optimism-sepolia \
  --private-key $PRIVATE_KEY
```

### 4. User Approvals

For multi-collateral deposits, users need to approve tokens directly to the vault:

```bash
# Approve collateral token to vault
cast send <COLLATERAL_TOKEN> "approve(address,uint256)" \
  <VAULT_ADDRESS> <AMOUNT> \
  --rpc-url optimism-sepolia \
  --private-key $PRIVATE_KEY
```

For standard deposits (if using base asset), users approve to the registry's conduit:

```bash
# Get conduit address
cast call <REGISTRY> "conduit()" --rpc-url optimism-sepolia

# Approve to conduit
cast send <SOVABTC> "approve(address,uint256)" \
  <CONDUIT_ADDRESS> <AMOUNT> \
  --rpc-url optimism-sepolia \
  --private-key $PRIVATE_KEY
```

## Testing Configuration

### 1. Verify Deployment
```bash
# Check vault configuration
cast call <VAULT> "asset()" --rpc-url optimism-sepolia
cast call <VAULT> "strategy()" --rpc-url optimism-sepolia
cast call <VAULT> "sovaBTC()" --rpc-url optimism-sepolia

# Check strategy configuration  
cast call <STRATEGY> "collateralRegistry()" --rpc-url optimism-sepolia
cast call <STRATEGY> "manager()" --rpc-url optimism-sepolia
```

### 2. Test Deposits
```bash
# Test multi-collateral deposit
cast send <VAULT> "depositCollateral(address,uint256,address)" \
  <WBTC_ADDRESS> <AMOUNT> <YOUR_ADDRESS> \
  --rpc-url optimism-sepolia \
  --private-key $PRIVATE_KEY

# Check balance
cast call <VAULT> "balanceOf(address)" <YOUR_ADDRESS> \
  --rpc-url optimism-sepolia
```

## Security Checklist

- [ ] Verify all manager addresses are correct
- [ ] Confirm token decimals match expected values
- [ ] Set reasonable exchange rates (not 1:1 in production)
- [ ] Test deposits and withdrawals with small amounts first
- [ ] Verify role assignments are correct
- [ ] Check that only authorized addresses can update rates
- [ ] Ensure redemption funds are adequate for expected withdrawals

## Important Notes

1. **Token Approvals**: 
   - Multi-collateral deposits: Approve directly to vault
   - Standard deposits: Approve to registry's conduit

2. **Exchange Rates**: 
   - Rates are in 18 decimal format (1e18 = 1:1 rate)
   - Update rates based on actual market prices in production

3. **Redemption Funds**:
   - Strategy needs SovaBTC balance for withdrawals
   - Manager must deposit redemption funds before users can withdraw

4. **Access Control**:
   - Only PROTOCOL_ADMIN can add/remove collateral types
   - Only manager can deposit/withdraw redemption funds
   - Only STRATEGY_ADMIN can deploy new strategies