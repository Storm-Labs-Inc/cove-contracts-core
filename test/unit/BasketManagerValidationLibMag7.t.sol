// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";

import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { RedstoneCoreOracle } from "euler-price-oracle/src/adapter/redstone/RedstoneCoreOracle.sol";

import { PythStructs } from "@pyth/PythStructs.sol";

import { AnchoredOracle } from "src/oracles/AnchoredOracle.sol";
import { PythOracleMarketHours } from "src/oracles/PythOracleMarketHours.sol";
import { BasketManagerValidationLib } from "test/utils/BasketManagerValidationLib.sol";
import { Constants } from "test/utils/Constants.t.sol";

contract StubPythMag7 {
    function getPriceUnsafe(bytes32) external pure returns (PythStructs.Price memory) {
        return PythStructs.Price({ price: 0, conf: 0, expo: 0, publishTime: 0 });
    }
}

contract BasketManagerValidationLibHarness {
    function validateOraclePath(EulerRouter router, address asset) external view {
        BasketManagerValidationLib.testLib_validateOraclePath(router, asset);
    }
}

contract BasketManagerValidationLibMag7Test is Test, Constants {
    StubPythMag7 internal pyth;
    PythOracleMarketHours internal pythOracle;
    RedstoneCoreOracle internal redstoneOracle;
    AnchoredOracle internal anchoredOracle;
    EulerRouter internal router;
    BasketManagerValidationLibHarness internal harness;

    function setUp() public {
        pyth = new StubPythMag7();
        pythOracle = new PythOracleMarketHours(address(pyth), ETH_AAPLON, USD, PYTH_AAPL_USD_FEED, 60 seconds, 50);
        redstoneOracle = new RedstoneCoreOracle(
            ETH_AAPLON, USD, REDSTONE_AAPL_USD_FEED, REDSTONE_DEFAULT_FEED_DECIMALS, 5 minutes
        );
        anchoredOracle = new AnchoredOracle(address(pythOracle), address(redstoneOracle), 0.005e18);

        router = new EulerRouter(address(1), address(this));
        router.govSetConfig(ETH_AAPLON, USD, address(anchoredOracle));

        harness = new BasketManagerValidationLibHarness();
    }

    function test_validateOraclePath_allowsMag7PythRedstone() public view {
        harness.validateOraclePath(router, ETH_AAPLON);
    }
}
