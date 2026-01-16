// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Test } from "forge-std/Test.sol";

import { RefreshMag7PythPriceFeeds } from "script/oneshot/RefreshMag7PythPriceFeeds.s.sol";

contract RefreshMag7PythPriceFeedsHarness is RefreshMag7PythPriceFeeds {
    function exposedBuildHermesUrl(bytes32[] memory feeds) external pure returns (string memory) {
        return _buildHermesUrl(feeds);
    }

    function exposedMag7PythFeeds() external pure returns (bytes32[] memory feeds) {
        return _mag7PythFeeds();
    }
}

contract RefreshMag7PythPriceFeedsTest is Test {
    function test_buildHermesUrl_containsParamsAndFeeds() public {
        RefreshMag7PythPriceFeedsHarness harness = new RefreshMag7PythPriceFeedsHarness();
        bytes32[] memory feeds = harness.exposedMag7PythFeeds();
        string memory url = harness.exposedBuildHermesUrl(feeds);

        assertTrue(_contains(url, "encoding=hex"));
        assertTrue(_contains(url, "parsed=false"));

        for (uint256 i = 0; i < feeds.length; i++) {
            string memory feedHex = Strings.toHexString(uint256(feeds[i]), 32);
            assertTrue(_contains(url, feedHex));
        }
    }

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        return vm.indexOf(haystack, needle) != type(uint256).max;
    }
}
