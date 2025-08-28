Below is a concrete technical specification for a **Yearn V3 Tokenized Strategy** that accepts **Tokemak autoUSD** as the ERC‑4626 `asset`, stakes it in **Tokemak’s AutopoolMainRewarder**, periodically **claims** rewards, uses **Milkman** to **asynchronously swap** rewards (e.g., **TOKE**) to **USDC**, then **deposits USDC into the autoUSD Autopool** to mint additional autoUSD and **re‑stake**, compounding via `report()`/`_harvestAndReport()`.

---

## 0) Decisions & scope (confirmed)

- **Deposits:** accept **autoUSD only** (no USDC deposits at the ERC‑4626 interface). Internal USDC is only used during harvest to mint autoUSD.
- **Access control:** use **Yearn TokenizedStrategy’s** built‑in roles (`management`, `keeper`, `emergencyAdmin`). No custom multisig/timelock/pausable beyond what Yearn provides. ([docs.yearn.fi](https://docs.yearn.fi/developers/v3/strategy_writing_guide))
- **Milkman:** support **multiple reward tokens** (open‑ended). Add a **protected** `updatePriceChecker(fromToken, checker)`; **revert** when `fromToken == asset` to prevent adding a checker for autoUSD (the base asset). ([docs.cow.fi](https://docs.cow.fi/cow-protocol/concepts/order-types/milkman-orders), [GitHub](https://github.com/charlesndalton/milkman))
- **Harvesting:** triggered **off‑chain by a keeper** (Yearn `keeper`) calling `report()` (and optionally `tend()` for maintenance). ([docs.yearn.fi](https://docs.yearn.fi/developers/v3/strategy_writing_guide))

---

## 1) External components and addresses

| Component | Purpose | Mainnet reference |
| --- | --- | --- |
| **Yearn TokenizedStrategy / BaseStrategy** | Provides ERC‑4626 vault logic, roles, and the hooks we must implement (`_deployFunds`, `_freeFunds`, `_harvestAndReport`). | Docs: TokenizedStrategy & Strategy Writing Guide. ([docs.yearn.fi](https://docs.yearn.fi/developers/smart-contracts/V3/TokenizedStrategy)) |
| **autoUSD Autopool (ERC‑4626)** | The **asset** of our strategy. The vault’s **base asset is USDC**, deposits mint `autoUSD` shares. | autoUSD address `0xa756…0d35` (your link); ERC‑4626 list shows **autoUSD ↔ USDC**. ([Ethereum (ETH) Blockchain Explorer](https://etherscan.io/address/0xa7569a44f348d3d70d8ad5889e50f78e33d80d35), [web3-ethereum-defi.readthedocs.io](https://web3-ethereum-defi.readthedocs.io/tutorials/erc-4626-vault-list.html)) |
| **AutopoolMainRewarder** | Stakes the **autopool vault token** (autoUSD) and distributes rewards (e.g., TOKE). Exposes `stake(account, amount)`, `withdraw(account, amount, claim)`, `getReward(account, recipient, claimExtras)`, `rewardToken()`. | `0x7261…c27B` (your link); verified code shows these functions. ([Ethereum (ETH) Blockchain Explorer](https://etherscan.io/address/0x726104CfBd7ece2d1f5b3654a19109A9e2b6c27B)) |
| **Tokemak Autopilot Router (optional)** | Multicall convenience for deposit+stake; not required if we use raw ERC‑4626 deposit to autoUSD then call Rewarder directly. | Router docs; contract addresses page. ([Tokemak Autopilot](https://docs.tokemak.xyz/developer-docs/contracts-overview/autopool-eth-contracts-overview/autopilot-contracts-and-systems/autopilot-router)) |
| **USDC (ERC‑20)** | Swap target and base asset of autoUSD vault. | `0xA0b8…6eB48`. ([Ethereum (ETH) Blockchain Explorer](https://etherscan.io/address/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48)) |
| **Milkman** | On‑chain requester for **CoW Protocol** asynchronous swaps via **price checkers**. We’ll call `requestSwapExactTokensForTokens(...)`. | CoW docs showing signature & flow. ([docs.cow.fi](https://docs.cow.fi/cow-protocol/concepts/order-types/milkman-orders)) |
| **Price checkers (custom)** | Contracts implementing `IPriceChecker.checkPrice(...)` used by Milkman to validate solver‑supplied `minOut` using on‑chain oracles. | Milkman repo/docs. ([GitHub](https://github.com/charlesndalton/milkman)) |
| **Chainlink Feed Registry** | Source of canonical price feeds `(base, quote) → aggregator` on **Ethereum mainnet** for price checker logic. | Docs & address `0x47Fb…eeDf`. ([Chainlink Documentation](https://docs.chain.link/data-feeds/feed-registry), [Ethereum (ETH) Blockchain Explorer](https://etherscan.io/address/0x47fb2585d2c56fe188d0e6ec628a38b74fceeedf)) |

> Note on TOKE/USD: If there is no direct Chainlink TOKE/USD feed on mainnet, the Chainlink‑based price checker must derive TOKE/USDC using safe composition (e.g., a DEX TWAP for TOKE/ETH combined with Chainlink ETH/USD and USDC/USD), or use Chainlink Data Streams where available. The design below allows slotting-in a PriceChecker per reward token accordingly. (Chainlink Documentation, data.chain.link)
> 

---

## 2) High‑level architecture

**Strategy type:** A **Yearn V3 TokenizedStrategy** whose `asset` is **autoUSD** (an ERC‑4626 vault token). Deposits **autoUSD** and immediately **stakes** to Tokemak’s **AutopoolMainRewarder**. ([docs.yearn.fi](https://docs.yearn.fi/developers/v3/strategy_writing_guide), [Ethereum (ETH) Blockchain Explorer](https://etherscan.io/address/0x726104CfBd7ece2d1f5b3654a19109A9e2b6c27B))

**Compounding loop (keeper‑driven):**

1. **Claim** rewards from `AutopoolMainRewarder` → strategy receives reward tokens (e.g., **TOKE**, possibly extras). ([Ethereum (ETH) Blockchain Explorer](https://etherscan.io/address/0x726104CfBd7ece2d1f5b3654a19109A9e2b6c27B))
2. For each configured **reward token**, call **Milkman** `requestSwapExactTokensForTokens(amountIn, reward, USDC, to=strategy, priceChecker, priceCheckerData)`; the **price checker** validates `minOut` vs Chainlink (or composite) oracle. The swap **settles asynchronously** via CoW solvers. ([docs.cow.fi](https://docs.cow.fi/cow-protocol/concepts/order-types/milkman-orders), [GitHub](https://github.com/charlesndalton/milkman))
3. On each harvest, **deposit any settled USDC** directly into **autoUSD** (ERC‑4626) to mint new `autoUSD` shares, then **stake** those shares back into the Rewarder. ([Tokemak Autopilot](https://docs.tokemak.xyz/developer-docs/contracts-overview/autopool-eth-contracts-overview/autopilot-contracts-and-systems/autopools))
4. Return total autoUSD held (loose + staked) from `_harvestAndReport()` for accounting/fees. ([docs.yearn.fi](https://docs.yearn.fi/developers/v3/strategy_writing_guide))

> Tokemak docs confirm LATs (receipt tokens like autoUSD) are staked for TOKE incentives, and Autopools are ERC‑4626(+Permit) with base asset deposits (USDC for autoUSD). Our design conforms with “deposit base asset → mint LAT, stake LAT to Rewarder”. (Tokemak Autopilot)
> 

---

## 3) Core contracts & interfaces

### 3.1 Strategy contract (inherits Yearn `BaseStrategy`)

- **Constructor params**
    - `IERC4626 autoUSD` (strategy `asset`)
    - `IAutopoolMainRewarder rewarder` (e.g., `0x7261…c27B`)
    - `IERC20 usdc` (USDC token)
    - `IMilkman milkman`
- **Immutable & storage**
    - `address public immutable ASSET = address(autoUSD);`
    - `IERC20 public immutable USDC = usdc;`
    - `IAutopoolMainRewarder public immutable REWARDER = rewarder;`
    - `IMilkman public immutable MILKMAN = milkman;`
    - `mapping(address => address) public priceCheckerByToken; // rewardToken -> priceChecker`
    - `EnumerableSet.AddressSet private configuredRewardTokens; // keys for iteration`
    - Optional: track `pendingOrders[rewardToken]` (ids / balances claimable) for analytics (not required by Milkman itself).
- **Roles & modifiers**
    - Leverage Yearn’s `onlyManagement`, `onlyKeepers`, `onlyEmergencyAuthorized`, `nonReentrant`. ([docs.yearn.fi](https://docs.yearn.fi/developers/smart-contracts/V3/TokenizedStrategy))
- **External mgmt**
    - `function updatePriceChecker(address fromToken, address priceChecker) external onlyManagement`
        - **require(fromToken != ASSET)** (prevent base asset swaps)
        - If `priceChecker == address(0)`, **remove** and delete from set. Else **add/update**.
    - Optional: `setMinRewardToSell(token, amount)`, `setDustThresholdUSDC(amount)`.
- **Keeper ops**
    - `function claimRewardsAndSwap() external onlyKeepers`
        - `REWARDER.getReward(address(this), address(this), /*claimExtras=*/true)` to pull all rewards.
        - For each `token in configuredRewardTokens`:
            - `uint256 bal = IERC20(token).balanceOf(address(this)); if (bal == 0) continue;`
            - Approve `MILKMAN` (safe approve reset) and call `requestSwapExactTokensForTokens(bal, token, USDC, address(this), priceCheckerByToken[token], checkerDataFor(token))` (see §4).
        - **No assumptions** about same‑block settlement; returns after requests are placed. ([Ethereum (ETH) Blockchain Explorer](https://etherscan.io/address/0x726104CfBd7ece2d1f5b3654a19109A9e2b6c27B), [docs.cow.fi](https://docs.cow.fi/cow-protocol/concepts/order-types/milkman-orders))
- **Yearn hooks (must implement)**
    - `_deployFunds(uint256 amount)` → **stake autoUSD** sitting idle:
        - `asset.safeApprove(address(REWARDER), 0); asset.safeApprove(address(REWARDER), amount);`
        - `REWARDER.stake(address(this), amount);` (Rewarder will `transferFrom` staking token, which is the **autopool vault token**, i.e., **autoUSD**). ([Ethereum (ETH) Blockchain Explorer](https://etherscan.io/address/0x726104CfBd7ece2d1f5b3654a19109A9e2b6c27B))
    - `_freeFunds(uint256 amount)` → **unstake** autoUSD:
        - `REWARDER.withdraw(address(this), amount, /*claim=*/false);`
    - `_harvestAndReport() returns (uint256 totalAssets)`
        - 
            1. If not shutdown: `claimRewardsAndSwap()`.
        - 
            1. **Settle & compound USDC** already held (from prior Milkman settlements):
            - `USDC.safeApprove(address(asset), 0); USDC.safeApprove(address(asset), usdcBal);`
            - `uint256 minted = IERC4626(address(asset)).deposit(usdcBal, address(this));`
            - Immediately **stake minted autoUSD**: handled by `_deployFunds(asset.balanceOf(address(this)))`.
        - 
            1. Compute `totalAssets = asset.balanceOf(address(this)) + REWARDER.balanceOf(address(this))` (if Rewarder balance is enumerable or we track staked amount internally).
        - **Return** `totalAssets`. (Unsettled Milkman orders and unsold reward tokens are **NOT** included to keep reporting **conservative & manipulation‑resistant**.) ([docs.yearn.fi](https://docs.yearn.fi/developers/v3/strategy_writing_guide))

> Why stake(address(this), amount) works: Rewarder’s stake pulls stakingToken via transferFrom(msg.sender, address(this)) after internal accounting; since our strategy is msg.sender and holds autoUSD, this is the intended flow. (Ethereum (ETH) Blockchain Explorer)
> 

---

## 4) Price checker design (Chainlink‑based)

**Goal:** Ensure the CoW solver’s `minOut` for `rewardToken → USDC` is **close to oracle value** at execution time.

**Mechanism:** Milkman calls our configured `priceChecker.checkPrice(amountIn, fromToken, USDC, minOut, data) → bool`; must return true to sign the off‑chain order. Price checkers are **plug‑and‑play** via the `IPriceChecker` interface; no global whitelist needed. ([GitHub](https://github.com/charlesndalton/milkman))

**Recommended implementation:** `ChainlinkPairPriceChecker` using **Chainlink Feed Registry** on Ethereum mainnet to fetch USD‑denominated prices:

- Resolve **fromToken/USD** via Feed Registry.
- Resolve **USDC/USD** (or treat USDC as $1 with a sanity check vs feed if available).
- Compute `refOut = amountIn * (price[fromToken,USD]/price[USDC,USD])` with proper decimals.
- Enforce `minOut >= refOut * (1 - maxDeviationBps/10_000)` and **staleness/heartbeat** checks.
- `data` can carry `maxDeviationBps`, min heartbeat, and optionally feed overrides. ([Chainlink Documentation](https://docs.chain.link/data-feeds/feed-registry), [Ethereum (ETH) Blockchain Explorer](https://etherscan.io/address/0x47fb2585d2c56fe188d0e6ec628a38b74fceeedf))

> TOKE/USD availability: If Chainlink lacks a native TOKE/USD on mainnet, use a composite checker:
> 
> - Derive **TOKE/ETH** via a **TWAP** (e.g., UniV3 30–60 min) and multiply by **Chainlink ETH/USD** and divide by **USDC/USD** to get TOKE/USDC; still apply heartbeat/staleness checks on Chainlink legs and TWAP window/min liquidity on the DEX leg. The checker is still set via `updatePriceChecker(TOKE, address(compositeChecker))`. ([Chainlink Documentation](https://docs.chain.link/data-feeds/price-feeds), [data.chain.link](https://data.chain.link/feeds/ethereum/mainnet/eth-usd))

**Safety rails:**

- `updatePriceChecker(fromToken, ...)` **reverts** if `fromToken == asset` (**autoUSD**), preventing misconfiguration that could sell base asset.
- If no checker is configured for a reward token, swaps are **skipped** (rewards accrue until configured).

---

## 5) ERC‑4626 interactions (compounding path)

- **USDC → autoUSD mint:** autoUSD Autopools are ERC‑4626(+Permit); deposit the **base asset (USDC)** to mint `autoUSD` shares. We call `IERC4626(autoUSD).deposit(usdcBalance, address(this))`. Then immediately stake the **new autoUSD**. ([Tokemak Autopilot](https://docs.tokemak.xyz/developer-docs/contracts-overview/autopool-eth-contracts-overview/autopilot-contracts-and-systems/autopools))
- (Optional) If using the **Autopilot Router** for batched flows, the canonical sequence is: `deposit(autoPool, router, amount, min) → stakeVaultToken(autoPool, max)`. We generally **don’t need** the router if we already hold USDC (no swaps), because raw ERC‑4626 deposit is simplest. ([Tokemak Autopilot](https://docs.tokemak.xyz/developer-docs/contracts-overview/autopool-eth-contracts-overview/autopilot-contracts-and-systems/autopilot-router))

---

## 6) Access control & permissions

Rely exclusively on Yearn TokenizedStrategy:

- **Management**: set fees, keeper, emergency admin; call setters like `updatePriceChecker`.
- **Keeper**: call `report()` (harvest) and `tend()` (optional maintenance); `claimRewardsAndSwap()` is **restricted to `onlyKeepers`** (keeper or management).
- **Emergency Admin**: use `shutdownStrategy()` in emergencies; withdraws remain possible; harvest logic can be bypassed if shutdown. ([docs.yearn.fi](https://docs.yearn.fi/developers/v3/strategy_writing_guide))

No custom pausable/timelock. (Matches your request.)

---

## 7) Function list (primary)

- **Mgmt**
    - `updatePriceChecker(address fromToken, address checker)` **onlyManagement** (revert if `fromToken == asset`).
    - (optional) `setMinRewardToSell(address token, uint256 amount)` **onlyManagement**.
- **Keeper**
    - `claimRewardsAndSwap()` **onlyKeepers**: reward claim + Milkman request(s).
- **Yearn hooks**
    - `_deployFunds(uint256 amount)` → stake autoUSD in Rewarder.
    - `_freeFunds(uint256 amount)` → withdraw autoUSD from Rewarder (no claim).
    - `_harvestAndReport()` → claim, request swaps, compound any settled USDC, re‑stake, return `totalAssets`.
- **View/trigger helpers**
    - `harvestTrigger(uint256 callCost)` (optional): return true if
        - `claimableRewards ≥ threshold`, or
        - `USDC.balanceOf(this) ≥ threshold`, or
        - `timeSinceLastReport ≥ profitMaxUnlockTime/2`, etc. (Tune to gas economics.) ([docs.yearn.fi](https://docs.yearn.fi/developers/v3/strategy_writing_guide))

---

## 8) Accounting choices & edge cases

- **Total assets** in `_harvestAndReport` counts **loose + staked autoUSD**.
    - **Do not** include unsettled Milkman orders or unsold reward token balances in the returned total; this avoids oracle/minOut games and is consistent with Yearn guidance to make `_harvestAndReport` a **trusted** accounting. ([docs.yearn.fi](https://docs.yearn.fi/developers/v3/strategy_writing_guide))
- **Withdraw path** uses `_freeFunds` to unstake exact shares as needed; any shortfall is recognized per Yearn semantics.
- **Fees** & profit unlocking handled by TokenizedStrategy. ([docs.yearn.fi](https://docs.yearn.fi/developers/smart-contracts/V3/TokenizedStrategy))

---

## 9) Security & safety

**Integration checks**

- **Approvals:** use **safe approve reset** (0 → N) for Rewarder, Milkman, autoUSD.
- **Reentrancy:** Yearn wraps state‑changing functions with a reentrancy guard; our external functions also inherit protection. ([docs.yearn.fi](https://docs.yearn.fi/developers/smart-contracts/V3/TokenizedStrategy))
- **Oracle safety:** Chainlink checker must enforce **freshness/heartbeat**, **decimals**, **non‑zero answers**, and a **max deviation** parameter; for composite checkers, TWAP must enforce min liquidity, min window, and maximum age. ([Chainlink Documentation](https://docs.chain.link/data-feeds/feed-registry))
- **AutoUSD only deposits:** strategy rejects non‑autoUSD deposits by design (ERC‑4626 asset is autoUSD), preventing a user from depositing USDC directly at the strategy ERC‑4626 interface.
- **DoS mitigation:** Skipping swaps when no price checker is configured ensures we never block harvest.
- **Emergency:** `shutdownStrategy()` to stop deposits, keep redemptions, and let management unwind. ([docs.yearn.fi](https://docs.yearn.fi/developers/v3/strategy_writing_guide))

**Tokemak specifics**

- We stake the **autopool vault token** (autoUSD) in Rewarder via `stake(account, amount)`, and can `withdraw(account, amount, claim)` to free shares. Rewarder exposes `rewardToken()`, `extraRewards*`, and `getReward(account, recipient, claimExtras)`. ([Ethereum (ETH) Blockchain Explorer](https://etherscan.io/address/0x726104CfBd7ece2d1f5b3654a19109A9e2b6c27B))

**Milkman specifics**

- Order creation uses `requestSwapExactTokensForTokens(...)`; execution is **asynchronous** and guarded by our price checker. (Solver must present a `minOut` consistent with the oracle; otherwise the checker rejects.) ([docs.cow.fi](https://docs.cow.fi/cow-protocol/concepts/order-types/milkman-orders))

---

## 10) Parameterization (initial suggestions)

- `thresholds`
    - `minRewardToSell[TOKE] = 1e18` (example; tune post‑launch)
    - `minUSDCToCompound = 1,000e6` (USDC 6d)
- `priceCheckerData`
    - For Chainlink checker: `maxDeviationBps = 500` (5%), `maxStaleTime = 1 hour`.
    - For composite TOKE checker: TWAP window `≥30m`, min liquidity threshold, plus Chainlink ETH/USD & USDC/USD staleness checks. ([data.chain.link](https://data.chain.link/feeds/ethereum/mainnet/eth-usd))

All values are configurable by **management**.

---

## 11) Test plan (high level)

- **Unit/mocks**
    - Mock Rewarder (stake/withdraw/getReward/rewardToken/extra rewards) and assert staking/unstaking correctness and claim flows. (Function names and behaviors are in verified Rewarder code.) ([Ethereum (ETH) Blockchain Explorer](https://etherscan.io/address/0x726104CfBd7ece2d1f5b3654a19109A9e2b6c27B))
    - Mock Milkman & price checkers: ensure `requestSwap…` requires a valid checker and rejects mis‑priced swaps; assert **no swap** when checker missing.
    - Mock Chainlink feeds & registry interfaces; test decimals/heartbeat/staleness and deviation logic. ([Chainlink Documentation](https://docs.chain.link/data-feeds/feed-registry))
    - ERC‑4626 deposit to autoUSD with USDC; assert minted shares and immediate restake. ([Tokemak Autopilot](https://docs.tokemak.xyz/developer-docs/contracts-overview/autopool-eth-contracts-overview/autopilot-contracts-and-systems/autopools))
    - `_harvestAndReport()` accounting excludes unsettled orders and unsold rewards; includes redeemed/minted/staked autoUSD.
- **Integration (fork)**
    - Fork mainnet around recent block; wire actual `autoUSD`, Rewarder `0x7261…c27B`, USDC, a live Milkman deployment, and the Chainlink Feed Registry. Exercise a full cycle with small amounts. ([Ethereum (ETH) Blockchain Explorer](https://etherscan.io/address/0x726104CfBd7ece2d1f5b3654a19109A9e2b6c27B), [Tokemak Autopilot](https://docs.tokemak.xyz/developer-docs/contracts-overview/contract-addresses))
- **Invariants**
    - Shares‑to‑assets monotonic with only realized assets.
    - No loss of staking token across claim/compound cycles.
    - `updatePriceChecker(asset, …)` reverts (cannot configure for autoUSD).

---

## 12) Deployment & runbook

1. **Configure addresses:**
    - `asset = autoUSD (0xa756…0d35)`
    - `rewarder = AutopoolMainRewarder (0x7261…c27B)`
    - `USDC = 0xA0b8…6eB48`
    - `milkman = (deployment used by your ops)`; confirm it’s the **requester** contract with `requestSwapExactTokensForTokens`. ([Ethereum (ETH) Blockchain Explorer](https://etherscan.io/address/0xa7569a44f348d3d70d8ad5889e50f78e33d80d35), [docs.cow.fi](https://docs.cow.fi/cow-protocol/concepts/order-types/milkman-orders))
2. **Set Yearn roles/params:** `management`, `keeper`, (optional) `emergencyAdmin`, `performanceFee`, `profitMaxUnlockTime`. ([docs.yearn.fi](https://docs.yearn.fi/developers/v3/strategy_writing_guide))
3. **Set price checkers:**
    - For **TOKE**: set `updatePriceChecker(TOKE, address(chainlinkOrCompositeChecker))`.
    - For any **extra reward tokens**, add corresponding checkers.
4. **Seed strategy:** deposit minimal **autoUSD**, verify `_deployFunds` stakes correctly (Rewarder `balanceOf` increases). ([Ethereum (ETH) Blockchain Explorer](https://etherscan.io/address/0x726104CfBd7ece2d1f5b3654a19109A9e2b6c27B))
5. **Keeper automation:** connect to Yearn‑compatible keepers (e.g., yHaas or Gelato) to call `report()` at desired cadence and optionally `tend()`. ([docs.yearn.fi](https://docs.yearn.fi/developers/v3/strategy_writing_guide))
6. **Monitoring:**
    - Track: Rewarder `earned`, `rewardToken`, balances of reward tokens/USDC/autoUSD (loose+staked), and pending Milkman orders.
    - Alert on: stale price feeds, failed Milkman checks, Rewarder queue changes, or strategy shutdown.

---

## 13) Pseudocode sketch (Solidity‑style, interfaces abbreviated)

```solidity
contract TokemakAutoUSDStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    IERC4626 public immutable autoUSD;
    IERC20   public immutable USDC;
    IAutopoolMainRewarder public immutable rewarder;
    IMilkman public immutable milkman;

    mapping(address => address) public priceCheckerByToken;
    EnumerableSet.AddressSet private rewardTokens; // configured

    constructor(
        IERC4626 _autoUSD,
        IERC20   _usdc,
        IAutopoolMainRewarder _rewarder,
        IMilkman _milkman,
        address _management
    ) BaseStrategy(address(_autoUSD), _management) {
        autoUSD = _autoUSD;
        USDC = _usdc;
        rewarder = _rewarder;
        milkman = _milkman;
    }

    // ---- mgmt ----
    function updatePriceChecker(address fromToken, address checker) external onlyManagement {
        if (fromToken == address(asset)) revert CannotSetCheckerForAsset();
        priceCheckerByToken[fromToken] = checker;
        if (checker == address(0)) rewardTokens.remove(fromToken);
        else rewardTokens.add(fromToken);
        emit PriceCheckerUpdated(fromToken, checker);
    }

    // ---- keeper ----
    function claimRewardsAndSwap() public onlyKeepers nonReentrant {
        // Claim all rewards to this strategy; include extras
        rewarder.getReward(address(this), address(this), true);

        uint256 n = rewardTokens.length();
        for (uint256 i; i < n; ++i) {
            address token = rewardTokens.at(i);
            uint256 amt = IERC20(token).balanceOf(address(this));
            if (amt == 0) continue;

            address checker = priceCheckerByToken[token];
            if (checker == address(0)) continue; // skip if not configured

            IERC20(token).safeApprove(address(milkman), 0);
            IERC20(token).safeApprove(address(milkman), amt);

            milkman.requestSwapExactTokensForTokens(
                amt,
                IERC20(token),
                USDC,
                address(this),
                checker,
                abi.encode(/* maxDeviationBps, staleness, etc. */)
            );
        }
    }

    // ---- Yearn hooks ----
    function _deployFunds(uint256 amount) internal override {
        if (amount == 0) return;
        IERC20(address(asset)).safeApprove(address(rewarder), 0);
        IERC20(address(asset)).safeApprove(address(rewarder), amount);
        rewarder.stake(address(this), amount);
    }

    function _freeFunds(uint256 amount) internal override {
        if (amount == 0) return;
        rewarder.withdraw(address(this), amount, false);
    }

    function _harvestAndReport() internal override returns (uint256) {
        if (!TokenizedStrategy.isShutdown()) {
            uint256 uBal = USDC.balanceOf(address(this));
            if (uBal > 0) {
                USDC.safeApprove(address(autoUSD), 0);
                USDC.safeApprove(address(autoUSD), uBal);
                autoUSD.deposit(uBal, address(this));
                _deployFunds(IERC20(address(asset)).balanceOf(address(this)));
            }
        }
        // compute total assets as loose + staked autoUSD
        return IERC20(address(asset)).balanceOf(address(this))
             + rewarder.balanceOf(address(this));
    }
}

```

*Notes:*

- `rewarder.balanceOf` exists per interface in verified code; if not public, track staked amount internally on stake/withdraw events. ([Ethereum (ETH) Blockchain Explorer](https://etherscan.io/address/0x726104CfBd7ece2d1f5b3654a19109A9e2b6c27B))
- The `IMilkman` interface uses the signature in CoW’s Milkman docs. ([docs.cow.fi](https://docs.cow.fi/cow-protocol/concepts/order-types/milkman-orders))

---

## 14) Risks & mitigations

- **Oracle gaps (e.g., TOKE/USD not on Chainlink):** use **composite price checker** (DEX TWAP + Chainlink majors) or **Data Streams** where appropriate; never proceed without a checker. ([Chainlink Documentation](https://docs.chain.link/data-feeds/price-feeds))
- **Async settlement:** harvest may “do work now, realize later”. We therefore **only** report compounded assets once USDC settles and is deposited; pending orders are ignored in accounting to prevent manipulation. ([docs.yearn.fi](https://docs.yearn.fi/developers/v3/strategy_writing_guide))
- **External dependencies:** Rewarder parameters (reward rate, queues) can change; strategy should tolerate “no rewards” harvests and continue staking flows. Verified Rewarder contract exposes `rewardToken()` etc. for introspection. ([Ethereum (ETH) Blockchain Explorer](https://etherscan.io/address/0x726104CfBd7ece2d1f5b3654a19109A9e2b6c27B))

---

## 15) What the codebases say (key facts we relied on)

- **Yearn TokenizedStrategy**: strategies override `_deployFunds`, `_freeFunds`, `_harvestAndReport`; roles `onlyManagement/onlyKeepers/onlyEmergencyAuthorized`; reporting via `report()`/`tend()`. ([docs.yearn.fi](https://docs.yearn.fi/developers/v3/strategy_writing_guide))
- **Tokemak Autopools**: ERC‑4626 vaults with **base asset deposits** (autoUSD base is **USDC**). Users **stake** LAT receipt tokens in **AutopoolMainRewarder** for additional incentives (e.g., TOKE). ([Tokemak Autopilot](https://docs.tokemak.xyz/developer-docs/contracts-overview/autopool-eth-contracts-overview/autopilot-contracts-and-systems/autopools))
- **AutopoolMainRewarder**: `stake(account, amount)`, `withdraw(account, amount, claim)`, `getReward(account, recipient, claimExtras)`, `rewardToken()`. Verified at `0x7261…c27B`. ([Ethereum (ETH) Blockchain Explorer](https://etherscan.io/address/0x726104CfBd7ece2d1f5b3654a19109A9e2b6c27B))
- **Milkman**: `requestSwapExactTokensForTokens(...)` and **price checker** interface for on‑chain validation of `minOut`. ([docs.cow.fi](https://docs.cow.fi/cow-protocol/concepts/order-types/milkman-orders), [GitHub](https://github.com/charlesndalton/milkman))
- **Chainlink Feed Registry**: canonical on‑chain registry to fetch aggregator addresses for `(base, quote)` pairs on **Ethereum mainnet**. ([Chainlink Documentation](https://docs.chain.link/data-feeds/feed-registry), [Ethereum (ETH) Blockchain Explorer](https://etherscan.io/address/0x47fb2585d2c56fe188d0e6ec628a38b74fceeedf))

---

### Appendix: Useful addresses (Ethereum mainnet)

- autoUSD Autopool (ERC‑4626): `0xa7569A44f348d3D70d8ad5889e50F78E33d80D35` (proxy; see Etherscan). ([Ethereum (ETH) Blockchain Explorer](https://etherscan.io/address/0xa7569a44f348d3d70d8ad5889e50f78e33d80d35))
- AutopoolMainRewarder (autoUSD): `0x726104CfBd7ece2d1f5b3654a19109A9e2b6c27B` (verified, functions above). ([Ethereum (ETH) Blockchain Explorer](https://etherscan.io/address/0x726104CfBd7ece2d1f5b3654a19109A9e2b6c27B))
- USDC: `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`. ([Ethereum (ETH) Blockchain Explorer](https://etherscan.io/address/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48))
- Chainlink Feed Registry: `0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf`. ([Ethereum (ETH) Blockchain Explorer](https://etherscan.io/address/0x47fb2585d2c56fe188d0e6ec628a38b74fceeedf))

---

## Final notes

- The spec above cleanly separates **configuration risk** (price checker per reward token) from **core flows** (stake/claim/swap/compound).
- It honors your constraints: **autoUSD‑only deposits**, **no extra AC**, **open‑ended & protected Milkman path**, and **keeper‑triggered** harvests.
- If you’d like, I can follow up with **interface stubs** for `IMilkman` and a sample `ChainlinkPairPriceChecker` (Feed Registry) plus a **composite TOKE checker** (UniV3 TWAP × Chainlink majors).