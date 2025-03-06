// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { console } from "forge-std/console.sol";

import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { RebalanceStatus } from "src/types/BasketManagerStorage.sol";
import { ExternalTrade, InternalTrade } from "src/types/Trades.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";
import { BasketManagerTestLib } from "test/utils/BasketManagerTestLib.t.sol";

contract BasketManager_InvariantTest is StdInvariant, BaseTest {
    using SafeERC20 for IERC20;
    using BasketManagerTestLib for BasketManager;

    BasketManagerHandler public handler;

    // Constants for test configuration
    uint256 private constant ACTOR_COUNT = 5;
    uint256 private constant INITIAL_BALANCE = 1_000_000;
    uint256 private constant DEPOSIT_AMOUNT = 10_000;

    function setUp() public virtual override {
        super.setUp();
        forkNetworkAt("mainnet", BLOCK_NUMBER_MAINNET_FORK);

        // Deploy handler with multiple baskets
        BasketManager basketManager = _setupBasketManager();
        address[] memory baskets = _setupBaskets(basketManager);
        address[] memory assets = _setupAssets(basketManager);

        // Create and configure handler
        handler = new BasketManagerHandler(basketManager, baskets, assets, ACTOR_COUNT);

        targetContract(address(handler));

        // Fund test accounts
        _fundActors();
    }

    function invariant_basketManagerIsOperational() public {
        // Check if BasketManager is not paused
        assertTrue(!handler.basketManager().paused(), "BasketManager should not be paused");
    }

    function invariant_basketBalancesMatchDeposits() public {
        // For each basket, verify total assets match deposits
        address[] memory baskets = handler.baskets();
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

    function _setupBasketManager() internal virtual returns (BasketManager) {
        return BasketManager(address(0));
    }

    function _setupBaskets(BasketManager basketManager) internal virtual returns (address[] memory) {
        // Return array of basket addresses
        return basketManager.basketTokens();
    }

    function _setupAssets(BasketManager basketManager) internal virtual returns (address[] memory) {
        // Return array of asset addresses
        return basketManager.assetRegistry().getAllAssets();
    }

    function _fundActors() internal {
        address[] memory actors = handler.actors();
        address[] memory assets = handler.assets();

        for (uint256 i = 0; i < actors.length; i++) {
            for (uint256 j = 0; j < assets.length; j++) {
                deal(assets[j], actors[i], INITIAL_BALANCE * (10 ** handler.decimals(assets[j])));
            }
        }
    }
}

contract BasketManagerHandler is BaseTest {
    using SafeERC20 for IERC20;

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

    function requestDeposit(uint256 actorIdx, uint256 basketIdx, uint256 amount) public {
        address actor = actors[actorIdx % actors.length];
        address basket = baskets[basketIdx % baskets.length];

        // Bound amount to the actor's balance
        amount = bound(amount, 1, IERC20(BasketToken(basket).asset()).balanceOf(actor));

        vm.startPrank(actor);
        // Perform deposit request logic
        IERC20(BasketToken(basket).asset()).approve(address(basketManager), amount);
        BasketToken(basket).requestDeposit(amount, actor, actor);
        vm.stopPrank();

        depositsPendingRebalance[basket][actor] += amount;
    }

    function requestRedeem(uint256 actorIdx, uint256 basketIdx, uint256 amount) public {
        address actor = actors[actorIdx % actors.length];
        address basket = baskets[basketIdx % baskets.length];

        uint256 balance = BasketToken(basket).balanceOf(actor);
        amount = bound(amount, 1, balance);

        vm.startPrank(actor);
        BasketToken(basket).requestRedeem(amount, actor, actor);
        vm.stopPrank();

        redeemsPendingRebalance[basket][actor] += amount;
    }

    function proposeRebalance() public {
        vm.assume(!isRebalancing);

        vm.startPrank(basketManager.hasRole(REBALANCE_PROPOSER_ROLE));
        basketManager.testLib_updateOracleTimestamps();
        basketManager.proposeRebalance(baskets);
        vm.stopPrank();

        // Update tracking variables
        isRebalancing = true;
        _rebalanceStatus = basketManager.rebalanceStatus();
    }

    function proposeTokenSwap(InternalTrade[] memory _internalTrades, ExternalTrade[] memory _externalTrades) public {
        vm.assume(isRebalancing);

        // Propose and execute token swaps
        vm.startPrank(basketManager.hasRole(TOKENSWAP_PROPOSER_ROLE));
        basketManager.testLib_updateOracleTimestamps();
        basketManager.proposeTokenSwap(
            _internalTrades, _externalTrades, rebalancingBaskets, rebalancingTargetWeights, _getBasketAssets()
        );
        vm.stopPrank();

        // Update tracking variables
        internalTrades = _internalTrades;
        externalTrades = _externalTrades;
        _rebalanceStatus = basketManager.rebalanceStatus();

        // Execute trades
        vm.startPrank(basketManager.hasRole(TOKENSWAP_EXECUTOR_ROLE));
        basketManager.executeTokenSwap(externalTrades, "");
        vm.stopPrank();

        // Simulate trade settlement
        _simulateTradeSettlement(externalTrades);
    }

    function completeRebalance() public {
        vm.assume(isRebalancing);

        // Wait required delay
        vm.warp(vm.getTimestamp() + basketManager.stepDelay());

        // Update oracle timestamps
        BasketManagerTestLib.updateOracleTimestamps(basketManager);

        basketManager.completeRebalance(
            externalTrades, baskets, basketManager.testLib_getTargetWeights(), _getBasketAssets()
        );

        // Update tracking variables
        isRebalancing = false;
        _rebalanceStatus = basketManager.rebalanceStatus();
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
}
