# Fountfi Protocol Security Audit Report

**Date:** February 6, 2025
**Auditor:** Claude (Opus)
**Scope:** Complete Fountfi Protocol codebase
**Commit:** 3a35824

## Executive Summary

This report presents the findings from a comprehensive security audit of the Fountfi Protocol, a system for tokenizing Real World Assets (RWA) on-chain. The audit identified several critical and high-severity vulnerabilities that must be addressed before deployment to production.

### Key Findings Summary:
- **Critical:** 3 issues
- **High:** 5 issues
- **Medium:** 4 issues
- **Low:** 3 issues
- **Informational:** 2 issues

## Audit Methodology

The audit consisted of:
1. Manual code review of all smart contracts
2. Analysis of contract interactions and state transitions
3. Verification of access control implementations
4. Review of mathematical operations and edge cases
5. Assessment of external dependencies and integrations

## Findings

### Critical Severity

#### C-01: Unrestricted Ether Reception in BasicStrategy

**Location:** `src/strategy/BasicStrategy.sol:127-129`

**Description:** The `sendETH` function allows the strategy to send all its ETH balance to any address, but there's no `receive()` or `fallback()` function to handle incoming ETH. This could lead to locked funds if ETH is sent to the strategy.

**Impact:** Permanent loss of funds if ETH is sent to the strategy contract.

**Proof of Concept:**
```solidity
// ETH sent to strategy address will be permanently locked
payable(strategyAddress).transfer(1 ether); // This will succeed but funds are locked
```

**Recommendation:** Add a `receive()` function with proper access controls or explicitly reject ETH transfers if not intended.

**Resolution:** Fixed in `d3377b8a6929ea019a22a4b57c48c927f62d2416`.

#### C-02: Signature Malleability in ManagedWithdrawRWAStrategy

**Location:** `src/strategy/ManagedWithdrawRWAStrategy.sol:194-203`

**Description:** The signature verification in `_verifySignature` uses `ecrecover` directly without protection against signature malleability. An attacker could potentially create a different valid signature for the same message.

**Impact:** While the nonce mechanism prevents replay attacks, signature malleability could cause issues with signature uniqueness assumptions.

**Recommendation:** Use OpenZeppelin's ECDSA library or implement signature malleability protection:
```solidity
require(uint256(s) <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0, "Invalid signature 's' value");
require(v == 27 || v == 28, "Invalid signature 'v' value");
```

**Resolution:** Fixed in `5274c4a67d9c67bbb27fd49d5a57c42814e9b48c`.

#### C-03: Missing Slippage Protection in Batch Operations

**Location:** `src/token/ManagedWithdrawRWA.sol:115-119`

**Description:** In `batchRedeemShares`, the pro-rata calculation `(userShares * totalAssets) / totalShares` can result in rounding errors that accumulate across the batch. The sum of distributed assets may not equal `totalAssets`.

**Impact:** Loss of funds due to rounding errors, especially problematic with tokens having low decimals.

**Proof of Concept:**
```solidity
// If totalAssets = 100, totalShares = 3
// User1: 1 share = 33 assets
// User2: 1 share = 33 assets
// User3: 1 share = 33 assets
// Total distributed: 99 assets (1 asset lost)
```

**Recommendation:** Track remaining assets and distribute any dust to the last recipient, or implement a more sophisticated rounding mechanism.

**Resolution:** Fixed in `f4f863ddd128aa781114e7df734eac0b292d17f7`.

### High Severity

#### H-01: Reentrancy in tRWA Withdrawal Flow

**Location:** `src/token/tRWA.sol:183-206`

**Description:** The `_withdraw` function calls hooks before burning shares and transferring assets. Malicious hooks could re-enter the contract in an inconsistent state.

**Impact:** Potential for fund theft through reentrancy attacks.

**Recommendation:** Follow checks-effects-interactions pattern. Burn shares before calling hooks:
```solidity
function _withdraw(...) internal override {
    if (by != owner) _spendAllowance(owner, by, shares);
    _beforeWithdraw(assets, shares);
    _burn(owner, shares); // Burn first

    // Then call hooks
    HookInfo[] storage opHooks = operationHooks[OP_WITHDRAW];
    // ... hook calls ...

    SafeTransferLib.safeTransfer(asset(), to, assets);
    emit Withdraw(by, to, owner, assets, shares);
}
```

**Resolution:** Fixed in `94f871d19a895c2f0b2fbe32b12cb824e1fbd6d9`.

#### H-02: Centralization Risk in PriceOracleReporter

**Location:** `src/reporter/PriceOracleReporter.sol:64-74`

**Description:** No maximum deviation check or staleness protection for price updates. A compromised updater could set arbitrary prices.

**Impact:** Complete manipulation of token valuations, enabling theft through mispriced deposits/withdrawals.

**Recommendation:** Implement price bands and staleness checks:
```solidity
uint256 public constant MAX_PRICE_DEVIATION = 10e16; // 10%
uint256 public constant MAX_PRICE_AGE = 1 days;

function update(uint256 newPricePerShare, string calldata source_) external {
    require(block.timestamp - lastUpdateAt <= MAX_PRICE_AGE, "Price too stale");

    uint256 deviation = abs(int256(newPricePerShare) - int256(pricePerShare)) * 1e18 / pricePerShare;
    require(deviation <= MAX_PRICE_DEVIATION, "Price deviation too high");
    // ...
}
```

**Resolution:** Acknowledged, initial versions of `PriceOracleReporter` will be highly trusted.


#### H-03: Unchecked External Call in BasicStrategy

**Location:** `src/strategy/BasicStrategy.sol:188-198`

**Description:** The `call` function allows arbitrary external calls with user-provided calldata. While restricted to manager, this is extremely dangerous.

**Impact:** Complete compromise of strategy funds if manager key is compromised.

**Recommendation:** Implement a whitelist of allowed target contracts and function selectors, or remove this functionality entirely.

**Resolution:** Acknowledged, this is protocol design such that the strategy contract can act like a smart wallet.


#### H-04: Denial of Service in Hook Removal

**Location:** `src/token/tRWA.sol:255-256`

**Description:** The `hasProcessedOperations` check prevents removing hooks that have been used, potentially leading to permanent hooks.

**Impact:** Malicious or buggy hooks could become permanent fixtures, potentially breaking token functionality.

**Recommendation:** Add an emergency removal function with a timelock, or allow removal after a certain period.

**Resolution:** Acknowledged, the removal feature is meant more for immediate misconfiguration resolution than ongoing hook management.

#### H-05: Integer Division Precision Loss

**Location:** `src/token/GatedMintRWA.sol:169`

**Description:** The calculation `(assetAmounts[i] * totalShares) / totalAssets` performs division last, which can lead to significant precision loss.

**Impact:** Users may receive fewer shares than entitled, especially for small deposits.

**Recommendation:** Use a higher precision intermediate calculation or a different rounding approach.

**Resolution:** Fixed in `6710838e6fa243c2d049b895c4b784f060e78105`.

### Medium Severity

#### M-01: Front-Running Vulnerability in GatedMintEscrow

**Location:** `src/strategy/GatedMintEscrow.sol:278-301`

**Description:** The `reclaimDeposit` function allows users to reclaim deposits after expiration, but a malicious strategy operator could front-run this with `acceptDeposit`.

**Impact:** Users may be unable to reclaim expired deposits.

**Recommendation:** Add a grace period where only the depositor can act:
```solidity
if (block.timestamp > deposit.expirationTime + GRACE_PERIOD) {
    // Only depositor can reclaim
} else if (block.timestamp > deposit.expirationTime) {
    // Both depositor and strategy can act
}
```

**Resolution:** Acknowledged, if a deposit is still valid it should acceptable.

#### M-02: Missing Event Emissions

**Location:** Multiple locations in BasicStrategy.sol

**Description:** Functions like `sendToken`, `pullToken`, and `setAllowance` modify important state but don't emit events.

**Impact:** Reduced transparency and difficulty in tracking strategy actions off-chain.

**Recommendation:** Add events for all state-changing operations.

**Resolution:** Acknowledged, we think event emission is sufficient since the underlying ERC20 token events will be emitted.

#### M-03: Initialization Race Condition

**Location:** `src/auth/RoleManager.sol:86-91`

**Description:** The `initializeRegistry` function can be front-run, potentially setting a malicious registry.

**Impact:** Protocol could be initialized with an attacker-controlled registry.

**Recommendation:** Combine deployment and initialization in a single transaction, or use a constructor parameter.

**Resolution:** Disputed, since `intializeRegistry` can only be callable by the owner.

#### M-04: Unbounded Loop in Withdrawal Queue

**Location:** `src/token/GatedMintRWA.sol:167-173`

**Description:** The batch operations loop through unbounded arrays, potentially causing gas limit issues.

**Impact:** Denial of service if arrays are too large.

**Recommendation:** Implement a maximum batch size limit.

**Resolution:** Acknowledged, transactions that are bound to fail can be detected and modified before on-chain submission.


### Low Severity

#### L-01: Floating Pragma

**Location:** `src/registry/Registry.sol:2`

**Description:** Uses `pragma solidity ^0.8.25` instead of a fixed version.

**Impact:** Different compiler versions might introduce subtle bugs.

**Recommendation:** Use a fixed pragma version: `pragma solidity 0.8.25;`

**Resolution:** Fixed in `a3d42a7ad899defc604e4e65bd9faa687b44b283`.

#### L-02: Missing Zero Address Validation

**Location:** `src/strategy/BasicStrategy.sol:105-111`

**Description:** `setManager` allows setting manager to zero address without validation.

**Impact:** Could accidentally lock strategy management functions.

**Recommendation:** Add zero address check or document this as intended behavior.

**Resolution**: Acknowledged, setting the manager address to zero is a way of pausing strategy operations in case of emergencies.

#### L-03: Inefficient Storage Access

**Location:** `src/hooks/RulesEngine.sol:278-306`

**Description:** Multiple reads from storage in loops when values could be cached.

**Impact:** Higher gas costs.

**Recommendation:** Cache frequently accessed storage variables in memory.

**Resolution:** Fixed in `42091d38810bbf1b1788cfdd540214e3fac333b5`.

### Informational

#### I-01: Unused Error Definitions

**Location:** `src/token/tRWA.sol:25`

**Description:** `AssetDecimalsTooHigh` error is defined but never used.

**Impact:** Code cleanliness.

**Recommendation:** Remove unused error definitions.

**Resolution:** Fixed in `a4403d86133e18089eb1df19b9f9a8594d5e4955`.

#### I-02: Naming Inconsistency

**Location:** Throughout codebase

**Description:** Inconsistent naming between "hook" and "rule" in various contracts.

**Impact:** Reduced code readability.

**Recommendation:** Standardize terminology across the codebase.

**Resolution:** Acknowleged.

## Security Considerations

### Access Control
The protocol implements a comprehensive role-based access control system. However, the concentration of power in certain roles (especially PROTOCOL_ADMIN) presents centralization risks.

### Oracle Security
The price reporting mechanism lacks robust validation, making it vulnerable to manipulation. This is particularly concerning given the protocol's reliance on accurate pricing.

### Upgrade Patterns
The protocol uses the clone pattern for deployments, which prevents upgrades. While this improves security, it also means bugs cannot be fixed post-deployment.

## Recommendations

1. **Immediate Actions:**
   - Fix critical issues C-01, C-02, and C-03
   - Implement reentrancy guards on all token operations
   - Add price deviation limits to oracle reporters

2. **Before Mainnet:**
   - Address all High severity issues
   - Implement comprehensive event logging
   - Add emergency pause mechanisms
   - Conduct formal verification of critical mathematical operations

3. **Long-term Improvements:**
   - Consider implementing timelocks for sensitive operations
   - Add multi-signature requirements for critical admin functions
   - Implement a bug bounty program
   - Regular security audits and monitoring

## Conclusion

The Fountfi Protocol implements an innovative approach to RWA tokenization with a flexible hook system and two-phase deposit mechanisms. However, several critical vulnerabilities must be addressed before the protocol can be considered production-ready. The most concerning issues relate to reentrancy vulnerabilities, oracle manipulation risks, and potential precision loss in financial calculations.

The development team should prioritize fixing the critical and high-severity issues identified in this report and consider implementing additional safety mechanisms such as emergency pauses and timelocks for sensitive operations.