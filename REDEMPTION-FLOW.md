# Multi-Collateral Redemption Flow

## Overview
The redemption flow for the multi-collateral FountFi fork follows the existing FountFi pattern where the vault manager is responsible for depositing the redemption currency into the strategy contract.

## Key Design Decision
- **No minting in withdrawal**: The vault does NOT mint SovaBTC during withdrawals
- **Pre-funded redemptions**: Vault manager deposits SovaBTC into the strategy beforehand
- **Standard flow preserved**: The existing withdrawal mechanism works unchanged

## Redemption Process

### 1. User Requests Redemption
```solidity
// User calls standard redeem function
vault.redeem(shares, receiver, owner)
```

### 2. Vault Manager Prepares SovaBTC (Off-chain Process)
- Manager monitors redemption requests
- Calculates required SovaBTC amount
- Sources SovaBTC through:
  - Converting collateral assets to SovaBTC
  - Using existing SovaBTC reserves
  - Minting new SovaBTC (if authorized)

### 3. Manager Deposits SovaBTC to Strategy
```solidity
// Manager transfers SovaBTC to strategy contract
sovaBTC.transfer(strategy, redemptionAmount)

// Or through a management function in strategy
strategy.depositRedemptionFunds(sovaBTCAmount)
```

### 4. Standard Withdrawal Executes
- Since `asset()` returns SovaBTC address
- The existing `_withdraw()` function:
  1. Burns user's shares
  2. Calls `_collect(assets)` to get SovaBTC from strategy
  3. Transfers SovaBTC to user
  4. No modifications needed!

## Benefits of This Approach

1. **Minimal Code Changes**: No modifications to withdrawal logic
2. **Audit Preservation**: Core redemption flow unchanged
3. **Flexibility**: Vault manager can source SovaBTC however needed
4. **Clean Separation**: Minting/sourcing logic separate from vault logic

## Strategy Contract Considerations

The MultiCollateralStrategy will need to:
- Track SovaBTC balance separately from collateral
- Report correct `balance()` including SovaBTC value
- Handle manager deposits of SovaBTC for redemptions

## Example Flow Diagram

```
User                    Vault                   Strategy              Manager
 |                       |                         |                     |
 |--redeem(shares)------>|                         |                     |
 |                       |                         |<--deposit SovaBTC---|
 |                       |<--get SovaBTC-----------|                     |
 |<--transfer SovaBTC----|                         |                     |
```

## Implementation Notes

1. The strategy's `balance()` function must include both:
   - Value of all collateral tokens (in SovaBTC terms)
   - Actual SovaBTC balance held for redemptions

2. The strategy may need a function for managers to deposit SovaBTC:
   ```solidity
   function depositRedemptionFunds(uint256 amount) external onlyManager {
       // Transfer SovaBTC from manager to strategy
       IERC20(sovaBTC).transferFrom(msg.sender, address(this), amount);
   }
   ```

3. No changes needed to tRWA's withdrawal function - it already:
   - Gets assets from strategy via `_collect()`
   - Transfers those assets to the user
   - Since `asset()` returns SovaBTC, it all works!