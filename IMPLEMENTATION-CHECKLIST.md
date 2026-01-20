# FountFi Multi-Collateral Implementation Checklist

## Phase 1: Interface & Contract Setup ✅ IN PROGRESS

### 1. Create Interface Files
- [ ] Create `src/interfaces/IMultiCollateralStrategy.sol`
- [ ] Create `src/interfaces/IMultiCollateralRegistry.sol`

### 2. Implement Core Contracts
- [x] MultiCollateralRegistry.sol - COMPLETE
- [ ] MultiCollateralStrategy.sol (extends ReportedStrategy)

## Phase 2: Modify Existing Contracts

### 3. Modify tRWA.sol (~40 lines)
- [ ] Add `sovaBTC` immutable state variable
- [ ] Update constructor to accept `sovaBTC` parameter
- [ ] Override `asset()` to return `sovaBTC`
- [ ] Add `underlyingAsset()` getter for backwards compatibility
- [ ] Add `depositCollateral()` function
- [ ] Ensure existing tests still pass

### 4. Modify Conduit.sol (~20 lines)
- [ ] Add `collectTokens()` function for multi-collateral
- [ ] Ensure it validates against MultiCollateralRegistry

## Phase 3: Testing & Integration

### 5. Create Test Suite
- [ ] Test multi-collateral deposits (WBTC, tBTC, etc.)
- [ ] Test SovaBTC as collateral (1:1 conversion)
- [ ] Test share calculations with mixed collateral
- [ ] Test redemptions return SovaBTC
- [ ] Test manager depositing SovaBTC for redemptions

### 6. Update Deployment Scripts
- [ ] Add MultiCollateralRegistry deployment
- [ ] Add MultiCollateralStrategy deployment
- [ ] Update tRWA deployment to include sovaBTC parameter
- [ ] Add collateral whitelist configuration

## Phase 4: Documentation & Deployment

### 7. Documentation
- [ ] Update README with multi-collateral instructions
- [ ] Document deployment process
- [ ] Create integration guide

### 8. Testnet Deployment
- [ ] Deploy to Sepolia first
- [ ] Test all functionality
- [ ] Deploy to other testnets

## Current Status
✅ Completed:
- Repository forked
- Architecture analyzed
- MultiCollateralRegistry implemented
- Documentation created

🔄 In Progress:
- Creating interface files

⏳ Next Steps:
1. Create interfaces
2. Implement MultiCollateralStrategy
3. Modify tRWA.sol
4. Modify Conduit.sol

## Order of Implementation
1. **Interfaces first** - Define contracts talk to each other
2. **MultiCollateralStrategy** - Core multi-collateral logic
3. **tRWA modifications** - Add depositCollateral function
4. **Conduit modifications** - Enable multi-token transfers
5. **Testing** - Comprehensive test coverage
6. **Deployment** - Scripts and testnet deployment

Ready to start with the interfaces!