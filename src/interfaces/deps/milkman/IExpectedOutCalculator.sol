// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity 0.8.28;

interface IExpectedOutCalculator {
    function getExpectedOut(uint256 amountIn, address fromToken, address toToken, bytes calldata data)
        external
        view
        returns (uint256);
}
