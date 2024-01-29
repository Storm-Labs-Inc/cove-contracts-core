// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { IPyth } from "src/interfaces/deps/IPyth.sol";
import { IChainlinkAggregatorV3Interface } from "src/interfaces/deps/IChainlinkAggregatorV3Interface.sol";

contract ERC4626OracleWrapper {
    mapping(address => address) public assetToPriceFeed;
    mapping(address => bytes32) public assetToPriceId;
    address public pythContract;
    address public chainlinkContract;

    constructor(address _pythContract, address _chainlinkContract) {
        pythContract = _pythContract;
        chainlinkContract = _chainlinkContract;
    }

    function updateFetchPythPrice(
        address asset,
        bytes[] calldata priceUpdateData
    )
        public
        returns (IPyth.Price memory)
    {
        // eth contract: 0x4305fb66699c3b2702d4d05cf36551390a4c69c6
        IPyth pyth = IPyth(pythContract);
        uint256 fee = pyth.getUpdateFee(priceUpdateData);
        // Update the prices to be set to the latest values
        pyth.updatePriceFeeds{ value: fee }(priceUpdateData);
        // eth/usd price feed found here: https://pyth.network/developers/price-feed-ids
        // bytes32 priceId = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
        return pyth.getPrice(assetToPriceId[asset]);
    }

    function getLatestChainlinkPrice(address asset) public view returns (uint80, int256, uint256, uint256, uint80) {
        IChainlinkAggregatorV3Interface priceFeed = IChainlinkAggregatorV3Interface(assetToPriceFeed[asset]);
        (uint80 roundID, int256 price, uint256 startedAt, uint256 timeStamp, uint80 answeredInRound) =
            priceFeed.latestRoundData();
        return (roundID, price, startedAt, timeStamp, answeredInRound);
    }

    function addPriceFeed(address asset, address priceFeed) public {
        assetToPriceFeed[asset] = priceFeed;
    }

    function updatePriceFeed(address asset, address priceFeed) public {
        assetToPriceFeed[asset] = priceFeed;
    }

    function addPriceId(address asset, bytes32 priceId) public {
        assetToPriceId[asset] = priceId;
    }

    function updatePriceId(address asset, bytes32 priceId) public {
        assetToPriceId[asset] = priceId;
    }
}
