// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { AutoUSDCompounderIntegrationBase } from "./AutoUSDCompounderIntegrationBase.s.sol";

contract StagingIntegrateAutoUSDCompounder is AutoUSDCompounderIntegrationBase {
    function deploy() public {
        integrate();
    }

    function _buildPrefix() internal view override returns (string memory) {
        return "Staging_";
    }

    function _keeperAccount() internal view override returns (address) {
        return STAGING_COVE_SILVERBACK_AWS_ACCOUNT;
    }

    function _opsMultisig() internal view override returns (address) {
        return COVE_STAGING_OPS_MULTISIG;
    }

    function _basketTokenRegistryKey() internal view override returns (bytes32) {
        return "BasketToken_Stables";
    }

    function _basketTokenLocalLabel() internal view override returns (string memory) {
        return "Stables";
    }
}
