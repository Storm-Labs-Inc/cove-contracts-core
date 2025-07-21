pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { BasketManager } from "src/BasketManager.sol";

contract RebalancerHandler is Test {
    BasketManager public basketManager;

    // Assume BasketManagerUtils.proposeRebalance prevent to call proposeRebalance if a rebalance is already running
    // Which ensure that all further call to basketManager.proposeRebalance will fail
    // see MustWaitForRebalanceToComplete
    address[] public latest_baskets_proposed;

    uint256 successfull_proposeRebalance;

    constructor(BasketManager basketManagerParameter) {
        require(address(basketManagerParameter) != address(0));
        basketManager = basketManagerParameter;
    }

    /**
     * @notice Proposes rebalancing for selected baskets
     * @param basketsSelected Array of boolean flags indicating which baskets to rebalance
     */
    function proposeRebalancer(bool[] memory basketsSelected) public {
        // Assume _createRebalanceBitMask works
        // properly and filter the invalid basket
        // We do this avoid fuzzing random basket address
        // and wasting cycles
        address[] memory all_baskets = basketManager.basketTokens();
        address[] memory baskets = new address[](all_baskets.length);

        if (basketsSelected.length > baskets.length) {
            revert();
        }

        for (uint256 i = 0; i < all_baskets.length; i++) {
            if (i >= basketsSelected.length) {
                break;
            }

            if (basketsSelected[i]) {
                baskets[i] = all_baskets[i];
            }
        }

        _proposeRebalance(baskets);
    }

    /**
     * @notice Proposes rebalancing for a specific basket
     * @param basket Address of the basket to rebalance
     */
    function proposeRebalancerOnBasket(address basket) public {
        address[] memory baskets = new address[](1);
        baskets[0] = basket;

        _proposeRebalance(baskets);
    }

    /**
     * @notice Proposes rebalancing for all baskets
     */
    function proposeRebalancerOnAll() public {
        address[] memory baskets = basketManager.basketTokens();

        _proposeRebalance(baskets);
    }

    function _proposeRebalance(address[] memory baskets) internal {
        // proposeRebalance might fail for various reasons (invalid parameter etc)
        // Given we used "fail_on_revert" on foundry setup, we use try/catch on this call
        // The alternative would be to validate the call state before calling proposeRebalance
        try basketManager.proposeRebalance(baskets) {
            latest_baskets_proposed = baskets;

            successfull_proposeRebalance++;
        } catch {
            revert();
        }
    }

    /**
     * @notice Returns the list of baskets that have been proposed for rebalancing
     * @return Array of basket addresses proposed for rebalancing
     */
    function baskets_proposed() public view returns (address[] memory) {
        return latest_baskets_proposed;
    }
}
