# FountFi Multi-Collateral Modification Plan

## Exact Modification Points Identified

### 1. tRWA.sol - Minimal Changes Required (~50 lines)

#### Add State Variable (Line ~56)
```solidity
/// @notice SovaBTC token address for multi-collateral redemptions (chain-specific)
address public immutable sovaBTC;
```

#### Modify Constructor (Line ~95)
```solidity
constructor(
    string memory name_,
    string memory symbol_,
    address asset_,
    uint8 assetDecimals_,
    address strategy_,
    address sovaBTC_  // NEW PARAMETER
) {
    // ... existing validation ...
    sovaBTC = sovaBTC_;  // NEW LINE
}
```

#### Override asset() Function (Line ~132)
```solidity
function asset() public view virtual override(ERC4626, ItRWA) returns (address) {
    // For multi-collateral, always return SovaBTC as the redemption asset
    return sovaBTC;
}

// Add getter for original asset (for backwards compatibility)
function underlyingAsset() public view returns (address) {
    return _asset;
}
```

#### Add depositCollateral Function (After line ~200)
```solidity
/**
 * @notice Deposit collateral tokens and receive vault shares
 * @param collateralToken The collateral token to deposit
 * @param collateralAmount The amount of collateral to deposit
 * @param receiver The address to receive shares
 * @return shares The amount of shares minted
 */
function depositCollateral(
    address collateralToken,
    uint256 collateralAmount,
    address receiver
) public virtual nonReentrant returns (uint256 shares) {
    // Get multi-collateral strategy
    IMultiCollateralStrategy multiStrategy = IMultiCollateralStrategy(strategy);
    
    // Convert collateral to SovaBTC value
    uint256 sovaBTCValue = multiStrategy.collateralRegistry()
        .convertToSovaBTC(collateralToken, collateralAmount);
    
    // Calculate shares based on SovaBTC value
    shares = previewDeposit(sovaBTCValue);
    
    // Run deposit hooks with collateral info
    HookInfo[] storage opHooks = operationHooks[OP_DEPOSIT];
    for (uint256 i = 0; i < opHooks.length;) {
        IHook.HookOutput memory hookOutput = opHooks[i].hook.onBeforeDeposit(
            address(this), msg.sender, sovaBTCValue, receiver
        );
        if (!hookOutput.approved) {
            revert HookCheckFailed(hookOutput.reason);
        }
        unchecked { ++i; }
    }
    
    // Transfer collateral through Conduit to strategy
    IRegistry(RoleManaged(strategy).registry()).conduit()
        .collectTokens(collateralToken, msg.sender, collateralAmount);
    
    // Notify strategy of collateral deposit
    multiStrategy.depositCollateral(collateralToken, collateralAmount);
    
    // Mint shares
    _mint(receiver, shares);
    emit Deposit(msg.sender, receiver, sovaBTCValue, shares);
}
```

#### NO CHANGES NEEDED to Withdraw Function
The existing withdraw logic remains unchanged. The vault manager will deposit SovaBTC into the strategy contract when fulfilling redemption requests, and the standard withdrawal flow will transfer that SovaBTC to users.

The key insight: When asset() returns SovaBTC, the existing withdrawal logic automatically handles SovaBTC redemptions correctly.

### 2. Conduit.sol - Add Multi-Token Support

#### Add New Function (After line ~61)
```solidity
/**
 * @notice Collect any token for multi-collateral deposits
 * @param token The token to collect
 * @param from The user address
 * @param amount The amount to collect
 */
function collectTokens(
    address token,
    address from,
    uint256 amount
) external returns (bool) {
    if (amount == 0) revert InvalidAmount();
    if (!IRegistry(registry()).isStrategyToken(msg.sender)) revert InvalidDestination();
    
    // For multi-collateral, verify token is allowed by strategy
    IMultiCollateralStrategy strategy = IMultiCollateralStrategy(
        ItRWA(msg.sender).strategy()
    );
    require(
        strategy.collateralRegistry().isAllowedCollateral(token),
        "Invalid collateral"
    );
    
    // Transfer to strategy
    token.safeTransferFrom(from, address(strategy), amount);
    return true;
}
```

### 3. New Interface File

#### interfaces/IMultiCollateralStrategy.sol
```solidity
// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IStrategy} from "../strategy/IStrategy.sol";

interface IMultiCollateralStrategy is IStrategy {
    function collateralRegistry() external view returns (address);
    function depositCollateral(address token, uint256 amount) external;
    function collateralBalances(address token) external view returns (uint256);
}
```

### 4. SovaBTC Interface Not Needed
Since we're not minting SovaBTC in the withdrawal flow (vault manager deposits pre-minted SovaBTC), we don't need an ISovaBTC interface.

## Summary of Changes

### Modified Files:
1. **tRWA.sol**: ~40 lines added/modified
   - Add sovaBTC state variable
   - Modify constructor
   - Override asset() to return SovaBTC
   - Add depositCollateral() function
   - NO CHANGES to withdraw logic (uses existing flow)

2. **Conduit.sol**: ~20 lines added
   - Add collectTokens() function

### New Files (No Audit Impact):
1. **MultiCollateralRegistry.sol**: Complete ✓
2. **MultiCollateralStrategy.sol**: To implement
3. **interfaces/IMultiCollateralStrategy.sol**: Defined above

### Unchanged Core Logic:
- Access control patterns ✓
- Hook validation system ✓
- Share calculation logic ✓
- Security mechanisms ✓
- Event emissions ✓

## Next Steps:
1. Create MultiCollateralStrategy.sol
2. Create interface files
3. Update deployment scripts
4. Write comprehensive tests