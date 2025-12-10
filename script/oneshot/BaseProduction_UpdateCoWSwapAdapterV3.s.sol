// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { UpdateCoWSwapAdapterV3Base } from "./UpdateCoWSwapAdapterV3Base.s.sol";

/// @title BaseProduction_UpdateCoWSwapAdapterV3
/// @notice Deploys and updates the CoWSwap adapter with the new appData hash and GPv2 domain separator for Base
/// production.
contract BaseProductionUpdateCoWSwapAdapterV3 is UpdateCoWSwapAdapterV3Base {
    bytes32 internal constant _BASE_PROD_COW_DOMAIN_SEPARATOR =
        0xd72ffa789b6fae41254d0b5a13e6e1e92ed947ec6a251edf1cf0b6c02c257b4b;

    function _safe() internal view override returns (address) {
        return BASE_COMMUNITY_MULTISIG;
    }

    function _buildPrefix() internal pure override returns (string memory) {
        return "Production_";
    }

    function _appDataHash() internal view override returns (bytes32) {
        return BASE_PRODUCTION_COWSWAP_APPDATA_HASH;
    }

    function _cowSettlementDomainSeparator() internal view override returns (bytes32) {
        return _BASE_PROD_COW_DOMAIN_SEPARATOR;
    }
}
