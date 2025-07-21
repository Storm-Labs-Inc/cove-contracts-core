pragma solidity 0.8.28;

import { BasketTradeOwnership, ExternalTrade, InternalTrade } from "src/types/Trades.sol";
import { BasketManagerHandlers } from "test/invariant/handler/BasketManagerHandlers.deployement.t.sol";

import { console } from "forge-std/console.sol";
import { UserHandler } from "test/invariant/handler/user/UserHandler.sol";

contract ScenarioNoFuzzHandler is BasketManagerHandlers {
    function _user_deposit(uint256 usdcDeposited) internal virtual {
        console.log("\n=== STEP 1: Deposit ===");
        UserHandler(address(users[0])).requestDeposit(0, usdcDeposited);
    }

    function _propose_rebalancing() internal virtual {
        console.log("\n=== STEP 2: REBALANCING PROCESS ===");

        rebalancer.proposeRebalancerOnBasket(address(basketToken));
    }

    function _token_swap(uint256 usdcDeposited) internal virtual returns (ExternalTrade[] memory) {
        // Create internal trades (simplified for this example)
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        // Create external trades
        ExternalTrade[] memory externalTrades = new ExternalTrade[](2);
        // Create empty basket trade ownership arrays
        BasketTradeOwnership[] memory ownership = new BasketTradeOwnership[](1);
        ownership[0] = BasketTradeOwnership({ basket: address(basketToken), tradeOwnership: 1e18 });

        externalTrades[0] = ExternalTrade({
            sellToken: address(assets[0]), // usdc
            buyToken: address(assets[1]), // weth
            sellAmount: usdcDeposited * 30 / 100,
            minAmount: usdcDeposited * 30 / 100,
            basketTradeOwnership: ownership
        });

        externalTrades[1] = ExternalTrade({
            sellToken: address(assets[0]), // usdc
            buyToken: address(assets[2]), // dai
            sellAmount: usdcDeposited * 30 / 100, // Sell 600 USDC
            minAmount: usdcDeposited * 30 / 100,
            basketTradeOwnership: ownership
        });

        address[] memory basketsToRebalance = new address[](1);
        basketsToRebalance[0] = address(basketToken);

        uint64[][] memory targetWeights = new uint64[][](1);
        targetWeights[0] = initialWeights;

        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = basketManager.basketAssets(address(basketToken));

        tokenSwap.proposeSwap(internalTrades, externalTrades, basketsToRebalance, targetWeights, basketAssets);
        tokenSwap.executeSwap();

        console.log("Token swaps executed");

        vm.warp(block.timestamp + 1 days);

        return externalTrades;
    }

    function _complete_rebalancing(ExternalTrade[] memory externalTrades) internal virtual {
        console.log("\n=== STEP 3: Token Swap ===");

        address[] memory basketsToRebalance = new address[](1);
        basketsToRebalance[0] = address(basketToken);

        uint64[][] memory targetWeights = new uint64[][](1);
        targetWeights[0] = initialWeights;

        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = basketManager.basketAssets(address(basketToken));

        // Permionless function
        basketManager.completeRebalance(externalTrades, basketsToRebalance, targetWeights, basketAssets);
    }

    function _finalize_deposit() internal virtual {
        console.log("\n=== STEP 4: Deposit finalize ===");
        UserHandler(address(users[0])).deposit(0);
    }

    /**
     * @notice Tests the complete protocol workflow
     */
    function test_ProtocolWorkflow() public {
        uint256 usdcDeposited = 100 * 10 ** 6;

        _user_deposit(usdcDeposited);

        _propose_rebalancing();

        ExternalTrade[] memory externalTrades = _token_swap(usdcDeposited);

        _complete_rebalancing(externalTrades);

        _finalize_deposit();

        console.log("\n=== FINAL STATE ===");
        console.log("User0's remaining shares:", basketToken.balanceOf(address(users[0])));
        console.log("Basket total assets:", basketToken.totalAssets());
        console.log("Basket balances:");
        console.log("- USDC:", basketManager.basketBalanceOf(address(basketToken), address(assets[0])));
        console.log("- WETH:", basketManager.basketBalanceOf(address(basketToken), address(assets[1])));
        console.log("- DAI:", basketManager.basketBalanceOf(address(basketToken), address(assets[2])));

        assert(basketToken.balanceOf(address(users[0])) == 100 * 10 ** 6);
    }
}
