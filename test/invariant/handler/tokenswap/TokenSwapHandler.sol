pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";

import { BasketManager } from "src/BasketManager.sol";
import { ExternalTrade, InternalTrade } from "src/types/Trades.sol";

import { Status } from "src/types/BasketManagerStorage.sol";
import { RebalancerHandler } from "test/invariant/handler/rebalancer/RebalancerHandler.sol";

import { GlobalState } from "test/invariant/handler/GlobalState.sol";
import { BasketManagerValidationLib } from "test/utils/BasketManagerValidationLib.sol";

/**
 * @title TokenSwapHandler
 * @notice Handler for token swap and rebalance operations
 * @dev Coordinates with RebalancerHandler and GlobalState for complete rebalance cycles
 */
contract TokenSwapHandler is Test {
    using BasketManagerValidationLib for BasketManager;

    ExternalTrade[] public last_externalTrades;
    address[] public last_basketsToRebalance;
    uint64[][] public last_targetWeights;
    address[][] public last_basketAssets;

    BasketManager public basketManager;
    GlobalState public globalState;

    RebalancerHandler rebalancer;

    uint256 successfull_proposeswap;
    uint256 successfull_executeswap;
    uint256 successfull_rebalance;

    /**
     * @notice Initializes the token swap handler
     * @param basketManagerParameter The BasketManager contract
     * @param rebalancerParameter The rebalancer handler for coordination
     * @param globalStateParameter Global state for coordination
     */
    constructor(
        BasketManager basketManagerParameter,
        RebalancerHandler rebalancerParameter,
        GlobalState globalStateParameter
    ) {
        require(address(basketManagerParameter) != address(0));
        basketManager = basketManagerParameter;
        require(address(rebalancerParameter) != address(0));
        rebalancer = rebalancerParameter;
        require(address(globalStateParameter) != address(0));
        globalState = globalStateParameter;
    }

    /**
     * @notice Proposes a token swap with given trades and parameters
     * @dev Uses try/catch to handle potential failures gracefully
     */
    function proposeSwap(
        InternalTrade[] memory internalTrades,
        ExternalTrade[] memory externalTrades,
        address[] memory basketsToRebalance,
        uint64[][] memory targetWeights,
        address[][] memory basketAssets
    )
        public
    {
        // proposeTokenSwap might fail for various reasons (invalid parameter, status not in rebalance etc)
        // Given we used "fail_on_revert" on foundry setup, we use try/catch on this call
        // The alternative would be to validate the call state before calling proposeTokenSwap
        try basketManager.proposeTokenSwap(
            internalTrades, externalTrades, basketsToRebalance, targetWeights, basketAssets
        ) {
            last_externalTrades = externalTrades;
            last_basketsToRebalance = basketsToRebalance;
            last_targetWeights = targetWeights;
            last_basketAssets = basketAssets;

            successfull_proposeswap++;
        } catch {
            revert();
        }
    }

    /**
     * @notice Executes the previously proposed token swap
     * @dev Only works if status is TOKEN_SWAP_PROPOSED
     */
    function executeSwap() public {
        if (basketManager.rebalanceStatus().status != Status.TOKEN_SWAP_PROPOSED) {
            return;
        }

        basketManager.executeTokenSwap(last_externalTrades, ""); // Empty data for mock

        //delete last_externalTrades;

        successfull_executeswap++;
    }

    /**
     * @notice Proposes and immediately executes a token swap
     */
    function proposeAndExecuteSwap(
        InternalTrade[] calldata internalTrades,
        ExternalTrade[] calldata externalTrades,
        address[] calldata basketsToRebalance,
        uint64[][] calldata targetWeights,
        address[][] calldata basketAssets
    )
        public
    {
        proposeSwap(internalTrades, externalTrades, basketsToRebalance, targetWeights, basketAssets);
        executeSwap();
    }

    /**
     * @notice Proposes a smart swap using rebalancer's proposed baskets and generated trades
     */
    function proposeSmartSwap() public {
        address[] memory _rebalancingBaskets = rebalancer.baskets_proposed();

        uint64[][] memory targetWeights = basketManager.testLib_getTargetWeights(_rebalancingBaskets);

        (InternalTrade[] memory newInternalTrades, ExternalTrade[] memory newExternalTrades) =
            basketManager.testLib_generateInternalAndExternalTrades(_rebalancingBaskets, targetWeights);

        address[][] memory basketAssets = new address[][](_rebalancingBaskets.length);

        for (uint256 i = 0; i < basketAssets.length; i++) {
            basketAssets[i] = basketManager.basketAssets(_rebalancingBaskets[i]);
        }

        proposeSwap(newInternalTrades, newExternalTrades, _rebalancingBaskets, targetWeights, basketAssets);
    }

    /**
     * @notice Completes the rebalance process and updates global state
     */
    function completeRebalance() public {
        try basketManager.completeRebalance(
            last_externalTrades, last_basketsToRebalance, last_targetWeights, last_basketAssets
        ) {
            successfull_rebalance++;

            globalState.rebalance_compeleted();
        } catch {
            revert();
        }
    }

    /**
     * @notice Returns the last external trades
     */
    function externalTrades() public view returns (ExternalTrade[] memory) {
        return last_externalTrades;
    }

    /**
     * @notice Returns the last rebalancing baskets
     */
    function rebalancingBaskets() public view returns (address[] memory) {
        return last_basketsToRebalance;
    }

    /**
     * @notice Returns the last target weights
     */
    function targetWeights() public view returns (uint64[][] memory) {
        return last_targetWeights;
    }

    /**
     * @notice Returns the last basket assets
     */
    function basketAssets() public view returns (address[][] memory) {
        return last_basketAssets;
    }
}
