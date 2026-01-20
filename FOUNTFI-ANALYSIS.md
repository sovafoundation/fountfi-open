# FountFi Architecture Analysis for Multi-Collateral Support

## Core Architecture Overview

### Key Contracts
1. **tRWA.sol** - Main ERC-4626 vault implementation
   - Inherits from Solady's ERC4626
   - Uses hooks for extensibility
   - Currently hardcoded to single asset via `_asset` immutable

2. **ReportedStrategy.sol** - Strategy with oracle pricing
   - Reports balance via external price oracle
   - Manages actual asset holdings
   - Single asset focused

3. **Conduit.sol** - Asset transfer layer
   - Already supports token transfers generically
   - Perfect for multi-collateral routing
   - Validates token matches vault's asset

4. **Registry.sol** - Central registry
   - Manages allowed assets, strategies, hooks
   - Already has multi-asset support via `allowedAssets` mapping

## Current Flow Analysis

### Deposit Flow
1. User approves Conduit for asset
2. User calls `tRWA.deposit(assets, receiver)`
3. tRWA validates via hooks
4. Conduit transfers asset from user to strategy
5. tRWA mints shares to receiver

### Withdrawal Flow
1. User calls `tRWA.withdraw(assets, receiver, owner)`
2. tRWA burns shares
3. Strategy returns assets
4. tRWA transfers assets to receiver

## Modification Points for Multi-Collateral

### 1. tRWA.sol Modifications (Minimal)
```solidity
// Current: Single asset
function asset() public view virtual override returns (address) {
    return _asset;
}

// Modified: Return SovaBTC for ERC-4626 compliance
function asset() public view virtual override returns (address) {
    return sovaBTC; // New state variable or registry lookup
}

// Add new function for multi-collateral deposits
function depositCollateral(
    address collateralToken,
    uint256 collateralAmount,
    address receiver
) public virtual returns (uint256 shares) {
    // Implementation here
}
```

### 2. New Contracts (No Audit Impact)

#### MultiCollateralRegistry.sol
- Manages allowed collateral tokens
- Stores conversion rates to SovaBTC
- Provides conversion calculations

#### MultiCollateralStrategy.sol
- Extends ReportedStrategy
- Tracks multiple collateral balances
- Aggregates value in SovaBTC terms

### 3. Conduit Integration
- No modifications needed!
- Already supports arbitrary token transfers
- Just need to update validation logic

### 4. Hook Integration
- Create MultiCollateralHook for validation
- Leverages existing hook infrastructure
- No core contract changes

## Key Insights

1. **Minimal Core Changes**: Only ~50 lines in tRWA.sol
2. **Leverage Existing Infrastructure**: Conduit, Registry, Hooks all ready
3. **Additive Approach**: New functions don't break existing ones
4. **Clean Separation**: Multi-collateral logic in new contracts

## Implementation Strategy

### Phase 1: Foundation (Week 1)
- [x] Fork repository
- [ ] Create MultiCollateralRegistry
- [ ] Design conversion rate oracle

### Phase 2: Core Implementation (Week 2)
- [ ] Implement MultiCollateralStrategy
- [ ] Add depositCollateral to tRWA
- [ ] Override asset() to return SovaBTC

### Phase 3: Integration (Week 3)
- [ ] Connect to SovaBTC minting
- [ ] Implement redemption flow
- [ ] Create validation hooks

### Phase 4: Testing & Polish (Week 4)
- [ ] Comprehensive test suite
- [ ] Gas optimization
- [ ] Documentation

## Risk Assessment

### Low Risk
- Conduit already generic
- Registry supports multi-asset
- Hook system unchanged

### Medium Risk
- Strategy balance calculations
- Conversion rate accuracy
- Share price stability

### Mitigations
- Extensive testing
- Conservative rate feeds
- Audit of new contracts only