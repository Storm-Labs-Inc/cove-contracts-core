// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";

import { Constants } from "test/utils/Constants.t.sol";

contract Mag7ConstantsTest is Test, Constants {
    function test_mag7AddressesNonZero() public {
        assertTrue(ETH_AAPLON != address(0));
        assertTrue(ETH_MSFTON != address(0));
        assertTrue(ETH_GOOGLON != address(0));
        assertTrue(ETH_AMZNON != address(0));
        assertTrue(ETH_NVDAON != address(0));
        assertTrue(ETH_METAON != address(0));
        assertTrue(ETH_TSLAON != address(0));
    }

    function test_mag7PythFeedIdsNonZero() public {
        assertTrue(PYTH_AAPL_USD_FEED != bytes32(0));
        assertTrue(PYTH_MSFT_USD_FEED != bytes32(0));
        assertTrue(PYTH_GOOGL_USD_FEED != bytes32(0));
        assertTrue(PYTH_AMZN_USD_FEED != bytes32(0));
        assertTrue(PYTH_NVDA_USD_FEED != bytes32(0));
        assertTrue(PYTH_META_USD_FEED != bytes32(0));
        assertTrue(PYTH_TSLA_USD_FEED != bytes32(0));
    }

    function test_mag7RedstoneFeedIdsNonZero() public {
        assertTrue(REDSTONE_AAPL_USD_FEED != bytes32(0));
        assertTrue(REDSTONE_MSFT_USD_FEED != bytes32(0));
        assertTrue(REDSTONE_GOOGL_USD_FEED != bytes32(0));
        assertTrue(REDSTONE_AMZN_USD_FEED != bytes32(0));
        assertTrue(REDSTONE_NVDA_USD_FEED != bytes32(0));
        assertTrue(REDSTONE_META_USD_FEED != bytes32(0));
        assertTrue(REDSTONE_TSLA_USD_FEED != bytes32(0));
    }

    function test_redstoneDefaultDecimals() public {
        assertEq(REDSTONE_DEFAULT_FEED_DECIMALS, 8);
    }
}
