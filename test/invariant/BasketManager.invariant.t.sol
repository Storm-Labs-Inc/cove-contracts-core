// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";

import { VmSafe } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";

import { Test } from "forge-std/Test.sol";
import { Constants } from "test/utils/Constants.t.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";

import { BasketManagerUtils } from "src/libraries/BasketManagerUtils.sol";
import { ManagedWeightStrategy } from "src/strategies/ManagedWeightStrategy.sol";
import { RebalanceStatus } from "src/types/BasketManagerStorage.sol";
import { Status } from "src/types/BasketManagerStorage.sol";
import { ExternalTrade, InternalTrade } from "src/types/Trades.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";
import { BasketManagerValidationLib } from "test/utils/BasketManagerValidationLib.sol";

abstract contract BasketManager_InvariantTest is StdInvariant, BaseTest {
    using SafeERC20 for IERC20;
    using BasketManagerValidationLib for BasketManager;

    BasketManagerHandler public handler;

    // Constants for test configuration
    uint256 internal constant ACTOR_COUNT = 5;
    uint256 internal constant INITIAL_BALANCE = 1_000_000;
    uint256 internal constant DEPOSIT_AMOUNT = 10_000;

    ///////////////////////
    // SETUP
    ///////////////////////

    function setUp() public virtual override {
        forkNetworkAt("mainnet", _getForkBlockNumber());
        super.setUp();

        // Deploy handler with multiple baskets
        BasketManager basketManager = _setupBasketManager();
        address[] memory baskets = _setupBaskets(basketManager);
        address[] memory assets = _setupAssets(basketManager);

        // Create and configure handler
        handler = new BasketManagerHandler(basketManager, baskets, assets, ACTOR_COUNT);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = Constants.labelKnownAddresses.selector;
        excludeSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));

        targetContract(address(handler));

        // Fund test accounts
        _fundActors();
    }

    function _getForkBlockNumber() internal virtual returns (uint256) {
        return BLOCK_NUMBER_MAINNET_FORK;
    }

    function _setupBasketManager() internal virtual returns (BasketManager);

    function _setupBaskets(BasketManager basketManager) internal virtual returns (address[] memory) {
        // Return array of basket addresses
        return basketManager.basketTokens();
    }

    function _setupAssets(BasketManager basketManager) internal virtual returns (address[] memory) {
        // Return array of asset addresses
        return AssetRegistry(address(basketManager.assetRegistry())).getAllAssets();
    }

    ///////////////////////
    // INVARIANTS
    ///////////////////////

    // Verify ghost variable isPaused matches actual BasketManager paused state
    function invariant_pauseStateConsistency() public {
        // Check if ghost variable isPaused matches actual paused state
        assertEq(
            handler.basketManager().paused(),
            handler.isPaused(),
            "Ghost variable isPaused out of sync with actual paused state"
        );
    }

    // Verify asset conservation: sum of basket balances equals actual token balance when not in rebalance
    function invariant_assetConservation() public {
        // Skip if currently in the middle of a rebalance process
        if (handler.basketManager().rebalanceStatus().status != Status.NOT_STARTED) {
            return;
        }

        // Check each asset
        address[] memory assets = handler.getAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 totalBasketBalances = 0;

            // Sum up the balances across all baskets
            address[] memory baskets = handler.getBaskets();
            for (uint256 j = 0; j < baskets.length; j++) {
                totalBasketBalances += handler.basketManager().basketBalanceOf(baskets[j], asset);
            }

            // Since collectedSwapFees is not directly accessible (it's private), we can't check it directly
            // in this invariant test. We rely on the internal accounting to be correct.

            // Verify conservation: sum of basket balances = actual balance when not in rebalance
            assertEq(
                totalBasketBalances,
                IERC20(asset).balanceOf(address(handler.basketManager())),
                "Asset conservation violated for asset"
            );
        }
    }

    // Verify basket total assets match total deposits for each basket. Assumes no trades have been made.
    // TODO: is this ghost variable tracking invariant helpful? How do we track this across each trade and rebalances?
    // Unsure what to compare totalAssets() to across each trade and rebalance.
    function invariant_basketBalancesMatchDeposits() public {
        // For each basket, verify total assets match deposits
        address[] memory baskets = handler.getBaskets();
        for (uint256 i = 0; i < baskets.length; i++) {
            assertEq(
                handler.totalDepositsForBasket(baskets[i]),
                BasketToken(baskets[i]).totalAssets(),
                "Basket assets should match deposits"
            );
        }
    }

    // Verify oracle configurations remain valid and return non-zero values
    function invariant_oraclePathsAreValid() public {
        // Verify oracle configurations remain valid
        handler.basketManager().testLib_validateConfiguredOracles();
    }

    // Verify basket registration consistency: count, indices, and mapping integrity
    function invariant_basketRegistrationConsistency() public {
        BasketManager basketManager = handler.basketManager();

        // Check that numOfBasketTokens matches basketTokens.length
        assertEq(basketManager.numOfBasketTokens(), basketManager.basketTokens().length, "Basket token count mismatch");

        // Check that each basket's index is correct
        address[] memory baskets = basketManager.basketTokens();
        for (uint256 i = 0; i < baskets.length; i++) {
            assertEq(basketManager.basketTokenToIndex(baskets[i]), i, "Basket token index mismatch");
        }
    }

    // Verify basket registration consistency for known baskets and their basketIds
    function invariant_knownBasketRegistrationConsistency() public {
        BasketManager basketManager = handler.basketManager();
        address[] memory baskets = basketManager.basketTokens();

        // Check each basket
        for (uint256 i = 0; i < baskets.length; i++) {
            address basket = baskets[i];

            // Get basket's bitFlag and strategy
            uint256 bitFlag = BasketToken(basket).bitFlag();
            address strategy = BasketToken(basket).strategy();

            // Calculate expected basketId
            bytes32 basketId = keccak256(abi.encodePacked(bitFlag, strategy));

            // Verify basketIdToAddress mapping is correct
            assertEq(basketManager.basketIdToAddress(basketId), basket, "BasketId to address mapping mismatch");

            // Verify basket has valid index by checking if basketTokenToIndex() doesn't revert
            // If the basket is not properly registered, this will revert with BasketTokenNotFound
            uint256 index = basketManager.basketTokenToIndex(basket);
            assertTrue(index < type(uint256).max, "Basket has invalid index"); // Always true if above doesn't revert
        }

        // Additional check: Verify all known basketIds point to baskets with valid indices
        // This is a more comprehensive check that ensures no "orphaned" basketIds exist
        for (uint256 i = 0; i < baskets.length; i++) {
            address basket = baskets[i];
            uint256 bitFlag = BasketToken(basket).bitFlag();
            address strategy = BasketToken(basket).strategy();
            bytes32 basketId = keccak256(abi.encodePacked(bitFlag, strategy));

            address registeredBasket = basketManager.basketIdToAddress(basketId);
            if (registeredBasket != address(0)) {
                // This will revert with BasketTokenNotFound if the basket is not properly registered
                uint256 index = basketManager.basketTokenToIndex(registeredBasket);
                assertTrue(index < type(uint256).max, "Known basket has invalid index"); // Always true if above doesn't
                    // revert
            }
        }
    }

    // Verify BasketManager configurations are within intended hardcoded bounds
    function invariant_configurationBounds() public {
        BasketManager basketManager = handler.basketManager();

        // Check swap fee is within bounds
        assertTrue(basketManager.swapFee() <= MAX_SWAP_FEE, "Swap fee exceeds maximum");

        // Check step delay is within bounds
        uint40 stepDelay = basketManager.stepDelay();
        assertTrue(stepDelay >= MIN_STEP_DELAY, "Step delay below minimum");
        assertTrue(stepDelay <= MAX_STEP_DELAY, "Step delay above maximum");

        // Check retry limit is within bounds
        assertTrue(basketManager.retryLimit() <= MAX_RETRIES, "Retry limit exceeds maximum");

        // Check slippage limit is within bounds
        assertTrue(basketManager.slippageLimit() <= MAX_SLIPPAGE_LIMIT, "Slippage limit exceeds maximum");

        // Check weight deviation limit is within bounds
        assertTrue(
            basketManager.weightDeviationLimit() <= MAX_WEIGHT_DEVIATION_LIMIT, "Weight deviation limit exceeds maximum"
        );

        // Check management fee for each basket is within bounds
        address[] memory baskets = basketManager.basketTokens();
        for (uint256 i = 0; i < baskets.length; i++) {
            assertTrue(basketManager.managementFee(baskets[i]) <= MAX_MANAGEMENT_FEE, "Management fee exceeds maximum");
        }
    }

    // Verify variable links are correct
    function invariant_variableLink() public {
        BasketManager basketManager = handler.basketManager();
        address[] memory baskets = basketManager.basketTokens();

        for (uint256 i = 0; i < baskets.length; i++) {
            address basket = baskets[i];
            // Check Asset Registry link
            assertEq(
                BasketToken(basket).assetRegistry(),
                address(basketManager.assetRegistry()),
                "Basket asset registry mismatch"
            );
            // Check Basket Manager link
            assertEq(BasketToken(basket).basketManager(), address(basketManager), "Basket manager address mismatch");
        }
    }

    // Verify rebalance status validity: retry count, basket mask, trade hashes, and timestamps
    function invariant_rebalanceStatusValidity() public {
        BasketManager basketManager = handler.basketManager();
        RebalanceStatus memory status = basketManager.rebalanceStatus();

        assertEq(
            keccak256(abi.encode(status)),
            keccak256(abi.encode(handler.rebalanceStatus())),
            "Rebalance status should be consistent"
        );

        // Check retry count does not exceed limit
        assertTrue(status.retryCount <= basketManager.retryLimit(), "Retry count exceeds limit");

        // Status-specific validations
        if (status.status == Status.NOT_STARTED) {
            // When not started, all state should be reset
            assertEq(status.proposalTimestamp, 0, "Proposal timestamp should be zero outside of rebalance");
            assertEq(status.retryCount, 0, "Retry count should be zero outside of rebalance");
            assertEq(status.basketMask, 0, "Basket mask should be zero outside of rebalance");
            assertEq(status.basketHash, bytes32(0), "Basket hash should be zero outside of rebalance");
            assertEq(
                basketManager.externalTradesHash(), bytes32(0), "External trades hash should be zero when not started"
            );
            if (status.epoch == 0 && status.retryCount == 0) {
                assertEq(status.timestamp, 0, "Timestamp should be zero when not started");
            }
            if (status.timestamp > 0) {
                assertTrue(
                    status.epoch > 0 || status.retryCount > 0,
                    "Epoch or retry count should be non-zero when timestamp is non-zero"
                );
            }
        } else {
            // Active rebalance validations
            assertTrue(status.basketMask != 0, "Basket mask is not zero during active rebalance");
            assertTrue(status.basketHash != bytes32(0), "Basket hash is not zero during active rebalance");
            assertTrue(status.proposalTimestamp != 0, "Proposal timestamp should be non-zero during rebalance");
            assertTrue(
                status.timestamp >= status.proposalTimestamp, "Timestamp should not be before proposal timestamp"
            );

            // Status-specific external trades hash checks
            if (status.status == Status.TOKEN_SWAP_PROPOSED || status.status == Status.TOKEN_SWAP_EXECUTED) {
                // Technically, the external trades could be empty if only internal trades are proposed
                // However the resulting hash should still be non-zero as hash of zero bytes is non-zero
                assertTrue(
                    basketManager.externalTradesHash() != bytes32(0),
                    "External trades hash should be non-zero after trade proposal"
                );
            }
        }
    }

    // Verify asset index consistency and base asset index validity for each basket
    function invariant_assetIndexConsistency() public {
        BasketManager basketManager = handler.basketManager();
        address[] memory baskets = basketManager.basketTokens();

        for (uint256 i = 0; i < baskets.length; i++) {
            address basket = baskets[i];
            address[] memory assets = basketManager.basketAssets(basket);

            for (uint256 j = 0; j < assets.length; j++) {
                address asset = assets[j];

                // Check that getAssetIndexInBasket returns the correct index
                assertEq(basketManager.getAssetIndexInBasket(basket, asset), j, "Asset index mismatch");
            }

            // Check base asset index is valid and matches
            uint256 baseAssetIndex = basketManager.basketTokenToBaseAssetIndex(basket);
            assertLt(baseAssetIndex, assets.length, "Base asset index out of bounds");

            // Verify base asset in BasketToken matches the asset at baseAssetIndex
            assertEq(BasketToken(basket).asset(), assets[baseAssetIndex], "Base asset mismatch");
        }
    }

    function invariant_completeRebalance_revertsWhen_StepDelayIsNotMet() public {
        // Get the last action timestamp
        BasketManager basketManager = handler.basketManager();
        uint256 lastActionTimestamp = basketManager.rebalanceStatus().timestamp;
        if (lastActionTimestamp > 0) {
            // Only if the step delay has not passed
            if (lastActionTimestamp + basketManager.stepDelay() > vm.getBlockTimestamp()) {
                try basketManager.completeRebalance(
                    handler.externalTrades(),
                    handler.rebalancingBaskets(),
                    handler.rebalancingTargetWeights(),
                    handler.rebalancingBasketAssets()
                ) {
                    assertTrue(false, "Expected reversion");
                } catch {
                    // Expected reversion
                }
            }
        }
    }

    ///////////////////////
    // HELPERS
    ///////////////////////

    function _fundActors() internal {
        address[] memory actors = handler.getActors();
        address[] memory assets = handler.getAssets();

        for (uint256 i = 0; i < actors.length; i++) {
            for (uint256 j = 0; j < assets.length; j++) {
                deal(assets[j], actors[i], INITIAL_BALANCE * (10 ** handler.decimals(assets[j])));
            }
        }
    }
}

contract BasketManagerHandler is Test, Constants {
    using SafeERC20 for IERC20;
    using BasketManagerValidationLib for BasketManager;

    BasketManager public immutable basketManager;
    address[] public baskets;
    address[] public assets;
    address[] public actors;

    // Ghost variables
    mapping(address => mapping(address => uint256)) public depositsPendingRebalance;
    mapping(address => mapping(address => uint256)) public redeemsPendingRebalance;
    mapping(address => uint256) public totalDepositsForBasket;
    bool public isRebalancing;
    bool public isPaused;

    // Rebalance state tracking
    RebalanceStatus private _rebalanceStatus;
    InternalTrade[] private _internalTrades;
    ExternalTrade[] private _externalTrades;
    address[] private _rebalancingBaskets;
    uint64[][] private _rebalancingTargetWeights;
    address[][] private _rebalancingBasketAssets;

    constructor(BasketManager _basketManager, address[] memory _baskets, address[] memory _assets, uint256 actorCount) {
        basketManager = _basketManager;
        baskets = _baskets;
        assets = _assets;

        // Create test actors
        actors = new address[](actorCount);
        for (uint256 i = 0; i < actorCount; i++) {
            actors[i] = address(uint160(uint256(keccak256(abi.encode("actor", i)))));
        }
    }

    ///////////////////////
    // Time Fuzzing
    ///////////////////////
    function warpBy(uint64 secondsToSkip) public {
        secondsToSkip = uint64(bound(secondsToSkip, 15 minutes, 3 hours));
        vm.warp(vm.getBlockTimestamp() + secondsToSkip);
    }

    ///////////////////////
    // BasketToken Fuzzing
    ///////////////////////

    function requestDeposit(uint256 actorIdx, uint256 basketIdx, uint256 amount) public {
        address actor = actors[actorIdx % actors.length];
        address basket = baskets[basketIdx % baskets.length];

        // Bound amount to the actor's balance
        uint256 balance = IERC20(BasketToken(basket).asset()).balanceOf(actor);
        vm.assume(balance > 0);
        // Assume no pending deposit requests
        uint256 lastDepositRequestId = BasketToken(basket).lastDepositRequestId(actor);
        vm.assume(BasketToken(basket).pendingDepositRequest(lastDepositRequestId, actor) == 0);
        vm.assume(BasketToken(basket).claimableDepositRequest(lastDepositRequestId, actor) == 0);
        vm.assume(BasketToken(basket).claimableFallbackAssets(actor) == 0);

        // Bound amount to the actor's balance
        amount = bound(amount, 1, balance);

        // Perform deposit request logic
        address asset = BasketToken(basket).asset();
        vm.prank(actor);
        IERC20(asset).approve(address(basket), amount);
        vm.prank(actor);
        BasketToken(basket).requestDeposit(amount, actor, actor);

        depositsPendingRebalance[basket][actor] += amount;
    }

    function deposit(uint256 actorIdx, uint256 basketIdx, uint256 amount) public {
        address actor = actors[actorIdx % actors.length];
        address basket = baskets[basketIdx % baskets.length];

        uint256 maxDeposit = BasketToken(basket).maxDeposit(actor);
        vm.assume(maxDeposit > 0);

        amount = bound(amount, 0, maxDeposit - 1);

        vm.prank(actor);
        try BasketToken(basket).deposit(amount, actor, actor) {
            assertTrue(false, "Expected reversion");
        } catch {
            // Expected reversion
        }

        vm.prank(actor);
        BasketToken(basket).deposit(maxDeposit, actor, actor);
    }

    function claimFallbackAssets(uint256 actorIdx, uint256 basketIdx) public {
        address actor = actors[actorIdx % actors.length];
        address basket = baskets[basketIdx % baskets.length];

        uint256 claimableFallbackAssets = BasketToken(basket).claimableFallbackAssets(actor);
        vm.assume(claimableFallbackAssets > 0);

        vm.prank(actor);
        BasketToken(basket).claimFallbackAssets(actor, actor);
    }

    function requestRedeem(uint256 actorIdx, uint256 basketIdx, uint256 amount) public {
        address actor = actors[actorIdx % actors.length];
        address basket = baskets[basketIdx % baskets.length];

        uint256 balance = BasketToken(basket).balanceOf(actor);
        vm.assume(balance > 0);

        // Assume no pending redeem requests
        uint256 lastRedeemRequestId = BasketToken(basket).lastRedeemRequestId(actor);
        vm.assume(BasketToken(basket).pendingRedeemRequest(lastRedeemRequestId, actor) == 0);
        vm.assume(BasketToken(basket).claimableRedeemRequest(lastRedeemRequestId, actor) == 0);
        vm.assume(BasketToken(basket).claimableFallbackShares(actor) == 0);

        // Bound amount to the actor's balance
        amount = bound(amount, 1, balance);

        vm.prank(actor);
        BasketToken(basket).requestRedeem(amount, actor, actor);

        redeemsPendingRebalance[basket][actor] += amount;
    }

    function redeem(uint256 actorIdx, uint256 basketIdx, uint256 amount) public {
        address actor = actors[actorIdx % actors.length];
        address basket = baskets[basketIdx % baskets.length];

        uint256 maxRedeem = BasketToken(basket).maxRedeem(actor);
        vm.assume(maxRedeem > 0);

        amount = bound(amount, 0, maxRedeem - 1);

        vm.prank(actor);
        try BasketToken(basket).redeem(amount, actor, actor) {
            assertTrue(false, "Expected reversion");
        } catch {
            // Expected reversion
        }

        vm.prank(actor);
        BasketToken(basket).redeem(maxRedeem, actor, actor);
    }

    function claimFallbackShares(uint256 actorIdx, uint256 basketIdx) public {
        address actor = actors[actorIdx % actors.length];
        address basket = baskets[basketIdx % baskets.length];

        uint256 claimableFallbackShares = BasketToken(basket).claimableFallbackShares(actor);
        vm.assume(claimableFallbackShares > 0);

        vm.prank(actor);
        BasketToken(basket).claimFallbackShares(actor, actor);
    }

    ///////////////////////
    // BasketManager Fuzzing
    ///////////////////////

    function proposeRebalance() public {
        vm.assume(!isRebalancing);
        vm.assume(!isPaused);

        // If a rebalance has ever been proposed, the step delay must have passed
        if (
            basketManager.rebalanceStatus().epoch != 0
                || (basketManager.rebalanceStatus().epoch == 0 && basketManager.rebalanceStatus().retryCount > 0)
        ) {
            vm.assume(basketManager.rebalanceStatus().timestamp + 1 hours <= vm.getBlockTimestamp());
        }
        basketManager.testLib_updateOracleTimestamps();
        vm.assume(basketManager.testLib_needsRebalance(baskets));

        address proposer = basketManager.getRoleMember(REBALANCE_PROPOSER_ROLE, 0);
        vm.prank(proposer);
        basketManager.proposeRebalance(baskets);

        // Update tracking variables
        isRebalancing = true;
        _rebalancingBaskets = baskets;
        _rebalancingTargetWeights = basketManager.testLib_getTargetWeights(baskets);
        _rebalancingBasketAssets = basketManager.testLib_getBasketAssets(baskets);
        _rebalanceStatus = basketManager.rebalanceStatus();
        for (uint256 i = 0; i < baskets.length; i++) {
            for (uint256 j = 0; j < actors.length; j++) {
                uint256 depositAmount = depositsPendingRebalance[baskets[i]][actors[j]];
                depositsPendingRebalance[baskets[i]][actors[j]] = 0;
                totalDepositsForBasket[baskets[i]] += depositAmount;
            }
        }
    }

    function proposeTokenSwap() public {
        vm.assume(basketManager.rebalanceStatus().status == Status.REBALANCE_PROPOSED);
        vm.assume(!isPaused);

        basketManager.testLib_updateOracleTimestamps();
        (InternalTrade[] memory newInternalTrades, ExternalTrade[] memory newExternalTrades) =
            basketManager.testLib_generateInternalAndExternalTrades(_rebalancingBaskets, _rebalancingTargetWeights);
        vm.assume(newInternalTrades.length > 0 || newExternalTrades.length > 0);

        // Propose and execute token swaps
        address proposer = basketManager.getRoleMember(TOKENSWAP_PROPOSER_ROLE, 0);
        vm.prank(proposer);
        basketManager.proposeTokenSwap(
            newInternalTrades,
            newExternalTrades,
            _rebalancingBaskets,
            _rebalancingTargetWeights,
            _rebalancingBasketAssets
        );

        // Update tracking variables
        _internalTrades = newInternalTrades;
        _externalTrades = newExternalTrades;
        _rebalanceStatus = basketManager.rebalanceStatus();

        // Execute trades
        address executor = basketManager.getRoleMember(TOKENSWAP_EXECUTOR_ROLE, 0);
        vm.prank(executor);
        vm.recordLogs();
        basketManager.executeTokenSwap(newExternalTrades, "");
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        address[] memory swapContracts = new address[](newExternalTrades.length);
        uint256 swapContractCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("OrderCreated(address,address,uint256,uint256,uint32,address)")) {
                (,,, address swapContract) = abi.decode(logs[i].data, (uint256, uint256, uint32, address));
                swapContracts[swapContractCount++] = swapContract;
            }
        }

        // Simulate trade settlement
        _simulateTradeSettlement(newExternalTrades, swapContracts);
        _rebalanceStatus = basketManager.rebalanceStatus();
    }

    function completeRebalance() public {
        vm.assume(isRebalancing);
        vm.assume(!isPaused);
        // Wait required delay
        vm.assume(basketManager.rebalanceStatus().timestamp > 0);
        vm.assume(basketManager.rebalanceStatus().timestamp + basketManager.stepDelay() <= vm.getBlockTimestamp());

        // Update oracle timestamps
        basketManager.testLib_updateOracleTimestamps();

        vm.recordLogs();
        basketManager.completeRebalance(
            _externalTrades, _rebalancingBaskets, _rebalancingTargetWeights, _rebalancingBasketAssets
        );
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            for (uint256 j = 0; j < logs[i].topics.length; j++) {
                if (logs[i].topics[j] == keccak256("RebalanceCompleted(uint40)")) {
                    isRebalancing = false;
                    _rebalancingBaskets = new address[](0);
                    _rebalancingTargetWeights = new uint64[][](0);
                    _rebalancingBasketAssets = new address[][](0);
                } else if (logs[i].topics[j] == keccak256("RedeemFulfilled(uint256,uint256,uint256)")) {
                    (, uint256 _assets) = abi.decode(logs[i].data, (uint256, uint256));
                    totalDepositsForBasket[logs[i].emitter] -= _assets;
                }
            }
        }

        // Update tracking variables
        _rebalanceStatus = basketManager.rebalanceStatus();
    }

    function pause() public {
        vm.assume(!isPaused);

        address pauser = basketManager.getRoleMember(PAUSER_ROLE, 0);
        vm.prank(pauser);
        basketManager.pause();

        isPaused = true;
    }

    function unpause() public {
        vm.assume(isPaused);

        address admin = basketManager.getRoleMember(DEFAULT_ADMIN_ROLE, 0);
        vm.prank(admin);
        basketManager.unpause();

        isPaused = false;
    }

    ///////////////////////
    // ManagedWeightStrategy Fuzzing
    ///////////////////////

    function setTargetWeights(uint256 basketIdx, uint256 seed) public {
        address basket = baskets[basketIdx % baskets.length];
        address weightStrategy = BasketToken(basket).strategy();
        uint256 bitFlag = BasketToken(basket).bitFlag();
        vm.assume(weightStrategy != address(0));

        address[] memory _assets = BasketToken(basket).getAssets();
        uint64[] memory targetWeights = new uint64[](_assets.length);
        uint256 remainingWeight = 1e18;

        for (uint256 i = 0; i < assets.length; i++) {
            if (i == assets.length - 1) {
                targetWeights[i] = uint64(remainingWeight);
            } else {
                uint256 maxWeight = remainingWeight - (assets.length - i - 1);
                uint256 weight = bound(uint256(keccak256(abi.encode(seed, i))), 1, maxWeight);
                targetWeights[i] = uint64(weight);
                remainingWeight -= weight;
            }
        }

        address manager = ManagedWeightStrategy(weightStrategy).getRoleMember(MANAGER_ROLE, 0);
        vm.prank(manager);
        ManagedWeightStrategy(weightStrategy).setTargetWeights(bitFlag, targetWeights);
    }

    ///////////////////////
    // Helper functions
    ///////////////////////

    function _simulateTradeSettlement(ExternalTrade[] memory trades, address[] memory swapContracts) internal {
        // Simulate successful settlement of external trades by CoWSwap
        for (uint256 i = 0; i < trades.length; i++) {
            // Transfer tokens to simulate trade execution
            _takeAway(IERC20(trades[i].sellToken), swapContracts[i], trades[i].sellAmount);
            _airdrop(IERC20(trades[i].buyToken), swapContracts[i], trades[i].minAmount);
        }
    }

    /// @notice Airdrop an asset to an address with a given amount
    /// @dev This function should only be used for ERC20s that have totalSupply storage slot
    /// @param _asset address of the asset to airdrop
    /// @param _to address to airdrop to
    /// @param _amount amount to airdrop
    function _airdrop(IERC20 _asset, address _to, uint256 _amount, bool adjust) internal {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount, adjust);
    }

    function _airdrop(IERC20 _asset, address _to, uint256 _amount) internal {
        _airdrop(_asset, _to, _amount, true);
    }

    /// @notice Take an asset away from an address with a given amount
    /// @param _asset address of the asset to take away
    /// @param _from address to take away from
    /// @param _amount amount to take away
    function _takeAway(IERC20 _asset, address _from, uint256 _amount) internal {
        uint256 balanceBefore = _asset.balanceOf(_from);
        if (balanceBefore < _amount) {
            revert("BaseTest:takeAway(): Insufficient balance");
        }
        deal(address(_asset), _from, balanceBefore - _amount);
    }

    ///////////////////////
    // Getters
    ///////////////////////

    function decimals(address token) public view returns (uint8) {
        return IERC20Metadata(token).decimals();
    }

    function rebalanceStatus() public view returns (RebalanceStatus memory) {
        return _rebalanceStatus;
    }

    function getActors() public view returns (address[] memory) {
        return actors;
    }

    function getAssets() public view returns (address[] memory) {
        return assets;
    }

    function getBaskets() public view returns (address[] memory) {
        return baskets;
    }

    function internalTrades() public view returns (InternalTrade[] memory) {
        return _internalTrades;
    }

    function externalTrades() public view returns (ExternalTrade[] memory) {
        return _externalTrades;
    }

    function rebalancingBaskets() public view returns (address[] memory) {
        return _rebalancingBaskets;
    }

    function rebalancingTargetWeights() public view returns (uint64[][] memory) {
        return _rebalancingTargetWeights;
    }

    function rebalancingBasketAssets() public view returns (address[][] memory) {
        return _rebalancingBasketAssets;
    }
}
