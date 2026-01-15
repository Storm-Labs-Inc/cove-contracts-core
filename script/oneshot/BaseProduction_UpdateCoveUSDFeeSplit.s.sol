// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { UpdateCoveUSDFeeSplitBase } from "./UpdateCoveUSDFeeSplitBase.s.sol";

/// @title BaseProduction_UpdateCoveUSDFeeSplit
/// @notice Updates coveUSD fee split for Base production via community multisig.
contract BaseProductionUpdateCoveUSDFeeSplit is UpdateCoveUSDFeeSplitBase {
    function _safe() internal view override returns (address) {
        return BASE_COMMUNITY_MULTISIG;
    }
}
