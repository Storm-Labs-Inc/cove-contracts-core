# Technical Context: Cove Asset Management Protocol

Reference: [Cove RFC](https://docs.cove.finance/technical/cove/rfc)

## Technology Stack

- Solidity (0.8.28 as per `BasketManager.sol` and other contracts).
- OpenZeppelin Contracts:
  - `AccessControlEnumerable` (in `BasketManager` for RBAC).
  - `SafeERC20` (used extensively for token interactions).
  - `Pausable` (in `BasketManager` for emergency stops).
  - `ReentrancyGuardTransient` (in `BasketManager`).
  - `Clones` (in `BasketManagerUtils` for creating `BasketToken` proxies).
  - `IERC20` interfaces.
- Euler Price Oracle (`euler-price-oracle/src/EulerRouter.sol`, `BaseAdapter.sol`, `ScaleUtils.sol`): For the underlying
  oracle infrastructure and adapter base classes.
  - Specific Adapters: `ERC4626Oracle.sol`, `ChainedERC4626Oracle.sol`, `CurveEMAOracleUnderlying.sol`,
    `AnchoredOracle.sol`.
- Solady (`@solady/utils/FixedPointMathLib.sol`): Used in `BasketManagerUtils` for fixed-point arithmetic.

## Key Dependencies & Libraries (Smart Contracts)

- **Core Protocol Contracts:**
  - `BasketManager.sol`: Central orchestrator.
  - `BasketToken.sol`: LP token implementation.
  - `BasketManagerUtils.sol`: Library for `BasketManager` logic.
  - `AssetRegistry.sol`: Manages allowed assets.
  - `FeeCollector.sol`: Manages protocol fees.
  - `Rescuable.sol`: For recovering mistakenly sent tokens.
  - `StrategyRegistry.sol` (in `src/strategies/`): Manages `WeightStrategy` contracts.
  - `WeightStrategy.sol` (interface and implementations in `src/strategies/`).
  - `TokenSwapAdapter.sol` (interface and implementations in `src/swap_adapters/`): For external trade execution.
- **External Libraries (as seen in imports):**
  - OpenZeppelin Contracts (various modules as listed above).
  - Euler Price Oracle contracts.
  - Solady FixedPointMathLib.
  - Forge-std (`console.sol` for debugging).

## Technical Constraints & Design Choices

1.  **Gas Optimization:** A primary concern. Achieved through:
    - Logic delegation to `BasketManagerUtils.sol`.
    - Internal trade matching (CoW) to avoid external gas costs.
    - Efficient data structures (e.g., mappings, arrays, `BasketManagerStorage` struct).
    - Careful use of loops and state access.
2.  **Security Considerations:**
    - Role-Based Access Control (`AccessControlEnumerable`) for sensitive functions.
    - Pausable mechanism for emergency situations.
    - Reentrancy protection (`ReentrancyGuardTransient`).
    - Use of `SafeERC20` for token transfers.
    - Custom errors for clear and gas-efficient reverts.
    - Oracle security (via `AnchoredOracle` and reliance on Euler framework).
    - Protection against specific attacks mentioned in RFC (e.g., `BasketToken` griefing).
    - `delegatecall` to `TokenSwapAdapter` is a critical security point, requiring trusted adapters.
    - `BasketManager.sol` constructor is `payable` but does not use `msg.value`.
    - `execute` function in `BasketManager` allows timelock to make arbitrary calls, requiring `target` not to be an
      active asset.
3.  **Modularity and Extensibility:**
    - `TokenSwapAdapter`s allow new trading venues.
    - `WeightStrategy` contracts allow different allocation logics.
    - Oracle system supports new adapter types.
4.  **Rebalance Mechanics:**
    - Defined states (`Status` enum in `BasketManagerStorage`).
    - Specific roles for proposing and executing parts of the rebalance.
    - Time delays (`_MIN_STEP_DELAY`, `_MAX_STEP_DELAY`, `stepDelay` in storage) between steps.
    - Retry limits (`_MAX_RETRY_COUNT`, `retryLimit` in storage).
    - Slippage (`_MAX_SLIPPAGE_LIMIT`, `slippageLimit`) and weight deviation (`_MAX_WEIGHT_DEVIATION_LIMIT`,
      `weightDeviationLimit`) controls.
5.  **Data Integrity:** Hashes used to ensure data consistency between rebalance steps (e.g., `externalTradesHash`,
    `basketHash`).

## Development & Testing Environment

- **Framework:** Foundry (indicated by `forge-std/console.sol` usage and typical project structure).
- **Static Analysis:** Slither (likely, given Slither comments in oracle code, though not explicitly in
  `BasketManager`).
- **Linter:** Solhint (likely, standard for Solidity projects).
- **Version Control:** Git.

## On-Chain Data Management

- `BasketManagerStorage.sol` defines a central struct `BasketManagerStorage` which holds most of the state for
  `BasketManager`, passed around using `storage pointer` (idiomatic for utils libraries).
- Key state variables include mappings for basket balances, fees, roles, and status of rebalances.

## Development Setup

- Foundry for testing and deployment
- Slither for static analysis
- Gas optimization tools
