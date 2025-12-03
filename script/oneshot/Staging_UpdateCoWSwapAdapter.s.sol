// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { UpdateCoWSwapAdapterBase } from "./UpdateCoWSwapAdapterBase.s.sol";

/// @title Staging_UpdateCoWSwapAdapter
/// @notice Deploys and updates the CoWSwap adapter with the new appData hash for ETH staging.
contract StagingUpdateCoWSwapAdapter is UpdateCoWSwapAdapterBase {
    function _safe() internal view override returns (address) {
        return COVE_STAGING_COMMUNITY_MULTISIG;
    }

    function _buildPrefix() internal pure override returns (string memory) {
        return "Staging_";
    }

    function _appDataHash() internal view override returns (bytes32) {
        return STAGING_COWSWAP_APPDATA_HASH;
    }
}
