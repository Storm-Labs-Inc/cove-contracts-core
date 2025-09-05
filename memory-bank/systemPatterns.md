# System Patterns: Cove Asset Management Protocol

Reference: [Cove RFC](https://docs.cove.finance/technical/cove/rfc)

## System Architecture

The Cove protocol centers around the `BasketManager.sol` contract, which orchestrates asset management, including
deposits, withdrawals, rebalancing, and LP token (`BasketToken.sol`) management. It interacts with several other key
components:

```mermaid
flowchart TD
    User[🧑 User/LP] -->|Deposit/Withdraw| BM(BasketManager.sol)
    BM -.-> BT(BasketToken.sol)
    BM -- Manages & Custodies --> AssetsPool{User Assets Pool}

    subgraph Rebalancing Roles
        RP[👮 RebalanceProposer] --> BM
        TSP[👮 TokenSwapProposer] -->|Internal/External Trades| BM
        TSE[👮 TokenSwapExecutor] -->|Execute External Calldata| BM
        RE[🧑 RebalanceExecutor] -->|Complete Rebalance| BM
    end

    subgraph Strategy & Pricing
        WS[📄 WeightStrategy.sol] <-- Reads -- BM
        WP[👮 WeightProposer] --> WS
        OR(OracleRouter / EulerRouter) <-- Reads Price -- BM
        OR --- EO(ERC4626Oracle)
        OR --- CEO(ChainedERC4626Oracle)
        OR --- CO(CurveEMAOracle)
        OR --- AO(AnchoredOracle)
    end

    subgraph Trade Execution
        BM -- Internal Trades --> BM
        BM -- External Trades --> SA(TokenSwapAdapter.sol)
        SA -- e.g. --> CoWSwap[CoW Swap]
        SA -- e.g. --> DutchAuction[Dutch Auction Adapter]
    end

    BM -- Interacts --> AR(AssetRegistry.sol)
    BM -- Interacts --> FC(FeeCollector.sol)
    BM -- Utilizes --> BMU(BasketManagerUtils.sol)

    classDef contract fill:#f9f,stroke:#333,stroke-width:2px;
    classDef actor fill:#9cf,stroke:#333,stroke-width:2px;
    classDef system fill:#lightgrey,stroke:#333,stroke-width:2px;

    class BM,BT,WS,OR,EO,CEO,CO,AO,SA,CoWSwap,DutchAuction,AR,FC,BMU contract;
    class User,RP,TSP,TSE,RE,WP actor;
    class AssetsPool system;
```

**Core Components:**

- **`BasketManager.sol` (📄):** The central nervous system.
  - Handles deposits, withdrawals, minting/burning of `BasketToken`s.
  - Custodies all user assets in a commingled pool.
  - Orchestrates the entire rebalance lifecycle: proposing, trade execution (internal & external), and finalization.
  - Manages fees (management & swap) via `FeeCollector.sol`.
  - Interacts with `AssetRegistry.sol` to know valid assets.
  - Uses `OracleRouter` (EulerRouter) for pricing assets and LP tokens.
  - Delegates much of its complex accounting logic to `BasketManagerUtils.sol`.
  - Implements `Pausable` and `AccessControlEnumerable`.
- **`BasketToken.sol` (📄):** ERC-20 (potentially ERC4626-like features) LP token representing a user's share in a
  specific basket. Each `BasketToken` is tied to an immutable selection of assets and a `WeightStrategy`.
- **`WeightStrategy.sol` (📄):** Contract defining target asset allocations for one or more baskets. Managed by a
  `WeightProposer`.
- **`TokenSwapAdapter.sol` (📄):** Modular contracts for executing external trades (e.g., via CoW Swap, or a generic
  Dutch Auction adapter). `BasketManager` calls these via `delegatecall` to execute trades.
- **Oracle System (Based on `EulerRouter`):**
  - `EulerRouter` acts as the registry for various oracle adapters.
  - `ERC4626Oracle.sol`: Converts vault shares to underlying assets.
  - `ChainedERC4626Oracle.sol`: Handles chains of ERC4626 vaults.
  - `CurveEMAOracleUnderlying.sol`: Prices assets using Curve EMA.
  - `AnchoredOracle.sol`: Provides price validation by checking a primary oracle against an anchor.
- **`AssetRegistry.sol` (📄):** Manages a list of allowed/supported assets and their statuses (e.g., enabled, paused).
- **`FeeCollector.sol` (📄):** Handles the collection and distribution of protocol fees.
- **`BasketManagerUtils.sol` (📄):** Library contract containing much of the complex logic for accounting, rebalance
  processing, and trade settlement, keeping `BasketManager.sol` cleaner.

**Key Actors:**

- **User/LP (🧑):** Deposits assets into baskets, receives `BasketToken`s, and can withdraw assets.
- **`WeightProposer` (👮/📄):** Updates `WeightStrategy` contracts with new target weights.
- **`RebalanceProposer` (👮/📄):** Initiates the rebalance lifecycle in `BasketManager`.
- **`TokenSwapProposer` (👮):** Calculates optimal internal (CoW) and external trades and submits them to
  `BasketManager`. This is an off-chain role using linear programming as per the RFC.
- **`TokenSwapExecutor` (👮):** Submits calldata to `BasketManager` to execute the proposed external trades via the
  `TokenSwapAdapter`.
- **`RebalanceExecutor` (🧑):** Permissionlessly calls `BasketManager` to complete an ongoing rebalance once conditions
  are met (e.g., time delays, trades settled).

## Key Technical Decisions & Patterns

- **Intent Aggregation:** Users express high-level investment intent (assets + strategy), and the protocol optimizes
  execution.
- **Pooled Asset Management:** Assets are held centrally in `BasketManager`, enabling economies of scale for rebalancing
  and internal trade matching (CoW).
- **Off-Chain Trade Optimization:** The `TokenSwapProposer` (off-chain) uses linear programming to maximize internal CoW
  settlement, minimizing external slippage and fees.
- **Modular Swap Execution:** `TokenSwapAdapter` pattern allows plugging in various external trading venues (CoW Swap,
  Dutch Auctions, etc.). `BasketManager` uses `delegatecall` to interact with these adapters.
- **Structured Rebalance Lifecycle:** `BasketManager` enforces a multi-step rebalancing process (Propose Rebalance ->
  Propose Token Swap -> Execute Token Swap -> Complete Rebalance) with distinct roles and status transitions
  (`RebalanceStatus` struct, `Status` enum in `BasketManagerStorage.sol`).
- **Oracle Abstraction:** Uses `EulerRouter` to abstract oracle implementations, allowing for different pricing
  mechanisms (`ChainedERC4626Oracle`, etc.) and security layers (`AnchoredOracle`). Oracles must conform to EIP-7726
  (`IPriceOracle`).
- **Access Control:** Extensive use of `AccessControlEnumerable` in `BasketManager` for permissioned roles (e.g.,
  `_MANAGER_ROLE`, `_PAUSER_ROLE`, `_REBALANCE_PROPOSER_ROLE`, `_TOKENSWAP_PROPOSER_ROLE`, `_TOKENSWAP_EXECUTOR_ROLE`,
  `_TIMELOCK_ROLE`).
- **Pausability:** `BasketManager` is `Pausable` for emergency stops.
- **Reentrancy Guard:** `BasketManager` uses `ReentrancyGuardTransient`.
- **Library for Complex Logic:** `BasketManagerUtils.sol` encapsulates significant portions of the business logic,
  keeping the main `BasketManager.sol` contract more focused on state and access control.
- **Bit Flags for Asset Selection:** Baskets use a `bitFlag` to represent their selected set of assets, managed by
  `AssetRegistry.sol`.
- **Gas Optimization:**
  - Internal CoW trades avoid external gas costs.
  - Pooled rebalancing is more efficient than individual.
  - Careful state management and use of libraries.
- **Security Considerations from RFC:**
  - Dependency on correct oracle prices (mitigated by `AnchoredOracle`).
  - Assumptions about asset quality and standard token behavior.
  - Protection against griefing attacks on `BasketToken` deposits/redeems.
  - Off-chain monitoring and emergency pausing capabilities.

## Design Patterns

- **Facade Pattern:** `BasketManager.sol` acts as a facade for the complex asset management and rebalancing system.
- **Strategy Pattern:** `WeightStrategy.sol` contracts define different rebalancing strategies.
- **Adapter Pattern:** `TokenSwapAdapter.sol` and oracle adapters (`ChainedERC4626Oracle`, etc.) adapt external
  systems/logics to standardized interfaces.
- **Registry Pattern:** `AssetRegistry.sol` and `StrategyRegistry.sol` (from `BasketManagerStorage`) manage collections
  of approved assets and strategies.
- **Proxy Pattern (Implied for `BasketToken`):** `BasketToken` instances are created using
  `Clones.clone(self.basketTokenImplementation)` in `BasketManagerUtils.sol`, indicating a minimal proxy (clone)
  pattern.
- **Role-Based Access Control (RBAC):** Via OpenZeppelin's `AccessControlEnumerable`.
- **State Machine:** The rebalancing process in `BasketManager` follows a defined state machine (`Status` enum).

## System Architecture

The core of the system is the `
