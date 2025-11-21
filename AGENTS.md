# Repository Guidelines

## Project Structure & Module Organization

- `src/` contains production Solidity contracts; subdirectories such as `compounder/`, `strategies/`, `swap_adapters/`,
  and `interfaces/` group protocol domains and shared types.
- `test/` mirrors runtime modules via `unit/`, `forked/`, `invariant/`, and `utils/`; add new cases beside the contract
  they cover.
- `script/` holds Foundry deployment flows (`Deployments*.s.sol`, helpers under `utils/`), and `scripts/` exposes Python
  utilities for address management.
- Deployment metadata lands in `deployments/`, generated ABIs in `abis/`, and the local `forge-deploy/` binary is
  versioned for reproducible releases.

## Build, Test, and Development Commands

- `pnpm build`: regenerate deployer wrappers, must be run to generate the deployer functions before being able to use
  them.
- `pnpm test`: full suite; narrow via `--match-path`.
- `pnpm coverage`: emit `lcov.info`.
- `pnpm lint` / `pnpm lint:fix`: `forge fmt`, `solhint`, `prettier`.
- `pnpm slither`, `pnpm semgrep`: static analysis.
- `pnpm deployLocal`: dry-run upgrades on Anvil fork.

## Deployment Script Debugging (Anvil fork)

1. Start a clean fork

   - `pkill -f "anvil --fork-url" || true`
   - `anvil --fork-url "$MAINNET_RPC_URL" --auto-impersonate`

2. Mirror mainnet deployments

   - `rm -rf deployments/1-fork && mkdir -p deployments/1-fork && cp -a deployments/1/. deployments/1-fork/`

3. Run the script in fork context

   - `DEPLOYMENT_CONTEXT=1-fork forge script script/oneshot/DeployAutoUSDCompounder.s.sol --rpc-url http://localhost:8545 --broadcast -vvv`

4. Validate in logs

   - Required infra deployed once and wired (e.g., expected-out calculator, slippage/price checker) if applicable.
   - Risk controls configured (e.g., max slippage/deviation) to intended values.
   - Roles/permissions set per constants (keeper, emergency admin, AccessControl roles as applicable).
   - Ownership handover initiated (e.g., set pending owner / timelock); acceptance may be manual on live net.
   - Sanity check: representative swap/route produces non-zero expectedOut and price checker validation passes.

5. Common pitfalls
   - Use a real sender for live runs: `--sender <EOA>` or `FOUNDRY_SENDER`.
   - Stale artifacts: `forge clean`.
   - Before calling privileged functions on forks, inspect which `AccessControl` role guards the selector (e.g.,
     BasketManager’s `setTokenSwapAdapter` uses `TIMELOCK_ROLE`) and `vm.prank` as the current role holder (timelock,
     ops multisig, etc.) rather than assuming the community multisig has permission.

Notes

- Integration scripts should treat the deployed target as already configured; avoid redeploying shared infra.
- Git hygiene: `git diff` → `pnpm lint:fix` → `git commit -S` → `git push --force-with-lease`.

## Coding Style & Naming Conventions

- `forge fmt` enforced: 4-space, 120 cols, double quotes, sorted imports.
- Contracts/libraries: `PascalCase`; interfaces: `IName`; helpers/functions: `camelCase`; constants: `UPPER_SNAKE_CASE`.
- Honor `solhint` configs; run `prettier` on JSON/Markdown/YAML.

## Testing Guidelines

- Unit tests in `test/unit`; fork/integration in `test/forked` with clear setup.
- Invariants in `test/invariant`; run when changing shared state/storage.
- Capture fuzz assumptions inline; check coverage deltas.

## Commit & Pull Request Guidelines

- Conventional Commits, one concern per commit.
- Ensure `pnpm build`, `pnpm test`, `pnpm lint` pass; include gas/coverage notes.
- Call out storage/upgrade impacts and deployment checklist; keep artifacts out of PRs; CI+Codecov green.

## Security & Configuration Tips

- Mainnet: `DEPLOYMENT_CONTEXT=1`, real `--sender`, `API_KEY_ETHERSCAN` for verification.
- Post-deploy: finalize ownership/role acceptance per governance (multisig/timelock); `forge clean` as needed.
