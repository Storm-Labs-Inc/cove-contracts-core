// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { IPyth } from "src/interfaces/deps/IPyth.sol";

contract PythOracleWrapper {
    constructor(address pythContract) { }

    function updateFeeGetPrice(
        address pythContract,
        bytes32 priceId,
        bytes[] calldata priceUpdateData
    )
        public
        payable
        returns (IPyth.Price memory)
    {
        // eth contract: 0x4305fb66699c3b2702d4d05cf36551390a4c69c6
        IPyth pyth = IPyth(pythContract);
        uint256 fee = pyth.getUpdateFee(priceUpdateData);
        // Update the prices to be set to the latest values
        pyth.updatePriceFeeds{ value: fee }(priceUpdateData);

        // Doing other things that uses prices
        // eth/usd price feed found here: https://pyth.network/developers/price-feed-ids
        // bytes32 priceId = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;

        return pyth.getPrice(priceId);
    }
}
