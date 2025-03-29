// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { Deployments } from "./Deployments.s.sol";
import { CustomDeployerFunctions } from "./utils/CustomDeployerFunctions.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";

// solhint-disable contract-name-camelcase
contract Deployments_Staging is Deployments {
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    function _buildPrefix() internal pure override returns (string memory) {
        return "Production_";
    }

    function _setPermissionedAddresses() internal virtual override {
        // Production deploy
        // TODO: confirm addresses for production
        admin = COVE_COMMUNITY_MULTISIG;
        treasury = COVE_COMMUNITY_MULTISIG;
        pauser = COVE_DEPLOYER_ADDRESS;
        manager = COVE_OPS_MULTISIG;
        timelock = getAddressOrRevert(buildTimelockControllerName());
        rebalanceProposer = BOOSTIES_SILVERBACK_AWS_ACCOUNT;
        tokenSwapProposer = BOOSTIES_SILVERBACK_AWS_ACCOUNT;
        tokenSwapExecutor = BOOSTIES_SILVERBACK_AWS_ACCOUNT;
    }

    function _feeCollectorSalt() internal pure override returns (bytes32) {
        return keccak256(abi.encodePacked("Production_FeeCollector"));
    }

    function _deployNonCoreContracts() internal override { }
}
