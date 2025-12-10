// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { UpdateCoWSwapAdapterV3Base } from "./UpdateCoWSwapAdapterV3Base.s.sol";

/// @title BaseStaging_UpdateCoWSwapAdapterV3
/// @notice Deploys and updates the CoWSwap adapter with the new appData hash and GPv2 domain separator for Base
/// staging.
// Commands (Base staging):
// # 1. Deploy a new instance of CoWSwapAdapter that points to the new CowSwapClone on Base
// forge script script/oneshot/BaseStaging_UpdateCoWSwapAdapterV3.s.sol:BaseStaging_UpdateCoWSwapAdapterV3 --rpc-url
// $BASE_RPC_URL --broadcast -vvvv --account deployer && ./forge-deploy sync
// # 2. Test the Safe batch for a timelock transaction for updating the cowswap adapter (add --broadcast for actually
// queueing up)
// forge script script/oneshot/BaseStaging_UpdateCoWSwapAdapterV3.s.sol:BaseStaging_UpdateCoWSwapAdapterV3 --sig
// "scheduleTimelock()" --rpc-url $BASE_RPC_URL -vvvv --account deployer
// # 3. Execute the queued timelock (add --broadcast for actually executing)
// forge script script/oneshot/BaseStaging_UpdateCoWSwapAdapterV3.s.sol:BaseStaging_UpdateCoWSwapAdapterV3 --sig
// "executeTimelock()" --rpc-url $BASE_RPC_URL -vvvv --account deployer
contract BaseStagingUpdateCoWSwapAdapterV3 is UpdateCoWSwapAdapterV3Base {
    bytes32 internal constant _BASE_STAGING_COW_DOMAIN_SEPARATOR =
        0xd72ffa789b6fae41254d0b5a13e6e1e92ed947ec6a251edf1cf0b6c02c257b4b;

    function _safe() internal view override returns (address) {
        return BASE_STAGING_COMMUNITY_MULTISIG;
    }

    function _buildPrefix() internal pure override returns (string memory) {
        return "Staging_";
    }

    function _appDataHash() internal view override returns (bytes32) {
        return BASE_STAGING_COWSWAP_APPDATA_HASH;
    }

    function _cowSettlementDomainSeparator() internal view override returns (bytes32) {
        return _BASE_STAGING_COW_DOMAIN_SEPARATOR;
    }
}
