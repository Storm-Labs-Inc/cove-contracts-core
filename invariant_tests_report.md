# 🧩 Invariant-Testing Coverage Report  

_(Generated from the current `test/invariant` suite)_

---

## 1. Overview  

The codebase contains two main invariant suites:

| Suite | Contract(s) under test | Key files |
|-------|-----------------------|-----------|
| **BasketManager** | `BasketManager`, its associated `BasketToken`s and strategies | `BasketManager.invariant.t.sol`, plus two thin wrappers (`BasketManager_integration…`, `BasketManager_staging…`) |
| **BasketToken** | Single `BasketToken` implementation in isolation | `BasketToken.invariant.t.sol` |

Both suites leverage Foundry’s `StdInvariant` with dedicated **handler contracts** that fuzz a broad set of user and privileged actions, then assert system-wide invariants after every call.

---

## 2. Current Invariants – Detailed Listing  

### 2.1 BasketManager Suite  

| # | Function | What it checks | Notes |
|---|----------|---------------|-------|
| 1 | `invariant_pauseStateConsistency` | Ghost var `isPaused` mirrors `BasketManager.paused()` | Ensures handler bookkeeping correctness |
| 2 | `invariant_assetConservation` | ∑ basket balances == on-chain `IERC20.balanceOf(BasketManager)` (when _not_ rebalancing) | Detects leakage/loss of assets |
| 3 | `invariant_oraclePathsAreValid` | Internal test-lib call to verify every configured oracle returns non-zero quote | Guards stale/removed oracles |
| 4 | `invariant_basketRegistrationConsistency` | `numOfBasketTokens`, `basketTokens()` array & `basketTokenToIndex` mapping stay in sync | Prevents phantom / orphaned baskets |
| 5 | `invariant_knownBasketRegistrationConsistency` | For each basket: computed `basketId` ↔ address mapping round-trips; index exists | Stronger version of #4 |
| 6 | `invariant_configurationBounds` | Swap fee, stepDelay, retryLimit, slippageLimit, weightDeviationLimit, per-basket managementFee are within hard-coded limits | Guards governance against mis-config |
| 7 | `invariant_variableLink` | Each `BasketToken` stores correct `assetRegistry` & `basketManager` address | Detects proxy / upgrade mis-wires |
| 8 | `invariant_rebalanceStatusValidity` | Structural validity of `rebalanceStatus` (retryCount ≤ limit, zeroing when NOT_STARTED, hash presence, timestamps, etc.) | Large surface—prevents half-finished rebalances |
| 9 | `invariant_assetIndexConsistency` | For every basket, `getAssetIndexInBasket` is bijective and base asset matches token storage | Guards silent reorderings |
| 10 | `invariant_completeRebalance_revertsWhen_StepDelayIsNotMet` | Calls must revert if stepDelay has not elapsed | Time-gate enforcement |

**Handler fuzz actions (excerpt)**  
• 5 actors simulate: deposits, redeems (request / fulfill paths), fallback claims, rebalances (propose/execute/complete), pausing, weight updates, arbitrary `warpBy` time jumps, etc.  
• Ghost state tracks pending deposits/redeems & rebalance status to cross-check on-chain values.

---

### 2.2 BasketToken Suite  

| # | Function | What it checks | Notes |
|---|----------|---------------|-------|
| 1 | `invariant_basketManagerIsImmutableContractCreator` | `basketManager == BasketTokenHandler` (the deployer) | Ensures immutability wiring |
| 2 | `invariant_totalPendingDeposits` | Handler counter equals `BasketToken.totalPendingDeposits()` | Ghost vs on-chain |
| 3 | `invariant_totalPendingRedemptions` | Same for redemptions | — |
| 4 | `invariant_totalSupply` | Handler-tracked supply equals ERC20 `totalSupply()` | Detects inflation/deflation bugs |
| 5 | `invariant_requestIdProgression` | `nextDepositRequestId` even & ≥2; `nextRedeemRequestId` odd & ≥3 | Preserves ID ordering scheme |

**Handler fuzz actions**  
• 5 actors interact through all public BasketToken flows, including edge-case calls (preview functions expected to revert, partial fulfillments with zero, etc.).  
• Maintains local counters for deposits/redeems awaiting fulfill & those moved into fallback logic.  

---

## 3. Strengths of the Current Suite  

1. **Stateful Fuzzing Depth** – Handlers exercise multi-step workflows (deposit → rebalance → fulfill) rather than isolated calls.  
2. **Oracle & Timing Coverage** – Rebalance proposals force oracle timestamp updates and time-warp fuzzing.  
3. **Ghost-Variable Cross-Checks** – Mirrors critical aggregates (pending deposits, paused state) to validate internal accounting.  
4. **Config Guardrails** – Hard limits on fees/deviation prevent governance mis-configuration from slipping through.  

---

## 4. Gaps & Potential Improvements  

### 4.1 Missing or Weak Invariants  

| Area | Suggested invariant |
|------|---------------------|
| **Weight Normalisation** | For each basket & strategy, `Σ targetWeights == 1e18` (or allowed epsilon). |
| **Fee Accounting** | Collected swap / management fees should increase monotonically & never exceed reserve balances. |
| **Total Assets vs. Supply** | For every basket: `totalAssets() == (assets held – pendingRedemptions + pendingDeposits)` within tolerance. |
| **Epoch Monotonicity** | `rebalanceStatus.epoch` should only increment, never decrease/reset. |
| **Role Integrity** | Critical roles (`DEFAULT_ADMIN`, `REBALANCE_PROPOSER`, etc.) must have at least 1 non-zero holder at all times. |
| **Re-entrancy / Paused Gate** | When `paused == true`, all state-changing external calls (except `unpause`) must revert. Could be enforced with a universal selector list. |
| **ERC20 Allowance Safety** | After a redeem, allowances granted to external swap contracts should be cleared or remain bounded. |
| **Over-Collateralisation** | BasketManager’s asset balances should always cover outstanding share supply when valued via oracle prices. |
| **Rebalance Hash Integrity** | Re-computing `externalTradesHash` off-chain using stored trades should always equal on-chain hash. |
| **Liquidity Ceiling** | Individual asset exposure per basket stays below a configurable % of total basket value. |

### 4.2 Fuzzing Enhancements  

1. **Actor Diversity** – Randomise number of actors per run and include contracts (not just EOAs) to mimic proxy attacks.  
2. **Dynamic Asset Sets** – Clone baskets with varying asset counts/decimals to catch rounding bugs.  
3. **Randomised Fee/Config Updates** – Temporarily grant MANAGER role to a fuzz actor to update parameters within limits.  
4. **Edge-Case Decimals** – Include tokens with 6, 8, 18, and 0 decimals (e.g., wrapped BTC) to stress arithmetic.  
5. **Gas-Griefing Scenarios** – Force-send Ether to contracts, simulate out-of-gas callbacks on COW settlement to test graceful handling.  

### 4.3 Infrastructure / Readability  

* Break large `BasketManager.invariant.t.sol` (780 LOC) into logical modules (Pause, Registry, Rebalance, etc.) for maintainability.  
* Add NatSpec-style comments to invariants for documentation generation.  
* Parameterise constants (`ACTOR_COUNT`, `INITIAL_BALANCE`) via `.toml` so CI can run light & heavy variants.  

---

## 5. Recommendations & Next Steps  

1. **Add the high-impact invariants** listed in §4.1, prioritising weight normalisation and total-assets coverage, as they directly guard user funds.  
2. **Refactor test architecture**: extract shared helpers (oracle mocks, fee maths) into libraries consumed by both suites.  
3. **Continuous Fuzz Budget**: configure CI to run quick (5-10 runs) on every PR and full (10k runs, depth 128) nightly.  
4. **State Snapshotting**: Log failing seeds and deploy a script to replay minimal reproduction for easier debugging.  
5. **Documentation**: Generate an mdbook or foundry-docgen site with the invariant descriptions so auditors can map risk coverage.  

---

## 6. Conclusion  

The existing invariant tests already cover a meaningful slice of BasketManager and BasketToken safety properties, especially around **registration integrity, rebalance state-machine correctness, and accounting conservation**.  

However, critical financial-soundness checks (oracle-priced solvency, fee monotonicity, weight sum) and broader governance/role invariants are still absent. Addressing these gaps will materially strengthen assurance and reduce manual audit surface.