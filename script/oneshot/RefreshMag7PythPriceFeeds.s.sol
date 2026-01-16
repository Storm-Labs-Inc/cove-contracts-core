// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Surl } from "dependencies/forge-safe-1/lib/surl/src/Surl.sol";
import { DeployScript } from "forge-deploy/DeployScript.sol";
import { stdJson } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { IPyth } from "src/interfaces/deps/IPyth.sol";
import { Constants } from "test/utils/Constants.t.sol";

// solhint-disable var-name-mixedcase
contract RefreshMag7PythPriceFeeds is DeployScript, Constants {
    using stdJson for string;
    using Surl for string;

    string internal constant _HERMES_BASE_URL = "https://hermes.pyth.network";
    string internal constant _HERMES_LATEST_PATH = "/v2/updates/price/latest";
    string internal constant _HERMES_QUERY = "encoding=hex&parsed=false";

    function deploy() public {
        bytes32[] memory feeds = _mag7PythFeeds();
        string memory url = _buildHermesUrl(feeds);

        console.log("Hermes URL:", url);
        (uint256 status, bytes memory data) = url.get();
        require(status == 200, "Hermes request failed");

        string memory json = string(data);
        string[] memory updateHex = json.readStringArray(".binary.data");
        require(updateHex.length > 0, "No update data");

        bytes[] memory updateData = new bytes[](updateHex.length);
        for (uint256 i = 0; i < updateHex.length; i++) {
            updateData[i] = vm.parseBytes(string.concat("0x", updateHex[i]));
        }

        uint256 fee = IPyth(PYTH).getUpdateFee(updateData);
        console.log("Update data count:", updateData.length);
        console.log("Update fee (wei):", fee);

        vm.broadcast();
        IPyth(PYTH).updatePriceFeeds{ value: fee }(updateData);
    }

    function _buildHermesUrl(bytes32[] memory feeds) internal pure returns (string memory) {
        string memory url = string.concat(_HERMES_BASE_URL, _HERMES_LATEST_PATH, "?", _HERMES_QUERY);
        for (uint256 i = 0; i < feeds.length; i++) {
            url = string.concat(url, "&ids[]=", Strings.toHexString(uint256(feeds[i]), 32));
        }
        return url;
    }

    function _mag7PythFeeds() internal pure returns (bytes32[] memory feeds) {
        feeds = new bytes32[](7);
        feeds[0] = PYTH_AAPL_USD_FEED;
        feeds[1] = PYTH_MSFT_USD_FEED;
        feeds[2] = PYTH_GOOGL_USD_FEED;
        feeds[3] = PYTH_AMZN_USD_FEED;
        feeds[4] = PYTH_NVDA_USD_FEED;
        feeds[5] = PYTH_META_USD_FEED;
        feeds[6] = PYTH_TSLA_USD_FEED;
    }
}
