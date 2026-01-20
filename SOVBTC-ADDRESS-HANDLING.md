# SovaBTC Address Handling for Multi-Chain Deployment

## Problem
SovaBTC will have different contract addresses on different chains, so we need a flexible way to configure it.

## Solution Options

### Option 1: Pass in Constructor (Recommended)
The cleanest approach is to pass the SovaBTC address when deploying the tRWA token.

```solidity
// In tRWA.sol constructor
constructor(
    string memory name_,
    string memory symbol_,
    address asset_,
    uint8 assetDecimals_,
    address strategy_,
    address sovaBTC_  // Chain-specific SovaBTC address
)
```

### Option 2: Store in Registry
Add SovaBTC address to the Registry contract:

```solidity
// In Registry.sol
mapping(uint256 => address) public sovaBTCByChainId;

function setSovaBTC(uint256 chainId, address sovaBTC) external onlyRoles(roleManager.PROTOCOL_ADMIN()) {
    sovaBTCByChainId[chainId] = sovaBTC;
    emit SovaBTCSet(chainId, sovaBTC);
}

function getSovaBTC() external view returns (address) {
    return sovaBTCByChainId[block.chainid];
}
```

### Option 3: Store in MultiCollateralRegistry
Since we already have a MultiCollateralRegistry, store it there:

```solidity
// Already in MultiCollateralRegistry.sol
address public immutable sovaBTC;

// This is set per-chain when deploying the registry
constructor(address _roleManager, address _sovaBTC) RoleManaged(_roleManager) {
    sovaBTC = _sovaBTC;
}
```

## Recommended Approach

**Use Option 1 + Option 3**: 
- Pass SovaBTC address to tRWA constructor for maximum flexibility
- Also store in MultiCollateralRegistry for reference

This gives us:
1. **Flexibility**: Each vault can theoretically use different SovaBTC if needed
2. **Consistency**: Registry ensures all vaults typically use the same SovaBTC
3. **Chain-specific**: Each deployment naturally handles its chain's address

## Deployment Flow

```javascript
// deployment script
const SOVBTC_ADDRESSES = {
    1: "0x...", // mainnet
    11155111: "0x...", // sepolia  
    8453: "0x...", // base
    10: "0x...", // optimism
}

// 1. Deploy MultiCollateralRegistry with chain-specific SovaBTC
const registry = await deploy("MultiCollateralRegistry", [
    roleManager,
    SOVBTC_ADDRESSES[chainId]
]);

// 2. Deploy strategy (gets sovaBTC from registry)
const strategy = await deploy("MultiCollateralStrategy", [
    ...params,
    registry.address
]);

// 3. Deploy tRWA with same SovaBTC
const tRWA = await deploy("tRWA", [
    name,
    symbol,
    asset,
    decimals,
    strategy,
    SOVBTC_ADDRESSES[chainId] // Chain-specific
]);
```

## Benefits
- Clean, explicit configuration per chain
- No hardcoded addresses in contracts
- Easy to verify correct address in deployment
- Supports different SovaBTC versions if needed