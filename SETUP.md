# Setup Instructions for Multi-Collateral Deployment

## Step 1: Environment Setup

1. **Fill in the `.env` file with your credentials:**

   ```bash
   # Edit the .env file
   nano .env
   ```

   **Required values:**
   - `PRIVATE_KEY`: Your wallet private key (without 0x prefix)
     - Example: `abcd1234...` (64 characters)
   - `ETHERSCAN_API_KEY`: Your Etherscan API key
     - Get one at: https://etherscan.io/apis

2. **Verify your setup:**
   ```bash
   # Check that environment variables are loaded
   source .env
   echo "Wallet address: $(cast wallet address --private-key $PRIVATE_KEY)"
   ```

## Step 2: Get Test ETH

1. **Get Optimism Sepolia ETH:**
   - Primary faucet: https://www.alchemy.com/faucets/optimism-sepolia
   - Alternative: https://app.optimism.io/faucet
   - You need at least 0.01 ETH for deployment

2. **Verify your balance:**
   ```bash
   cast balance $(cast wallet address --private-key $PRIVATE_KEY) --rpc-url optimism-sepolia
   ```

## Step 3: Deploy Contracts

1. **Run the deployment:**
   ```bash
   forge script script/DeployMultiCollateral.s.sol:DeployMultiCollateralScript \
     --rpc-url optimism-sepolia \
     --broadcast \
     --verify \
     -vvvv
   ```

2. **Save the deployed addresses from the output:**
   ```
   === Multi-Collateral Deployment Summary ===
   
   Core Infrastructure:
   Role Manager: 0x...
   Registry: 0x...
   
   Tokens:
   SovaBTC: 0x...
   WBTC: 0x...
   tBTC: 0x...
   cbBTC: 0x...
   
   Multi-Collateral Infrastructure:
   MultiCollateralRegistry: 0x...
   Strategy: 0x...
   Vault (tRWA): 0x...
   ```

3. **Update your `.env` file with deployed addresses:**
   ```bash
   # Add these to your .env file
   VAULT_ADDRESS=0x...
   STRATEGY_ADDRESS=0x...
   MULTI_COLLATERAL_REGISTRY=0x...
   SOVABTC_ADDRESS=0x...
   WBTC_ADDRESS=0x...
   ```

## Step 4: Post-Deployment Configuration

1. **Add redemption funds (as manager):**
   ```bash
   # First, reload environment with new addresses
   source .env
   
   # Set amount (e.g., 100 SovaBTC = 10000000000 in 8 decimals)
   export AMOUNT=10000000000
   
   # Run the script
   forge script script/MultiCollateralHelpers.s.sol:DepositRedemptionFundsScript \
     --rpc-url optimism-sepolia \
     --broadcast
   ```

## Step 5: Test the Deployment

1. **Test a deposit:**
   ```bash
   # Set test parameters
   export TOKEN_ADDRESS=$WBTC_ADDRESS
   export AMOUNT=100000000  # 1 WBTC (8 decimals)
   
   # Run test deposit
   forge script script/MultiCollateralHelpers.s.sol:TestDepositScript \
     --rpc-url optimism-sepolia \
     --broadcast
   ```

2. **Check balances:**
   ```bash
   export USER_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)
   
   forge script script/MultiCollateralHelpers.s.sol:CheckBalancesScript \
     --rpc-url optimism-sepolia
   ```

## Step 6: Verify on Etherscan

If automatic verification failed, manually verify:

```bash
# Example for the vault
forge verify-contract $VAULT_ADDRESS \
  "src/token/tRWA-multicollateral.sol:tRWA" \
  --chain optimism-sepolia \
  --constructor-args $(cast abi-encode "constructor(string,string,address,uint8,address,address)" \
    "Multi-Collateral Bitcoin Vault" "mcBTC" $SOVABTC_ADDRESS 8 $STRATEGY_ADDRESS $SOVABTC_ADDRESS)
```

## Troubleshooting

### "Insufficient funds"
- Make sure you have enough ETH: `cast balance $YOUR_ADDRESS --rpc-url optimism-sepolia`

### "Invalid private key"
- Ensure your private key is 64 characters without the 0x prefix

### "Transaction reverted"
- Check transaction details: `cast run $TX_HASH --rpc-url optimism-sepolia`

### "Cannot find module"
- Run `forge install` to install dependencies

## Next Steps

1. **Share vault address** with users for testing
2. **Monitor transactions** on: https://sepolia-optimism.etherscan.io/
3. **Update exchange rates** as needed using the helper scripts
4. **Add more collateral types** using AddCollateralScript

## Security Reminder

- **NEVER** share your private key
- **NEVER** commit `.env` to git
- **ALWAYS** test with small amounts first
- **VERIFY** all addresses before sending large amounts