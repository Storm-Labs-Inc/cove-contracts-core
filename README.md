# basket-manager

[![codecov](https://codecov.io/gh/Storm-Labs-Inc/cove-contracts-core/branch/master/graph/badge.svg?token=PSFDZ17DDG)](https://codecov.io/gh/Storm-Labs-Inc/cove-contracts-core)
[![CI](https://github.com/Storm-Labs-Inc/cove-contracts-core/actions/workflows/ci.yml/badge.svg)](https://github.com/Storm-Labs-Inc/cove-contracts-core/actions/workflows/ci.yml)

# Installation

Tested with node 18.16.1

```sh
# Install node dependencies
pnpm install
# Install submodules as soldeer dependencies
forge soldeer install
```

# Compilation

```sh
# Build contracts
pnpm build
# Run tests
pnpm test
```

# Deploying contracts to live network

## Local mainnet fork

```sh
# Run a fork network using anvil
anvil --rpc-url <fork_network_rpc_url>
```

Keep this terminal session going to keep the fork network alive.

Then in another terminal session:

```sh
# Deploy contracts to local fork network
pnpm localDeploy
```

- deployments will be in `deployments/<chainId>-fork`
- make sure to not commit `broadcast/`
- if trying to deploy new contract either use the default deployer functions or generate them with
  `$./forge-deploy gen-deployer`
