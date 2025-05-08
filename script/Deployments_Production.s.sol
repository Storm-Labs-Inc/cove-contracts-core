// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { Deployments } from "./Deployments.s.sol";
import { CustomDeployerFunctions } from "./utils/CustomDeployerFunctions.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";

contract DeploymentsProduction is Deployments {
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
        rewardToken = ETH_COVE;
    }

    function _feeCollectorSalt() internal pure override returns (bytes32) {
        return keccak256(abi.encodePacked("Production_FeeCollector"));
    }

    // solhint-disable-next-line no-empty-blocks
    function _deployNonCoreContracts() internal override { }
}
