# FountFi Solidity Codebase – Security Audit Report

*Date: 2025-06-02*
*Commit Hash: 3a3582434591a8bada79a3bb3f13b28b2b5502d5*

## 1. Executive Summary
FountFi engaged o3-Audit to perform a comprehensive security review of the smart–contract suite located under `src/`.  The review was conducted over **all Solidity contracts** published in the repository and focused on correctness, security, upgrade-safety and best-practice compliance.

A total of **9 issues** were identified:

| ID | Severity | Title |
|----|----------|-------|
| H-01 | High | Re-entrancy in custom `_deposit/ _withdraw` flows |
| H-02 | High | Accounting inexact for fee-on-transfer / deflationary assets |
| M-01 | Medium | EIP-712 signature malleability in `ManagedWithdrawReportedStrategy` |
| M-02 | Medium | Lack of validation for asset decimals |
| M-03 | Medium | Deposit-ID collisions possible in `GatedMintRWA` |
| L-01 | Low | Centralised control over price oracle / share pricing |
| L-02 | Low | Hook governance – potential bypass via re-order/removal |
| L-03 | Low | `Conduit.rescueERC20()` may withdraw user funds |
| L-04 | Low | Gas & style observations |

No critical-severity findings were detected.  Two high-severity issues demand code changes before main-net deployment.  Medium & Low issues should be triaged according to risk-appetite.

## 2. Scope
All contracts under `src/**` (≈ 30 contracts) plus directly-interacting Solady libraries were inspected.  Off-chain helpers (`utils/withdrawalUtils.js`, tests, mocks) were **out of scope** except where relevant.

## 3. Methodology
1. Manual line-by-line review of each contract.
2. Architectural analysis of trust-relationships between **Strategy ↔ Token ↔ Registry ↔ Conduit**.
3. Attack-surface modelling inc. re-entrancy, permission-escalation, price-oracle manipulation, overflow/underflow, DoS and griefing.
4. Automated fuzz / static tools (Slither, Echidna) to corroborate hypotheses.
5. Threat classification using the OWASP Smart-Contract Security Matrix; severity derived from **Likelihood × Impact**.

## 4. Detailed Findings
### H-01  Re-entrancy in custom `_deposit` / `_withdraw` logic
Severity: **High**   Likelihood: High   Impact: High

The bespoke overrides in `tRWA`, `ManagedWithdrawRWA`, and `GatedMintRWA` perform **external calls _before_ state-changes are complete and without a re-entrancy lock**.

Example (deposit path):
```153:177:src/token/tRWA.sol
    function _deposit(address by, address to, uint256 assets, uint256 shares) internal virtual override {
        ...
        Conduit(...).collectDeposit(asset(), by, strategy, assets); // EXTERNAL CALL ➜ user-controlled ERC20
        _mint(to, shares);                                         // state-change happens _after_ the call
        ...
    }
```
`collectDeposit` internally invokes `SafeTransferLib.safeTransferFrom`, re-entering the **arbitrary** ERC-20 token contract.  A malicious or specially-crafted ERC-20 can call back into `tRWA.deposit()` (or `withdraw()`) and manipulate balances before the first call finishes → double-mint, share inflation, or DoS.

The same pattern exists in custom `_withdraw`, where an external transfer to the user happens _after_ shares are burned:
```174:206:src/token/tRWA.sol
        _burn(owner, shares);
        SafeTransferLib.safeTransfer(asset(), to, assets); // EXTERNAL CALL
```

**Proof-of-Concept**
1. Deploy an ERC-20 that, inside `transferFrom`, calls `tRWA.deposit()` again.
2. Provide minimal allowance and call initial `deposit` → re-entrant invocation mints shares twice for only one transfer of assets (depending on timing).

**Recommendation**
• Add `ReentrancyGuard` (Solady provides both standard and transient versions).
• Follow Checks-Effects-Interactions: move `_mint/_burn` _before_ external calls where feasible.
• Where external token must be transferred first (to collect assets) store a local `uint256 initialTotalSupply` and enforce invariants after the call.

**Resolution**
Fixed in `0de35041e802f5b7ab878905162fcd12f38d2e85`.

---
### H-02  Incorrect accounting with fee-on-transfer / deflationary tokens
Severity: **High**   Likelihood: Medium   Impact: High

Throughout the system asset movements assume **1 : 1** accounting:
```153:177:src/token/tRWA.sol
Conduit.collectDeposit(asset(), by, strategy, assets);
```
`collectDeposit` trusts that `assets` tokens actually arrived, yet fee-on-transfer tokens (e.g.
USDT, *some* bridged assets) will deliver fewer units, causing share-over-issuance and enabling value extraction.

Similarly `_collect()` and Escrow flows use `safeTransferFrom/ safeTransfer` without balance-difference checks.

**Recommendation**
• Forbid non-standard ERC-20 by checking `balanceOf(strategy)` before & after transfers, or whitelist known good tokens.
• Alternatively, calculate actual received amount and base share-mint on that value.

**Resolution**
Acknowledged, the protocol won't support fee-on-transfer tokens for deposit assets.

---
### M-01  Signature malleability in `ManagedWithdrawReportedStrategy`
Severity: **Medium**   Likelihood: Medium   Impact: Medium

EIP-712 verification omits *malleability* checks on `s` and `v`.  Attackers can craft alternative `(r,s,v)` pairs producing the same signer, enabling **nonce reuse bypass** when backend signs "cancelled" requests.

```150:196:src/strategy/ManagedWithdrawRWAStrategy.sol
address signer = ecrecover(digest, signature.v, signature.r, signature.s);
```

**Recommendation**
• Reject signatures where `s > secp256k1n ÷ 2` and `v` ∉ {27,28}.  (`ECDSA.recover()` from OZ already enforces this.)

**Resolution**
Fixed in `5274c4a67d9c67bbb27fd49d5a57c42814e9b48c`.

---
### M-02  Missing validation of asset decimals
Severity: **Medium**   Likelihood: Medium   Impact: Medium

The constructor accepts `_assetDecimals` but never validates it versus the real ERC-20:
```60:95:src/token/tRWA.sol
    _assetDecimals = assetDecimals_;
```
Supplying an incorrect value (malicious deployer or mis-configured registry) skews conversion maths and **inflates or deflates share price**.

**Recommendation**  Query `ERC20(asset_).decimals()` during initialization (via `try/catch`) and revert on mismatch.

**Resolution**
Acknowledged, will be handled by double-checking `Registry#setAsset` configurations.

---
### M-03  Deposit ID collision in `GatedMintRWA`
Severity: **Medium**   Likelihood: Low   Impact: Medium

`depositId` is `keccak256(by,to,assets, block.timestamp, address(this))`:
```90:105:src/token/GatedMintRWA.sol
bytes32 depositId = keccak256(abi.encodePacked(by,to,assets,block.timestamp,address(this)));
```
Because `block.timestamp` has 1-second granularity, an attacker **front-runs** another user in the same block with identical parameters, resulting in identical `depositId` and overwriting Escrow data.

**Recommendation**
Include `msg.sender` *nonce* or an incrementing counter in the hash; alternatively revert if `pendingDeposits[depositId]` already exists.

---
### L-01  Centralisation – single-source price oracle
Severity: **Low**   Likelihood: Medium   Impact: High

`ReportedStrategy.balance()` relies entirely on `BaseReporter.report()`; `PriceOracleReporter` allows **owner-set updaters** to arbitrarily change `pricePerShare`, influencing exchange-rate for all deposits / redemptions.

While perhaps intended, this introduces a trust requirement.  A compromised updater could set `pricePerShare = 0` and steal liquidity via cheap deposit-mint or expensive redemption.

**Recommendation**  Consider multi-sig guarded updates, on-chain TWAP/PT oracle, or consensus of multiple reporters.

**Resolution**
Acknowledged, the `updater` function will be controlled by a multisig with off-chain protections against malicious updates.

---
### L-02  Hook governance race conditions
Severity: **Low**

Functions `removeOperationHook` and `reorderOperationHooks` lack checks for hooks **currently executing**.  An admin could reorder during a re-entrant call chain causing storage inconsistencies.

**Resolution**
Fixed in `c900cdfbdfda10713eabd31e4504ff0ed3166405`, by adding reentrancy guards to hook management operations.

---
### L-03  `Conduit.rescueERC20()` may withdraw user funds
Severity: **Low**

Protocol admin can arbitrarily move *any* token from the Conduit, potentially draining still-in-flight deposits if performed maliciously or by compromised admin.

Recommendation: only allow rescue of tokens **not equal to allowed assets** or route through governance.

**Resolution**
Acknowledged, the design of the conduit is such that it should never hold funds between transctions, so any stuck funds will result from nonstandard operation, and will need "rescue".

---
### L-04  Minor / Gas / Style
* Unused errors (`AssetDecimalsTooHigh`).
* Default-deny design in `KycRulesHook` may break integrations.
* Consider `unchecked` blocks for loop increments (already used in some libs).

## 5. Recommendations Summary
1. **Add `ReentrancyGuard`** or adopt check-effects-interactions.
2. Enforce **token decimal & transfer-fee correctness**.
3. Harden signature validation with OpenZeppelin `ECDSA`.
4. Strengthen oracle & admin controls (multi-sig / timelock).
5. Resolve medium & low issues per priority.

## 6. Appendix – Severity Definitions
• **High** – exploitable bug leading to loss of funds or control.
• **Medium** – bugs that can cause incorrect accounting or impact some users.
• **Low** – edge-case, best-practice, or trust assumptions.

---
*Report prepared by **o3-Audit***