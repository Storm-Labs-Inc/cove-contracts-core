pragma solidity 0.8.28;

import { ExternalTrade } from "src/types/Trades.sol";
import { ERC20DecimalsMock } from "test/utils/mocks/ERC20DecimalsMock.sol";

/// @notice This mock behaves as a perfect token swapper, where the exact amount of tokens are sold and bought
contract TokenSwapAdapterMock {
    // This address holds the tokens that are sold
    address constant COW_SINK = address(0xdeadbeef);

    /// @notice Executes series of token swaps and returns the hashes of the orders submitted/executed
    /// @param externalTrades The external trades to execute
    function executeTokenSwap(ExternalTrade[] calldata externalTrades, bytes calldata) external payable {
        for (uint256 i = 0; i < externalTrades.length; i++) {
            uint256 sold = externalTrades[i].sellAmount;
            ERC20DecimalsMock token = ERC20DecimalsMock(externalTrades[i].sellToken);

            token.transfer(COW_SINK, sold);
        }
    }

    /// @notice Completes the token swaps by confirming each order settlement and claiming the resulting tokens (if
    /// necessary).
    /// @dev This function must return the exact amounts of sell tokens and buy tokens claimed per trade.
    /// If the adapter operates asynchronously (e.g., CoWSwap), this function should handle the following:
    /// - Cancel any unsettled trades to prevent further execution.
    /// - Claim the remaining tokens from the unsettled trades.
    ///
    /// @param externalTrades The external trades that were executed and need to be settled.
    /// @return claimedAmounts A 2D array where each element contains the claimed amounts of sell tokens and buy tokens
    /// for each corresponding trade in `externalTrades`. The first element of each sub-array is the claimed sell
    /// amount, and the second element is the claimed buy amount.
    function completeTokenSwap(ExternalTrade[] calldata externalTrades)
        external
        payable
        virtual
        returns (uint256[2][] memory claimedAmounts)
    {
        claimedAmounts = new uint256[2][](externalTrades.length);

        for (uint256 i = 0; i < externalTrades.length; i++) {
            uint256 bought = externalTrades[i].minAmount;

            claimedAmounts[i][0] = 0;
            claimedAmounts[i][1] = bought;

            ERC20DecimalsMock token = ERC20DecimalsMock(externalTrades[i].buyToken);
            token.mint(address(this), bought);
        }
    }
}
