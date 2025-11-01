// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IUniV2 {
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
}
