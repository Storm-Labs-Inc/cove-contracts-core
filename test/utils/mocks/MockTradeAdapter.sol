// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { console } from "forge-std/console.sol";
import { ExternalTrade } from "src/types/Trades.sol";

contract MockTradeAdapter {
    constructor() { }

    function executeTokenSwap(ExternalTrade[] calldata externalTrades, bytes calldata data) external payable { }

    function completeTokenSwap(ExternalTrade[] calldata externalTrades)
        external
        payable
        returns (uint256[2][] memory claimedAmounts)
    {
        // Initialize return array
        claimedAmounts = new uint256[2][](externalTrades.length);

        // Assume this contract has the tokens necessary to complete the swap, transfer the caller of the function all
        // of them
        for (uint256 i = 0; i < externalTrades.length; i++) {
            ExternalTrade memory trade = externalTrades[i];

            // Record claimed amounts
            claimedAmounts[i][0] = trade.minAmount; // buy amount claimed
            claimedAmounts[i][1] = 0; // sell amount left
        }

        return claimedAmounts;
    }
}
