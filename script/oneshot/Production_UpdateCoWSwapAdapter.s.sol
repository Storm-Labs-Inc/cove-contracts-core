// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { UpdateCoWSwapAdapterBase } from "./UpdateCoWSwapAdapterBase.s.sol";

/// @title Production_UpdateCoWSwapAdapter
/// @notice Deploys and updates the CoWSwap adapter with the new appData hash for ETH production.
contract ProductionUpdateCoWSwapAdapter is UpdateCoWSwapAdapterBase {
    function _safe() internal view override returns (address) {
        return COVE_COMMUNITY_MULTISIG;
    }

    function _buildPrefix() internal pure override returns (string memory) {
        return "Production_";
    }

    function _appDataHash() internal view override returns (bytes32) {
        return PRODUCTION_COWSWAP_APPDATA_HASH;
    }
}
