// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IPyth } from "@pyth/IPyth.sol";
import { PythStructs } from "@pyth/PythStructs.sol";

import { ChainlinkOracle } from "euler-price-oracle/src/adapter/chainlink/ChainlinkOracle.sol";
import { PythOracle } from "euler-price-oracle/src/adapter/pyth/PythOracle.sol";
import { Errors } from "euler-price-oracle/src/lib/Errors.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

import { AnchoredOracle } from "src/AnchoredOracle.sol";

contract AnchoredOracle_ForkedTest is BaseTest {
    uint256 public MAX_DIVERGENCE = 0.02e18; // 2.0%

    PythOracle public primary;
    ChainlinkOracle public anchor;
    AnchoredOracle public oracle;

    function setUp() public override {
        // Fork ethereum mainnet at block 20113049 for consistent testing and to cache RPC calls
        // https://etherscan.io/block/20113049
        forkNetworkAt("mainnet", 20_113_049);
        super.setUp();

        // https://pyth.network/price-feeds/crypto-eth-usd
        primary = new PythOracle(PYTH, ETH, USD, PYTH_ETH_USD_FEED, 15 minutes, 500);
        // https://data.chain.link/feeds/ethereum/mainnet/eth-usd
        anchor = new ChainlinkOracle(ETH, USD, ETH_CHAINLINK_ETH_USD_FEED, 1 days);
        oracle = new AnchoredOracle(address(primary), address(anchor), MAX_DIVERGENCE);
    }

    function test_getQuote_revertWhen_stalePrice() public {
        vm.expectRevert(Errors.PriceOracle_InvalidAnswer.selector);
        oracle.getQuote(1e18, ETH, USD);
    }

    function test_getQuote() public {
        // Ref: https://github.com/euler-xyz/euler-price-oracle/blob/experiments/test/adapter/pyth/PythOracle.fork.t.sol
        PythStructs.Price memory p = IPyth(PYTH).getPriceUnsafe(PYTH_ETH_USD_FEED);
        p.publishTime = vm.getBlockTimestamp() - 5 minutes;
        vm.mockCall(PYTH, abi.encodeCall(IPyth.getPriceUnsafe, (PYTH_ETH_USD_FEED)), abi.encode(p));

        uint256 outAmount = oracle.getQuote(1e18, ETH, USD);
        assertEq(outAmount, 349_371_565_257e10);
    }

    function test_getQuote_revertWhen_divergenceTooHigh(uint256 divergencePercent, uint256 amount) public {
        // Bound divergence between 2.1% and 100% (above MAX_DIVERGENCE of 2%)
        divergencePercent = bound(divergencePercent, 21, 1000);
        divergencePercent = divergencePercent * 1e15; // Convert to WAD (e.g., 21 -> 0.021e18 -> 2.1%)
        // Bound amount between 0.1e18 and 1000e18
        amount = bound(amount, 0.1e18, 1000e18);

        // Get Chainlink's current price
        uint256 chainlinkPrice = anchor.getQuote(amount, ETH, USD);

        // Mock Pyth price
        PythStructs.Price memory p = IPyth(PYTH).getPriceUnsafe(PYTH_ETH_USD_FEED);

        // Calculate the adjusted price based on Chainlink's price plus our divergence
        uint256 adjustedPrice = chainlinkPrice * (1e18 + divergencePercent) / 1e18;
        p.price = int64(int256(adjustedPrice / 1e10)); // Adjust for Pyth's decimal format
        p.publishTime = vm.getBlockTimestamp() - 5 minutes;

        vm.mockCall(PYTH, abi.encodeCall(IPyth.getPriceUnsafe, (PYTH_ETH_USD_FEED)), abi.encode(p));

        vm.expectRevert(Errors.PriceOracle_InvalidAnswer.selector);
        oracle.getQuote(amount, ETH, USD);
    }
}
