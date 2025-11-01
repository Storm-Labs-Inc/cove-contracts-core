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

- `pnpm build` regenerates deployer wrappers then runs `forge build --sizes`.
- `pnpm test` executes the full Foundry suite with gas report; narrow scope via
  `forge test --match-path test/unit/BasketManager.t.sol`.
- `pnpm coverage` produces LCOV output in `lcov.info` for Codecov uploads.
- `pnpm lint` (`forge fmt --check`, `solhint`, `prettier`) and `pnpm lint:fix` auto-correct common issues.
- `pnpm slither` and `pnpm semgrep` provide static analysis sign-off before security-sensitive merges.
- `pnpm deployLocal` targets an Anvil fork (`anvil --fork-url ...`) to dry-run end-to-end upgrades.

## Deployment Script Debugging (Anvil fork)

- Stop any existing Anvil and start fresh with visible logs:
  - `pkill -f "anvil --fork-url" || true`
  - `anvil --fork-url "$MAINNET_RPC_URL" --auto-impersonate`
- Sync fork deployments to mirror mainnet addresses:
  - `rm -rf deployments/1-fork && mkdir -p deployments/1-fork && cp -a deployments/1/. deployments/1-fork/`
- Run the deploy script against the fork with context:
  - `DEPLOYMENT_CONTEXT="1-fork" forge script script/oneshot/DeployAutoUSDCompounder.s.sol --rpc-url http://localhost:8545 --broadcast -vvv`
- Verify logs/guards from the script:
  - Price infra deployed once (UniV2ExpectedOutCalculator, DynamicSlippageChecker) and wired via `updatePriceChecker`.
  - `setMaxPriceDeviation(500)` applied (5% slippage bound).
  - `ITokenizedStrategy.setKeeper(...)` and `setEmergencyAdmin(...)` match constants.
  - Management set to `COVE_COMMUNITY_MULTISIG` via `setPendingManagement(...)` (acceptance may require multisig).
  - TOKE→USDC check uses 10,000 TOKE sizing: expectedOut > 0 and `priceChecker.checkPrice(...)` passes.
- Common issues
  - Foundry default sender warning: pass `--sender <EOA>` (or set `FOUNDRY_SENDER`) for real runs.
  - "Artifacts built from source files that no longer exist": run `forge clean`.
  - Import-path solhint warnings in scripts are informational; `pnpm lint:fix` to normalize style.
- Integration scripts: treat `AutopoolCompounder` as pre-configured; do not (re)deploy price/slippage checkers.
- Git hygiene for debug loops: `git diff` → `pnpm lint:fix` → `git commit -S -m "chore(lint): ..."` →
  `git push --force-with-lease`.

## Coding Style & Naming Conventions

- `forge fmt` enforces 4-space indents, 120-character lines, double quotes, and sorted imports; keep diffs
  formatter-clean.
- Contracts and libraries use `PascalCase`, interfaces `IName`, helpers and functions `camelCase`; constants in
  `constants/` stay `UPPER_SNAKE_CASE`.
- Respect repository `solhint` configs for security checks and run `prettier` on JSON/Markdown/YAML touched by a change.

## Testing Guidelines

- Place deterministic specs in `test/unit`; integration and fork flows live in `test/forked` with clear setup comments.
- Maintain invariant suites in `test/invariant`; run `forge test --match-contract Invariant` when touching shared state
  or storage.
- Capture new cheatcodes or fuzz assumptions inline and confirm coverage deltas with `pnpm coverage`.

## Commit & Pull Request Guidelines

- Use Conventional Commits (`type(scope?): summary`), e.g., `feat(compounder): add vault fee toggle`; align each commit
  to a single concern.
- Verify `pnpm build`, `pnpm test`, and `pnpm lint` locally; include gas or coverage notes in the PR description.
- Reference related issues or audits, describe storage or upgrade impacts, and call out deployment checklist items.
- Exclude local artifacts (`broadcast/`, `.env`, fork deployments) and ensure CI plus Codecov are green before
  requesting review.

## Security & Configuration Tips

- Mainnet runs: set `DEPLOYMENT_CONTEXT=1`, pass a real `--sender`, and export `API_KEY_ETHERSCAN` for verification.
- Post-deploy: coordinate `acceptManagement()` from `COVE_COMMUNITY_MULTISIG`; clean via `forge clean` as needed.
