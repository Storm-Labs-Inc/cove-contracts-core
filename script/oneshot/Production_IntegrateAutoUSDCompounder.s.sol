// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { AutoUSDCompounderIntegrationBase } from "./AutoUSDCompounderIntegrationBase.s.sol";

contract ProductionIntegrateAutoUSDCompounder is AutoUSDCompounderIntegrationBase {
    function deploy() public {
        integrate();
    }

    function _buildPrefix() internal view override returns (string memory) {
        return "Production_";
    }

    function _keeperAccount() internal view override returns (address) {
        return PRODUCTION_COVE_SILVERBACK_AWS_ACCOUNT;
    }

    function _opsMultisig() internal view override returns (address) {
        return COVE_OPS_MULTISIG;
    }

    function _basketTokenRegistryKey() internal view override returns (bytes32) {
        return "BasketToken_USD";
    }

    function _basketTokenLocalLabel() internal view override returns (string memory) {
        return "USD";
    }
}
