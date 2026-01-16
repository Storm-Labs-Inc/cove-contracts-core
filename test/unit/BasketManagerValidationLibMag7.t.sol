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
    BasketManagerValidationLibHarness internal harness;

    function setUp() public {
        pyth = new StubPythMag7();
        harness = new BasketManagerValidationLibHarness();
    }

    function _setupAnchoredOracle(address asset, bytes32 pythFeed, bytes32 redstoneFeed)
        internal
        returns (EulerRouter)
    {
        PythOracleMarketHours pythOracle =
            new PythOracleMarketHours(address(pyth), asset, USD, pythFeed, 60 seconds, 50);
        RedstoneCoreOracle redstoneOracle =
            new RedstoneCoreOracle(asset, USD, redstoneFeed, REDSTONE_DEFAULT_FEED_DECIMALS, 5 minutes);
        AnchoredOracle anchoredOracle = new AnchoredOracle(address(pythOracle), address(redstoneOracle), 0.005e18);
        EulerRouter router = new EulerRouter(address(1), address(this));
        router.govSetConfig(asset, USD, address(anchoredOracle));
        return router;
    }

    function _setupPythOnlyOracle(address asset, bytes32 pythFeed) internal returns (EulerRouter) {
        PythOracleMarketHours pythOracle =
            new PythOracleMarketHours(address(pyth), asset, USD, pythFeed, 60 seconds, 50);
        EulerRouter router = new EulerRouter(address(1), address(this));
        router.govSetConfig(asset, USD, address(pythOracle));
        return router;
    }

    function test_validateOraclePath_allowsMag7PythRedstone() public {
        EulerRouter router = _setupAnchoredOracle(ETH_GOOGLON, PYTH_GOOGL_USD_FEED, REDSTONE_GOOGL_USD_FEED);
        harness.validateOraclePath(router, ETH_GOOGLON);
    }

    function test_validateOraclePath_allowsMag7PythOnly() public {
        EulerRouter router = _setupPythOnlyOracle(ETH_AAPLON, PYTH_AAPL_USD_FEED);
        harness.validateOraclePath(router, ETH_AAPLON);
    }
}
