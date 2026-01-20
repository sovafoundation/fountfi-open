# Multi-Collateral Vault Test Suite

## Overview
Comprehensive test suite for the FountFi multi-collateral implementation.

## Test Files

### 1. MultiCollateralRegistry.t.sol
Tests the collateral registry functionality:
- ✅ Adding/removing collateral tokens
- ✅ Conversion rate management
- ✅ Decimal normalization (8 vs 18 decimals)
- ✅ SovaBTC special case (1:1 always)
- ✅ Access control
- ✅ Edge cases and fuzz testing

### 2. MultiCollateralStrategy.t.sol
Tests the multi-collateral strategy:
- ✅ Collateral deposits from vault
- ✅ Multiple collateral tracking
- ✅ SovaBTC redemption fund deposits
- ✅ Total value calculations
- ✅ Withdrawal functionality
- ✅ Integration with registry

### 3. MultiCollateralVault.t.sol
End-to-end integration tests:
- ✅ WBTC deposits (8 decimals)
- ✅ tBTC deposits (18 decimals)
- ✅ SovaBTC deposits (1:1)
- ✅ Mixed collateral scenarios
- ✅ Redemption flow with pre-funded SovaBTC
- ✅ Share price calculations
- ✅ Standard ERC-4626 functions

## Running Tests

```bash
# Run all tests
forge test

# Run specific test file
forge test --match-path test/MultiCollateralRegistry.t.sol

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test testDepositWBTC

# Gas report
forge test --gas-report
```

## Key Test Scenarios

### 1. Multi-Collateral Deposits
- User deposits WBTC → receives shares based on SovaBTC value
- User deposits tBTC → decimal conversion handled correctly
- User deposits SovaBTC → 1:1 share minting

### 2. Redemption Flow
1. Users deposit various collateral
2. Manager deposits SovaBTC into strategy
3. Users redeem shares for SovaBTC
4. No minting occurs during redemption

### 3. Decimal Handling
- WBTC (8 decimals) → SovaBTC (8 decimals): Direct 1:1
- tBTC (18 decimals) → SovaBTC (8 decimals): Scaled correctly
- All conversions maintain precision

### 4. Edge Cases
- Cannot deposit unallowed collateral
- Access control enforced
- Zero amount deposits rejected
- Conversion rate updates work correctly

## Coverage Areas

1. **Unit Tests**: Individual contract functionality
2. **Integration Tests**: Multi-contract interactions
3. **E2E Tests**: Full user flows
4. **Fuzz Tests**: Random input validation
5. **Access Control**: Permission testing

## Notes

- All BTC-backed tokens use 1:1 rates in tests
- SovaBTC always has 8 decimals
- Manager must pre-fund redemptions with SovaBTC
- Standard ERC-4626 functions remain compatible