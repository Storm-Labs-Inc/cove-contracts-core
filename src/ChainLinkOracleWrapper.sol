// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { IChainlinkAggregatorV3Interface } from "src/interfaces/deps/IChainlinkAggregatorV3Interface.sol";

contract ChainLinkOracleWrapper {
    constructor() { }

    /**
     * Returns the latest price
     */
    function getLatestPrice(address priceFeedAddress) public view returns (uint80, int256, uint256, uint256, uint80) {
        IChainlinkAggregatorV3Interface priceFeed = IChainlinkAggregatorV3Interface(priceFeedAddress);
        (uint80 roundID, int256 price, uint256 startedAt, uint256 timeStamp, uint80 answeredInRound) =
            priceFeed.latestRoundData();
        return (roundID, price, startedAt, timeStamp, answeredInRound);
    }
}
