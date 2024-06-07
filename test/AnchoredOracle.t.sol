// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { BaseTest } from "./utils/BaseTest.t.sol";

import { console2 as console } from "forge-std/console2.sol";
import { AnchoredOracle } from "src/deps/AnchoredOracle.sol";

contract AnchoredOracleTest is BaseTest {
    function test_constructor() public {
        AnchoredOracle oracle = new AnchoredOracle(address(0), address(0), 0.002e18);
        console.log("oracle: %s", address(oracle));
    }
}
