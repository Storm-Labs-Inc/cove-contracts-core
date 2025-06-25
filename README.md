# cove-contracts-core

![cove](./assets/cove.png)

<div align="center">

[![codecov](https://codecov.io/gh/Storm-Labs-Inc/cove-contracts-core/branch/master/graph/badge.svg?token=PSFDZ17DDG)](https://codecov.io/gh/Storm-Labs-Inc/cove-contracts-core)
[![CI](https://github.com/Storm-Labs-Inc/cove-contracts-core/actions/workflows/ci.yml/badge.svg)](https://github.com/Storm-Labs-Inc/cove-contracts-core/actions/workflows/ci.yml)
[![Discord](https://img.shields.io/discord/1162443184681533470?logo=discord&label=discord)](https://discord.gg/xdhvEFVsE9)
[![X (formerly Twitter) Follow](https://img.shields.io/twitter/follow/cove_fi)](https://twitter.com/intent/user?screen_name=cove_fi)

</div>

This repository contains the core smart contracts for the Cove Protocol.

The testing suite includes unit, integration, fork, and invariant tests.

For more detailed information, visit the [documentation](https://docs.cove.finance/) or the
[technical RFC](https://docs.cove.finance/technical/cove/rfc).

> [!IMPORTANT]
> You acknowledge that there are potential uses of the [Licensed Work] that
> could be deemed illegal or noncompliant under U.S. law. You agree that you
> will not use the [Licensed Work] for any activities that are or may
> reasonably be expected to be deemed illegal or noncompliant under U.S. law.
> You also agree that you, and not [Storm Labs], are responsible for any
> illegal or noncompliant uses of the [Licensed Work] that you facilitate,
> enable, engage in, support, promote, or are otherwise involved with.

## Prerequisites

Ensure you have the following installed:

- [Node.js](https://nodejs.org/) (v20.15.0)
- [Python](https://www.python.org/) (v3.9.17)

## Installation

Setup [pyenv](https://github.com/pyenv/pyenv?tab=readme-ov-file#installation) and install the python dependencies:

```sh
pyenv install 3.9.17
pyenv virtualenv 3.9.17 cove-contracts-core
pyenv local cove-contracts-core
pip install -r requirements.txt
```

Install node and build dependencies:

```sh
# Install node dependencies
pnpm install
# Install submodules as soldeer dependencies
forge soldeer install
```

## Usage

Build the contracts:

```sh
pnpm build
```

Run the tests:

```sh
pnpm test
```

### Run slither static analysis

[Install slither](https://github.com/crytic/slither?tab=readme-ov-file#how-to-install) and run the tool:

```sh
pnpm slither
```

To run the [upgradeability checks](https://github.com/crytic/slither/wiki/Upgradeability-Checks) with
`slither-check-upgradeability`:

```sh
pnpm slither-upgradeability
```

### Run semgrep static analysis

[Install semgrep](https://github.com/semgrep/semgrep?tab=readme-ov-file#option-2-getting-started-from-the-cli) and run
the tool:

```sh
pnpm semgrep
```

## Deploying contracts to live network

### Local mainnet fork

```sh
# Run a fork network using anvil
anvil --fork-url <rpc_url> --fork-block-number <block_num> --auto-impersonate
```

Keep this terminal session going to keep the fork network alive.

Then in another terminal session:

```sh
# Deploy contracts to local fork network
pnpm deployLocal
```

This command uses the `deployLocal` script defined in `package.json`. It sets the `DEPLOYMENT_CONTEXT` to `1-fork` and runs the `forge` script `script/Deployments.s.sol` with the specified RPC URL, broadcasting the transactions, and syncing the deployment using `forge-deploy`. The sender address set to COVE_DEPLOYER and is unlocked for local deployment.

- Deployments will be in `deployments/<chainId>-fork`.
- Make sure not to commit `broadcast/`.
- If trying to deploy a new contract, either use the default deployer functions or generate them with:
  `$ ./forge-deploy gen-deployer`.

## Contract Architecture

![architecture](./assets/architecture.png)

## Basket Tokens

Basket tokens are ERC-4626 compliant vault tokens that represent a diversified portfolio of underlying assets. They implement the ERC-7540 standard for asynchronous deposits and redemptions, allowing for efficient management of multi-asset baskets.

### Key Features

#### Asynchronous Deposit/Redeem Mechanism
- **Two-Step Process**: Users first request deposits/redemptions, which are then fulfilled during the next rebalance cycle
- **Request IDs**: Each deposit/redeem request is assigned a unique ID for tracking
- **Controller Model**: Supports delegation where operators can manage positions on behalf of controllers

#### Rebalancing Process
1. **Proposal Phase**: Rebalance proposers initiate rebalancing for baskets that deviate from target weights
2. **Token Swap Phase**: Internal trades between baskets and external trades via adapters are proposed and executed
3. **Completion Phase**: Pending deposits/redemptions are fulfilled, and basket weights are adjusted

#### Asset Management
- **BitFlag System**: Each basket uses a bitflag to select eligible assets from the AssetRegistry
- **Weight Strategies**: Target weights are determined by strategy contracts (AutomaticWeightStrategy or ManagedWeightStrategy)
- **Dynamic Asset Universe**: Assets can be added/removed from baskets by updating the bitflag

#### Fee Structure
- **Management Fees**: Continuously accruing fees (max 30%) harvested during rebalances
- **Swap Fees**: Applied during rebalancing trades (max 5%)

### Important Integration Considerations

#### Griefing Protection
When integrating BasketToken into other contracts, be aware of a potential griefing vector:
- An attacker can call `requestDeposit` or `requestRedeem` with dust amounts, specifying another user as the controller
- This prevents the target controller from making new requests until they claim the pending request
- **Recommendation**: Always check for and claim any pending/claimable deposits or redemptions before making new requests

#### Fallback Mechanisms
- **Failed Deposits**: If a deposit cannot be fulfilled, users can claim back their original assets via `claimFallbackAssets`
- **Failed Redemptions**: If a redemption cannot be fulfilled, users can claim back their shares via `claimFallbackShares`

#### Pro-Rata Redemption
- **Emergency Exit**: Users can bypass the asynchronous process using `proRataRedeem`
- **Immediate Settlement**: Receives a proportional share of all basket assets
- **Use Cases**: Exiting baskets with paused assets or when rebalancing is not possible

### Lifecycle Example

1. **User deposits assets**:
   ```solidity
   basketToken.requestDeposit(amount, controller, owner);
   ```

2. **Wait for rebalance** (typically within 15-60 minutes)

3. **Claim shares after fulfillment**:
   ```solidity
   basketToken.deposit(amount, receiver, controller);
   ```

4. **For redemptions**:
   ```solidity
   basketToken.requestRedeem(shares, controller, owner);
   // After rebalance...
   basketToken.redeem(shares, receiver, controller);
   ```

### Token Naming Convention
- **Name**: Prefixed with "Cove " (e.g., "Cove USD")
- **Symbol**: Prefixed with "cove" (e.g., "coveUSD")

## Audits

Smart contract audits of the Cove Protocol are available [here](https://github.com/Storm-Labs-Inc/cove-audits).
