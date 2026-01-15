// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Constants } from "test/utils/Constants.t.sol";

abstract contract Mag7DeploymentUtils is Constants {
    function _isPythOnlyAsset(address asset) internal pure returns (bool) {
        return asset == ETH_AAPLON || asset == ETH_MSFTON;
    }
}
