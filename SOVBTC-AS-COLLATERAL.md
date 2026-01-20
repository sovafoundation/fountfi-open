# SovaBTC as Both Collateral and Redemption Asset

## Overview
SovaBTC serves dual purposes in the multi-collateral vault:
1. **Redemption Asset**: All redemptions return SovaBTC
2. **Collateral Asset**: SovaBTC itself can be deposited as collateral

## Benefits of This Design

### 1. Simplified Redemptions
Users who deposit SovaBTC and later redeem get back SovaBTC - a clean 1:1 flow (minus any fees/yield adjustments).

### 2. Liquidity Management
- Deposited SovaBTC can directly fulfill redemption requests
- Reduces the need for vault manager to source external SovaBTC
- Creates natural liquidity buffer in the vault

### 3. Arbitrage Opportunities
If the vault's share price deviates from NAV, users can:
- Deposit SovaBTC when shares are undervalued
- Redeem for SovaBTC when shares are overvalued
- This helps maintain peg stability

## Implementation Considerations

### MultiCollateralRegistry Configuration
```solidity
// When setting up collateral registry
registry.addCollateral(
    sovaBTC,      // token address
    1e18,         // rate: 1:1 with SovaBTC (since it IS SovaBTC)
    8             // decimals
);
```

### Special Handling in Strategy
```solidity
contract MultiCollateralStrategy {
    function depositCollateral(address token, uint256 amount) external {
        if (token == sovaBTC) {
            // Direct SovaBTC deposits can immediately serve redemptions
            // No conversion needed
            sovaBTCReserves += amount;
        } else {
            // Other collateral tracked separately
            collateralBalances[token] += amount;
        }
    }
}
```

### Conversion Rate
- SovaBTC → SovaBTC rate is always 1:1
- Simplifies calculations when SovaBTC is deposited
- No oracle or rate updates needed for SovaBTC

## Example Flow

### User Deposits SovaBTC
1. User deposits 100 SovaBTC
2. Vault calculates shares: 100 SovaBTC = 100 shares (at 1:1 initial rate)
3. Strategy receives 100 SovaBTC
4. This SovaBTC is immediately available for redemptions

### Mixed Collateral Scenario
```
Vault State:
- 1000 WBTC (worth 1000 SovaBTC at current rates)
- 500 tBTC (worth 500 SovaBTC at current rates)  
- 300 SovaBTC (worth 300 SovaBTC)
- Total Value: 1800 SovaBTC
- Total Shares: 1800

Perfect 1:1 backing with built-in liquidity!
```

## Advantages for Vault Manager

1. **Reduced External Sourcing**: SovaBTC deposits provide ready liquidity
2. **Natural Rebalancing**: Market forces encourage SovaBTC deposits when needed
3. **Simplified Accounting**: SovaBTC deposits don't need conversion calculations

## Configuration Note

When deploying, ensure SovaBTC is added to the collateral whitelist:
```javascript
// In deployment script
await multiCollateralRegistry.addCollateral(
    SOVBTC_ADDRESS,  // The chain-specific SovaBTC address
    ethers.utils.parseEther("1"), // 1:1 rate
    8  // SovaBTC decimals
);
```

This creates a more robust and self-balancing system!