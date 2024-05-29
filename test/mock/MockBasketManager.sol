// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { BasketToken } from "src/BasketToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

contract MockBasketManager {
    BasketToken public basketTokenImplementation;
    mapping(uint256 => address) strategyIdToAddress;

    constructor(address basketTokenImplementation_) {
        basketTokenImplementation = BasketToken(basketTokenImplementation_);
    }

    function createNewBasket(
        IERC20 asset,
        string memory basketName,
        string memory symbol,
        uint256 bitFlag,
        uint256 strategyId
    )
        public
        returns (BasketToken basket)
    {
        basket = BasketToken(Clones.clone(address(basketTokenImplementation)));
        basket.initialize(asset, basketName, symbol, bitFlag, strategyId);
        strategyIdToAddress[strategyId] = address(basket);
        BasketToken(basket).approve(address(basket), type(uint256).max);
        IERC20(asset).approve(address(basket), type(uint256).max);
    }

    function fulfillDeposit(address basket, uint256 sharesToIssue) external {
        BasketToken(basket).fulfillDeposit(sharesToIssue);
    }

    function fulfillRedeem(address basket, uint256 assetsToIssue) external {
        BasketToken(basket).fulfillRedeem(assetsToIssue);
    }

    function totalAssetValue(uint256 strategyId) external view returns (uint256) {
        return IERC20(BasketToken(strategyIdToAddress[strategyId]).asset()).balanceOf(address(this));
    }
}
