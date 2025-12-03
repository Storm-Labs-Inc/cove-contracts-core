// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";

import { Constants } from "test/utils/Constants.t.sol";

/// @title AppDataHash Test
/// @notice Tests that the appdata JSON files hash to the expected values
contract AppDataHashTest is Test, Constants {
    string internal constant _APPDATA_BASE_PATH = "assets/appdata/";

    function test_ethStagingAppDataHash() public view {
        string memory json = vm.readFile(string.concat(_APPDATA_BASE_PATH, "eth-staging.json"));
        bytes32 actualHash = keccak256(bytes(json));
        assertEq(actualHash, STAGING_COWSWAP_APPDATA_HASH, "ETH staging appData hash mismatch");
    }

    function test_ethProductionAppDataHash() public view {
        string memory json = vm.readFile(string.concat(_APPDATA_BASE_PATH, "eth-production.json"));
        bytes32 actualHash = keccak256(bytes(json));
        assertEq(actualHash, PRODUCTION_COWSWAP_APPDATA_HASH, "ETH production appData hash mismatch");
    }

    function test_baseStagingAppDataHash() public view {
        string memory json = vm.readFile(string.concat(_APPDATA_BASE_PATH, "base-staging.json"));
        bytes32 actualHash = keccak256(bytes(json));
        assertEq(actualHash, BASE_STAGING_COWSWAP_APPDATA_HASH, "Base staging appData hash mismatch");
    }

    function test_baseProductionAppDataHash() public view {
        string memory json = vm.readFile(string.concat(_APPDATA_BASE_PATH, "base-production.json"));
        bytes32 actualHash = keccak256(bytes(json));
        assertEq(actualHash, BASE_PRODUCTION_COWSWAP_APPDATA_HASH, "Base production appData hash mismatch");
    }
}
