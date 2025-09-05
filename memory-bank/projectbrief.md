# Cove Protocol Project Brief

## Core Product: Cove Asset Management Protocol

Cove is an asset management protocol designed to maximize returns through intelligent automation. It aims to simplify
complex DeFi strategies into accessible, yield-bearing products for users. The protocol functions as an intent
aggregator for liquidity providers (LPs), allowing them to express investment preferences through "baskets" of
ERC-20/ERC4626 tokens, managed by specific weight strategies.

Reference: [Cove RFC](https://docs.cove.finance/technical/cove/rfc)

## Core Requirements

- **Basket Management:** Allow creation and management of "baskets," which are LP tokens representing a user's chosen
  combination of assets and a weight strategy.
- **Deposit & Withdrawal:** Handle user deposits into baskets and withdrawals from them, minting and burning
  `BasketToken` LP shares.
- **Asset Custody:** Securely hold user assets within the `BasketManager` contract.
- **Automated Rebalancing:** Implement a robust rebalancing lifecycle for baskets to maintain target asset allocations
  defined by their `WeightStrategy`. This includes:
  - Proposing rebalances.
  - Executing internal trades (Coincidence of Wants - CoW) to minimize external slippage and fees.
  - Executing external trades through integrated `SwapAdapter`s (e.g., CoW Swap).
  - Finalizing rebalances and updating internal accounting.
- **Fee Collection:** Implement configurable management and swap fees.
- **Oracle Integration:** Utilize a flexible oracle system (e.g., Euler Price Oracle with custom adapters like
  `ERC4626Oracle`, `ChainedERC4626Oracle`) for asset pricing during rebalancing and for LP token valuation.
- **Modular Design:** Employ a modular architecture with distinct contracts for `BasketManager`, `BasketToken`,
  `WeightStrategy`, `SwapAdapter`, and oracle components.
- **Access Control:** Implement granular access control for sensitive operations (e.g., pausing, setting fees, proposing
  rebalances).

## Project Scope

- Develop the core smart contracts for the Cove protocol, including:
  - `BasketManager.sol`: Central contract for deposits, withdrawals, asset custody, and rebalance orchestration.
  - `BasketToken.sol`: ERC-20/4626 compatible LP token representing shares in a basket.
  - `WeightStrategy.sol` (interfaces and implementations): Contracts defining target asset allocations.
  - `SwapAdapter.sol` (interfaces and implementations): Contracts for executing external trades.
  - Oracle adapters (e.g., `ChainedERC4626Oracle.sol`, `ERC4626Oracle.sol`).
  - Supporting contracts like `AssetRegistry.sol`, `FeeCollector.sol`.
- Ensure robust error handling, event emission, and security best practices.
- Develop comprehensive test coverage.
- Provide clear documentation.

## Technical Goals

1.  **Efficient Rebalancing:** Minimize value leakage (LVR, slippage, fees) during rebalancing by maximizing internal
    CoWs and using efficient external execution (e.g., CoW Swap).
2.  **Gas Optimization:** Optimize all user interactions and protocol operations for gas efficiency.
3.  **Security:** Build a secure system resistant to common DeFi vulnerabilities, including oracle manipulation and
    reentrancy.
4.  **Modularity & Extensibility:** Design contracts to be easily upgradeable and allow for new strategies, assets, and
    swap venues to be added.
5.  **Accurate Accounting:** Maintain precise internal accounting of asset balances per basket and user LP shares.

## Success Criteria

- The protocol successfully manages user deposits and allows for the creation of diverse baskets.
- Rebalancing operations execute efficiently, demonstrably reducing costs compared to naive individual rebalancing.
- The system is secure, validated by audits and extensive testing.
- Accurate pricing and LP share calculation.
- The protocol is well-documented and understandable for developers and users.
- The system can be paused and managed effectively in emergency situations.
