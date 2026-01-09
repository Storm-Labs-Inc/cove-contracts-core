// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { UpdateCoveUSDFeeSplitBase } from "./UpdateCoveUSDFeeSplitBase.s.sol";

/// @title Production_UpdateCoveUSDFeeSplit
/// @notice Updates coveUSD fee split for ETH production via community multisig.
contract ProductionUpdateCoveUSDFeeSplit is UpdateCoveUSDFeeSplitBase {
    function _safe() internal view override returns (address) {
        return COVE_COMMUNITY_MULTISIG;
    }
}
