// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";

import { Mag7DeploymentUtils } from "script/utils/Mag7DeploymentUtils.sol";
import { Constants } from "test/utils/Constants.t.sol";

contract Mag7DeploymentUtilsHarness is Mag7DeploymentUtils {
    function isPythOnly(address asset) external pure returns (bool) {
        return isPythOnlyAsset(asset);
    }
}

contract Mag7DeploymentUtilsTest is Test, Constants {
    Mag7DeploymentUtilsHarness internal harness;

    function setUp() public {
        harness = new Mag7DeploymentUtilsHarness();
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
}
