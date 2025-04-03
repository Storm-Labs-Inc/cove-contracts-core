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

    function invariant_basketManagerIsOperational() public {
        // Check if BasketManager is not paused
        assertTrue(!handler.basketManager().paused(), "BasketManager should not be paused");
    }

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

    function invariant_oraclePathsAreValid() public {
        // Verify oracle configurations remain valid
        handler.basketManager().testLib_validateConfiguredOracles();
    }

    function invariant_rebalanceStateIsConsistent() public {
        assertEq(
            keccak256(abi.encode(handler.basketManager().rebalanceStatus())),
            keccak256(abi.encode(handler.rebalanceStatus())),
            "Rebalance status should be consistent"
        );
    }

    function invariant_retryCountWithinLimit() public {
        assertLt(handler.basketManager().retryCount(), 10, "Retry count should be within limit");
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

    // State tracking
    mapping(address => mapping(address => uint256)) public depositsPendingRebalance;
    mapping(address => mapping(address => uint256)) public redeemsPendingRebalance;
    mapping(address => uint256) public totalDepositsForBasket;
    bool public isRebalancing;

    // Rebalance state tracking
    RebalanceStatus private _rebalanceStatus;
    InternalTrade[] public internalTrades;
    ExternalTrade[] public externalTrades;
    address[] public rebalancingBaskets;
    uint64[][] public rebalancingTargetWeights;
    address[][] public rebalancingBasketAssets;

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
    function warpBy(uint256 secondsToSkip) public {
        console.log("warpBy", secondsToSkip);
        vm.assume(secondsToSkip <= 3 hours);
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

    ///////////////////////
    // BasketManager Fuzzing
    ///////////////////////

    function proposeRebalance() public {
        vm.assume(!isRebalancing);

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
        rebalancingBaskets = baskets;
        rebalancingTargetWeights = basketManager.testLib_getTargetWeights(baskets);
        rebalancingBasketAssets = basketManager.testLib_getBasketAssets(baskets);
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
        basketManager.testLib_updateOracleTimestamps();
        (InternalTrade[] memory _internalTrades, ExternalTrade[] memory _externalTrades) =
            basketManager.testLib_generateInternalAndExternalTrades(baskets);
        vm.assume(_internalTrades.length > 0 || _externalTrades.length > 0);

        // Propose and execute token swaps
        address proposer = basketManager.getRoleMember(TOKENSWAP_PROPOSER_ROLE, 0);
        vm.prank(proposer);
        basketManager.proposeTokenSwap(
            _internalTrades, _externalTrades, rebalancingBaskets, rebalancingTargetWeights, rebalancingBasketAssets
        );

        // Update tracking variables
        internalTrades = _internalTrades;
        externalTrades = _externalTrades;
        _rebalanceStatus = basketManager.rebalanceStatus();

        // Execute trades
        address executor = basketManager.getRoleMember(TOKENSWAP_EXECUTOR_ROLE, 0);
        vm.prank(executor);
        basketManager.executeTokenSwap(_externalTrades, "");

        // Simulate trade settlement
        _simulateTradeSettlement(externalTrades);
    }

    function completeRebalance() public {
        vm.assume(isRebalancing);

        // Wait required delay
        vm.assume(basketManager.rebalanceStatus().timestamp > 0);
        vm.assume(basketManager.rebalanceStatus().timestamp + basketManager.stepDelay() <= vm.getBlockTimestamp());

        // Update oracle timestamps
        basketManager.testLib_updateOracleTimestamps();

        vm.recordLogs();
        basketManager.completeRebalance(externalTrades, baskets, rebalancingTargetWeights, rebalancingBasketAssets);
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            for (uint256 j = 0; j < logs[i].topics.length; j++) {
                if (logs[i].topics[j] == keccak256("RebalanceCompleted(uint40)")) {
                    isRebalancing = false;
                    rebalancingBaskets = new address[](0);
                    rebalancingTargetWeights = new uint64[][](0);
                    rebalancingBasketAssets = new address[][](0);
                } else if (logs[i].topics[j] == keccak256("RedeemFulfilled(uint256,uint256,uint256)")) {
                    (, uint256 _assets) = abi.decode(logs[i].data, (uint256, uint256));
                    totalDepositsForBasket[logs[i].emitter] -= _assets;
                }
            }
        }

        // Update tracking variables
        _rebalanceStatus = basketManager.rebalanceStatus();
    }

    function revertsWhenStepDelayIsNotMet() public {
        // Get the last action timestamp
        uint256 lastActionTimestamp = basketManager.rebalanceStatus().timestamp;
        vm.assume(lastActionTimestamp > 0);
        // Only if the step delay has not passed
        vm.assume(lastActionTimestamp + basketManager.stepDelay() > vm.getBlockTimestamp());

        try basketManager.completeRebalance(externalTrades, baskets, rebalancingTargetWeights, rebalancingBasketAssets)
        {
            assertTrue(false, "Expected reversion");
        } catch {
            // Expected reversion
        }
    }

    function _getBasketAssets() internal view returns (address[][] memory) {
        address[][] memory basketAssets = new address[][](baskets.length);
        for (uint256 i = 0; i < baskets.length; i++) {
            basketAssets[i] = BasketToken(baskets[i]).getAssets();
        }
        return basketAssets;
    }

    function _simulateTradeSettlement(ExternalTrade[] memory trades) internal {
        // Simulate successful settlement of external trades
        for (uint256 i = 0; i < trades.length; i++) {
            // Transfer tokens to simulate trade execution
            IERC20(trades[i].sellToken).safeTransfer(address(basketManager), trades[i].sellAmount);
            deal(trades[i].buyToken, address(basketManager), trades[i].minAmount);
        }
    }

    // Getters for test contract
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
}
