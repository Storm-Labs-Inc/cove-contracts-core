// SPDX-License-Identifier: LGPL-3.0-or-later 
pragma solidity 0.8.28;

import { IExpectedOutCalculator } from "src/interfaces/deps/milkman/IExpectedOutCalculator.sol";
import { IUniV2 } from "src/interfaces/deps/milkman/IUniV2.sol";

/// @notice Expected output calculator that routes through a Uniswap V2 style router (SushiSwap).
/// @dev Mirrors Milkman's implementation with updated pragma and without SafeMath.
contract UniV2ExpectedOutCalculator is IExpectedOutCalculator {
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    string public NAME;
    address public immutable UNIV2_ROUTER;

    constructor(string memory name_, address univ2Router) {
        NAME = name_;
        UNIV2_ROUTER = univ2Router;
    }

    function getExpectedOut(uint256 amountIn, address fromToken, address toToken, bytes calldata)
        external
        view
        override
        returns (uint256)
    {
        address[] memory path;

        if (fromToken == WETH || toToken == WETH) {
            path = new address[](2);
            path[0] = fromToken;
            path[1] = toToken;
        } else {
            path = new address[](3);
            path[0] = fromToken;
            path[1] = WETH;
            path[2] = toToken;
        }

        uint256[] memory amounts = IUniV2(UNIV2_ROUTER).getAmountsOut(amountIn, path);
        return amounts[amounts.length - 1];
    }
}
