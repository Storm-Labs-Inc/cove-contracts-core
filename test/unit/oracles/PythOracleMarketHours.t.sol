// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { PythStructs } from "@pyth/PythStructs.sol";
import { Errors } from "euler-price-oracle/src/lib/Errors.sol";

import { PythOracleMarketHours } from "src/oracles/PythOracleMarketHours.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";
import { ERC20DecimalsMock } from "test/utils/mocks/ERC20DecimalsMock.sol";

contract StubPyth {
    PythStructs.Price private price;

    function setPrice(PythStructs.Price memory _price) external {
        price = _price;
    }

    function getPriceUnsafe(bytes32) external view returns (PythStructs.Price memory) {
        return price;
    }
}

contract PythOracleMarketHoursTest is BaseTest {
    StubPyth internal pyth;
    ERC20DecimalsMock internal base;
    ERC20DecimalsMock internal quote;
    PythOracleMarketHours internal oracle;

    bytes32 internal constant FEED_ID = bytes32(uint256(1));
    uint256 internal constant MAX_STALENESS = 60 seconds;
    uint256 internal constant MAX_CONF_WIDTH = 50; // 0.5%

    function setUp() public override {
        super.setUp();
        pyth = new StubPyth();
        base = new ERC20DecimalsMock(18, "Base", "BASE");
        quote = new ERC20DecimalsMock(6, "USD Coin", "USDC");
        oracle = new PythOracleMarketHours(
            address(pyth), address(base), address(quote), FEED_ID, MAX_STALENESS, MAX_CONF_WIDTH
        );
    }

    function _setPrice(uint256 publishTime) internal {
        PythStructs.Price memory p = PythStructs.Price({
            price: 100_000_000, // 1.00 with expo -8
            conf: 1,
            expo: -8,
            publishTime: publishTime
        });
        pyth.setPrice(p);
    }

    function _assertQuote(uint256 ts) internal {
        vm.warp(ts);
        _setPrice(ts);
        uint256 out = oracle.getQuote(1e18, address(base), address(quote));
        assertGt(out, 0);
    }

    function _assertRevertInvalid(uint256 ts) internal {
        vm.warp(ts);
        _setPrice(ts);
        vm.expectRevert(Errors.PriceOracle_InvalidAnswer.selector);
        oracle.getQuote(1e18, address(base), address(quote));
    }

    function test_getQuote_passWhen_withinMarketHours_EST() public {
        _assertQuote(1_768_230_000); // 2026-01-12 15:00:00 UTC (10:00 ET)
    }

    function test_getQuote_passWhen_openBoundary_EST() public {
        _assertQuote(1_768_228_200); // 2026-01-12 14:30:00 UTC (09:30 ET)
    }

    function test_getQuote_passWhen_closeBoundary_EST() public {
        _assertQuote(1_768_251_600); // 2026-01-12 21:00:00 UTC (16:00 ET)
    }

    function test_getQuote_revertWhen_afterClose_EST() public {
        _assertRevertInvalid(1_768_251_601); // 2026-01-12 21:00:01 UTC (16:00:01 ET)
    }

    function test_getQuote_revertWhen_beforeOpen_EST() public {
        _assertRevertInvalid(1_768_222_800); // 2026-01-12 13:00:00 UTC (08:00 ET)
    }

    function test_getQuote_revertWhen_weekend() public {
        _assertRevertInvalid(1_768_057_200); // 2026-01-10 15:00:00 UTC (Saturday)
    }

    function test_getQuote_passWhen_dstOpenBoundary() public {
        _assertQuote(1_773_063_000); // 2026-03-09 13:30:00 UTC (09:30 EDT)
    }

    function test_getQuote_revertWhen_beforeOpen_DST() public {
        _assertRevertInvalid(1_773_057_600); // 2026-03-09 12:00:00 UTC (08:00 EDT)
    }

    function test_getQuote_passWhen_afterDstEnd_EST() public {
        _assertQuote(1_793_631_600); // 2026-11-02 15:00:00 UTC (10:00 EST)
    }

    function test_getQuote_revertWhen_beforeOpen_afterDstEnd() public {
        _assertRevertInvalid(1_793_628_000); // 2026-11-02 14:00:00 UTC (09:00 EST)
    }
}
