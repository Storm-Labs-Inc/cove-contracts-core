// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { console } from "forge-std/console.sol";

import { ExternalTrade } from "src/types/Trades.sol";
// import { airdrop, takeaway } from "test/utils/BaseTest.t.sol";

contract MockTradeAdapter {
    constructor() { }

    // solhint-disable-next-line no-unused-vars
    function executeTokenSwap(ExternalTrade[] calldata externalTrades, bytes calldata data) external payable {
        for (uint256 i = 0; i < externalTrades.length; i++) {
            // Mimic cowswaps transfer of funds to a clone contract
            IERC20(externalTrades[i].sellToken).transfer(address(1), externalTrades[i].sellAmount);
            console.log("executeTokenSwap: transfered token: ", externalTrades[i].sellToken);
            console.log("executeTokenSwap: transfered amount: ", externalTrades[i].sellAmount);
        }
    }

    function completeTokenSwap(ExternalTrade[] calldata externalTrades)
        external
        payable
        returns (uint256[2][] memory claimedAmounts)
    {
        // Initialize return array
        claimedAmounts = new uint256[2][](externalTrades.length);

        // // Assume this contract has the tokens necessary to complete the swap
        for (uint256 i = 0; i < externalTrades.length; i++) {
            // $PEPE flag for testing
            if (IERC20(0x6982508145454Ce325dDbE47a25d4ec3d2311933).balanceOf(address(this)) == 0) {
                claimedAmounts[i][0] = externalTrades[i].minAmount;
                claimedAmounts[i][1] = 0;
            } else {
                claimedAmounts[i][0] = 0;
                claimedAmounts[i][1] = externalTrades[i].sellAmount;
                console.log("adapter trade failed giving back token: ", externalTrades[i].sellToken);
                console.log("adapter trade failed giving back amount: ", externalTrades[i].sellAmount);
            }
        }

        return claimedAmounts;
    }
}
