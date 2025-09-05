# Product Context: Cove Asset Management Protocol

Reference: [Cove RFC](https://docs.cove.finance/technical/cove/rfc)

## Problem Solved: Limitations of Traditional AMMs for Portfolio Management

Traditional Automated Market Makers (AMMs) are not optimally suited for portfolio or index construction. They often
suffer from Loss-Versus-Rebalancing (LVR), where liquidity providers (LPs) incur losses due to toxic order flow (trades
executing at worse-than-market prices). Research (e.g., Loesch et al., 2021; Heimbach et al., 2022, as cited in the RFC)
has shown that LPs in some popular AMMs might have been better off simply holding their assets rather than providing
liquidity, especially for retail users in sophisticated AMMs like Uniswap V3.

Cove proposes an alternative solution to eliminate LVR and ensure better execution for LPs, aiming for at least general
intent-level execution (similar to CoW Swap).

## How Cove Works: Intent Aggregation and Optimized Rebalancing

Cove functions as an **intent aggregator** for LPs. Users express their investment intent by:

1.  Choosing a **Weight Strategy** (e.g., Gauntlet-optimized yield, market-cap weighted index, custom weights).
2.  Selecting a combination of **ERC-20 / ERC-4626 tokens**.

These choices form a **basket**, represented by a `BasketToken` (an LP token). By limiting the number of strategy and
token options, the protocol can efficiently aggregate deposits.

The **`BasketManager.sol`** contract is the core of the protocol. It handles:

- User deposits and withdrawals.
- Custody of all user assets in a pooled manner.
- Management of the rebalance lifecycle.

**Key Advantages of Pooled Assets:**

- **Optimized Rebalancing:** Rebalancing occurs at the protocol level, which is cheaper than individual basket
  rebalancing.
- **Increased Value Capture:** Internal matching of trades (Coincidence of Wants - CoW) between baskets during
  rebalancing. This is achieved by an off-chain **TokenSwapProposer** using linear programming to maximize CoW volume.
  Matched trades execute without price impact, slippage, fees, or MEV from external liquidity sources.

**Rebalancing Process:**

1.  **Weight Updates:** `WeightProposer` actors update their respective `WeightStrategy` contracts.
2.  **Rebalance Proposal:** A `RebalanceProposer` initiates the rebalance lifecycle. Deposits and withdrawals for
    affected baskets are temporarily paused.
3.  **Trade Calculation:** A `TokenSwapProposer` (permissioned actor) calculates an optimized set of internal (CoW) and
    external trades and submits them to `BasketManager`.
4.  **Trade Execution:**
    - Internal trades are settled directly by `BasketManager`.
    - External trades are routed through `SwapAdapter`s (e.g., CoW Swap, which supports programmatic orders like TWAP)
      by a `TokenSwapExecutor` to ensure best execution and capture positive slippage.
5.  **Rebalance Finalization:** A permissionless `RebalanceExecutor` completes the rebalance, advancing the epoch.
    Tracked balances within `BasketManager` are updated.

**Oracle Usage:**

- The protocol uses a pluggable oracle system (based on `euler-price-oracle`) to value baskets and settle internal
  trades. This includes adapters like:
  - `ERC4626Oracle`: For direct ERC4626 vault share-to-asset conversion.
  - `ChainedERC4626Oracle`: For nested ERC4626 vaults (max depth 10).
  - `CurveEMAOracleUnderlying`: For Curve pool prices.
- The `AnchoredOracle` is a primary implementation, validating a primary oracle against an anchor to prevent
  stale/manipulated prices.

## User Experience Goals

- **Maximized Returns:** Through intelligent automation, optimized rebalancing, and reduced value leakage.
- **Accessibility:** Simplify complex DeFi strategies into user-friendly, yield-bearing products.
- **Efficiency:** Lower gas costs for users due to pooled rebalancing and internal trade matching.
- **Transparency:** Clear fee structures (management and swap fees) and rebalancing processes.
- **Security:** Robust system with safeguards like pausable contracts, oracle monitoring, and adherence to EIP-7726 for
  oracles.

## Important Considerations (from RFC & Oracles)

- **Oracle Dependency:** Correctness relies on accurate external oracle prices. `AnchoredOracle` provides a layer of
  safety.
- **External Assumptions:**
  - `TokenSwapProposer` uses on-chain oracle rates (not live quotes) for proposing trades.
  - Assumes high-quality, liquid assets with minimal depeg risk.
  - Designed for standard ERC-20/4626 tokens (not fee-on-transfer or rebasing tokens unless explicitly handled).
- **Underlying ERC4626 Vault Security:** For oracles like `ChainedERC4626Oracle`, accuracy depends on the security of
  the underlying vaults (e.g., protection against donation attacks).
- **Potential Griefing Attack (BasketToken):** Integrators of `BasketToken` should check for pending deposits/redeems
  before new requests to prevent a griefing vector mentioned in the RFC.
