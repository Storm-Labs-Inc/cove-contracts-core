// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BasketToken } from "src/BasketToken.sol";

contract MockBasketManager {
    BasketToken public basketTokenImplementation;

    constructor(address basketTokenImplementation_) {
        basketTokenImplementation = BasketToken(basketTokenImplementation_);
    }

    function createNewBasket(
        IERC20 asset,
        string memory basketName,
        string memory symbol,
        uint256 bitFlag,
        address strategy,
        address owner
    )
        public
        returns (BasketToken basket)
    {
        basket = BasketToken(Clones.clone(address(basketTokenImplementation)));
        basket.initialize(asset, basketName, symbol, bitFlag, strategy, owner);
        BasketToken(basket).approve(address(basket), type(uint256).max);
        IERC20(asset).approve(address(basket), type(uint256).max);
    }

    function fulfillDeposit(address basket, uint256 sharesToIssue) external {
        BasketToken(basket).fulfillDeposit(sharesToIssue);
    }

    function fulfillRedeem(address basket, uint256 assetsToIssue) external {
        BasketToken(basket).fulfillRedeem(assetsToIssue);
    }
}
