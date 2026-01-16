// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";

import { PythStructs } from "@pyth/PythStructs.sol";
import { RedstoneCoreOracle } from "euler-price-oracle/src/adapter/redstone/RedstoneCoreOracle.sol";
import { Mag7DeploymentUtils } from "script/utils/Mag7DeploymentUtils.sol";
import { AnchoredOracle } from "src/oracles/AnchoredOracle.sol";
import { PythOracleMarketHours } from "src/oracles/PythOracleMarketHours.sol";
import { Constants } from "test/utils/Constants.t.sol";

contract StubPythMag7Deploy {
    function getPriceUnsafe(bytes32) external pure returns (PythStructs.Price memory) {
        return PythStructs.Price({ price: 0, conf: 0, expo: 0, publishTime: 0 });
    }
}

contract Mag7DeploymentUtilsHarness is Mag7DeploymentUtils {
    function isPythOnly(address asset) external pure returns (bool) {
        return _isPythOnlyAsset(asset);
    }

    function assertPythConfig(
        address oracle,
        address base,
        address quote,
        bytes32 feedId,
        uint256 maxStaleness,
        uint256 maxConfWidth
    )
        external
        view
    {
        _assertPythOracleMarketHoursConfig(oracle, base, quote, feedId, maxStaleness, maxConfWidth);
    }

    function assertRedstoneConfig(
        address oracle,
        address base,
        address quote,
        bytes32 feedId,
        uint8 feedDecimals,
        uint256 maxStaleness
    )
        external
        view
    {
        _assertRedstoneCoreOracleConfig(oracle, base, quote, feedId, feedDecimals, maxStaleness);
    }

    function assertAnchoredConfig(
        address oracle,
        address primary,
        address anchor,
        uint256 maxDivergence
    )
        external
        view
    {
        _assertAnchoredOracleConfig(oracle, primary, anchor, maxDivergence);
    }
}

contract Mag7DeploymentUtilsTest is Test, Constants {
    Mag7DeploymentUtilsHarness internal harness;
    StubPythMag7Deploy internal pyth;

    function setUp() public {
        harness = new Mag7DeploymentUtilsHarness();
        pyth = new StubPythMag7Deploy();
    }

    function test_isPythOnlyAsset_trueForAaplAndMsft() public view {
        assertTrue(harness.isPythOnly(ETH_AAPLON));
        assertTrue(harness.isPythOnly(ETH_MSFTON));
    }

    function test_isPythOnlyAsset_falseForOtherMag7() public view {
        assertFalse(harness.isPythOnly(ETH_GOOGLON));
        assertFalse(harness.isPythOnly(ETH_AMZNON));
        assertFalse(harness.isPythOnly(ETH_NVDAON));
        assertFalse(harness.isPythOnly(ETH_METAON));
        assertFalse(harness.isPythOnly(ETH_TSLAON));
    }

    function test_assertOracleConfigs_passesForMag7() public {
        PythOracleMarketHours pythOracle =
            new PythOracleMarketHours(address(pyth), ETH_GOOGLON, USD, PYTH_GOOGL_USD_FEED, 60 seconds, 50);
        RedstoneCoreOracle redstoneOracle = new RedstoneCoreOracle(
            ETH_GOOGLON, USD, REDSTONE_GOOGL_USD_FEED, REDSTONE_DEFAULT_FEED_DECIMALS, 5 minutes
        );
        AnchoredOracle anchoredOracle = new AnchoredOracle(address(pythOracle), address(redstoneOracle), 0.005e18);

        harness.assertPythConfig(address(pythOracle), ETH_GOOGLON, USD, PYTH_GOOGL_USD_FEED, 60 seconds, 50);
        harness.assertRedstoneConfig(
            address(redstoneOracle),
            ETH_GOOGLON,
            USD,
            REDSTONE_GOOGL_USD_FEED,
            REDSTONE_DEFAULT_FEED_DECIMALS,
            5 minutes
        );
        harness.assertAnchoredConfig(address(anchoredOracle), address(pythOracle), address(redstoneOracle), 0.005e18);
    }
}
