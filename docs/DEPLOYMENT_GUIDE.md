# Multi-Collateral Deployment Guide

## Prerequisites

1. **Install Foundry**
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

2. **Environment Setup**
   - Copy `.env.example` to `.env`
   - Add your private key (without 0x prefix)
   - Add your Etherscan API key for contract verification

3. **Get Test ETH**
   - Optimism Sepolia Faucet: https://www.alchemy.com/faucets/optimism-sepolia
   - Alternative: https://sepoliafaucet.com/ (bridge to Optimism Sepolia)

## Deployment Steps

### 1. Deploy to Optimism Sepolia

```bash
# Load environment variables
source .env

# Run deployment script
forge script script/DeployMultiCollateral.s.sol:DeployMultiCollateralScript \
  --rpc-url optimism-sepolia \
  --broadcast \
  --verify \
  -vvvv
```

### 2. Verify Contracts (if not auto-verified)

```bash
forge verify-contract <CONTRACT_ADDRESS> <CONTRACT_NAME> \
  --chain optimism-sepolia \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

### 3. Post-Deployment Testing

After deployment, test the contracts:

```bash
# Test deposit functionality
cast send <VAULT_ADDRESS> "depositCollateral(address,uint256,address)" \
  <WBTC_ADDRESS> <AMOUNT> <YOUR_ADDRESS> \
  --rpc-url optimism-sepolia \
  --private-key $PRIVATE_KEY

# Check balance
cast call <VAULT_ADDRESS> "balanceOf(address)" <YOUR_ADDRESS> \
  --rpc-url optimism-sepolia
```

## Deployed Contracts

The deployment script will output all contract addresses. Save these for future reference:

- **RoleManager**: Manages access control
- **Registry**: Central registry for strategies and assets
- **MultiCollateralRegistry**: Manages collateral types and rates
- **Tokens**:
  - SovaBTC: Mock redemption token
  - WBTC: Mock Wrapped Bitcoin
  - tBTC: Mock tBTC (18 decimals)
  - cbBTC: Mock Coinbase Bitcoin
- **Strategy**: SimpleMultiCollateralStrategy
- **Vault**: tRWA multi-collateral vault

## Configuration

### Adding New Collateral Types

```bash
# Add a new collateral token
cast send <MULTI_COLLATERAL_REGISTRY> "addCollateral(address,uint256,uint8)" \
  <TOKEN_ADDRESS> <RATE_IN_WEI> <DECIMALS> \
  --rpc-url optimism-sepolia \
  --private-key $PRIVATE_KEY
```

### Updating Exchange Rates

```bash
# Update collateral rate
cast send <MULTI_COLLATERAL_REGISTRY> "updateRate(address,uint256)" \
  <TOKEN_ADDRESS> <NEW_RATE_IN_WEI> \
  --rpc-url optimism-sepolia \
  --private-key $PRIVATE_KEY
```

## Security Considerations

1. **Test Network Only**: This deployment uses MockERC20 tokens suitable for testing only
2. **Access Control**: Ensure proper roles are assigned to trusted addresses
3. **Rate Management**: Exchange rates should be managed by trusted oracles in production

## Troubleshooting

### Common Issues

1. **Insufficient Gas**: Increase gas limit in deployment script
2. **Nonce Issues**: Reset nonce with `cast nonce <ADDRESS> --rpc-url optimism-sepolia`
3. **Verification Fails**: Ensure constructor arguments match exactly

### Useful Commands

```bash
# Check deployment status
cast receipt <TX_HASH> --rpc-url optimism-sepolia

# Get contract info
cast code <CONTRACT_ADDRESS> --rpc-url optimism-sepolia

# Debug failed transaction
cast run <TX_HASH> --rpc-url optimism-sepolia
```