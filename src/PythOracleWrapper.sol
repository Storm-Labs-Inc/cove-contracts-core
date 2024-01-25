// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { IPyth } from "src/interfaces/deps/IPyth.sol";

contract PythOracleWrapper {
  IPyth pyth;

  constructor(address pythContract) {
    // eth contract: 0x4305fb66699c3b2702d4d05cf36551390a4c69c6
    pyth = IPyth(pythContract);
  }

  function getPrice(
    uint someArg,
    string memory otherArg,
    bytes[] calldata priceUpdateData
  ) public payable {
    // Update the prices to be set to the latest values
    uint fee = pyth.getUpdateFee(priceUpdateData);
    pyth.updatePriceFeeds{ value: fee }(priceUpdateData);

    // Doing other things that uses prices
    // eth/usd price feed found here: https://pyth.network/developers/price-feed-ids
    bytes32 priceId = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;

    IPyth.Price memory price = pyth.getPrice(priceId);
  }
}