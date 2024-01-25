// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { IChainlinkAggregatorV3Interface } from "src/interfaces/deps/IChainlinkAggregatorV3Interface.sol";

contract ChainLinkOracleWrapper {
    constructor() {}

    /**
     * Returns the latest price
     */
    function getLatestPrice(address priceFeedAddress) public view returns (uint80, int, uint, uint, uint80) {
        IChainlinkAggregatorV3Interface priceFeed = IChainlinkAggregatorV3Interface(priceFeedAddress);
        (
            uint80 roundID,
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        return (roundID, price, startedAt, timeStamp, answeredInRound);
    }
}
