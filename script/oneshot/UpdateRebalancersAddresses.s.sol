// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";

import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";
import { CustomDeployerFunctions } from "script/utils/CustomDeployerFunctions.sol";

import { BasketManager } from "src/BasketManager.sol";
import { Constants } from "test/utils/Constants.t.sol";

/**
 * @title UpdateRebalancersAddresses
 * @notice Script to update the rebalancers addresses in the staging environment
 */
contract UpdateRebalancersAddresses is DeployScript, Constants, StdAssertions, BuildDeploymentJsonNames {
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    // Staging EulerRouter address
    address public constant STAGING_EULER_ROUTER = 0xb96e038998049BA86c220Dda4048AC17E1109453;

    // Oracle configuration parameters
    uint256 public constant PYTH_MAX_STALENESS = 30 seconds;
    uint256 public constant PYTH_MAX_CONF_WIDTH = 50; // 0.5%
    uint256 public constant CHAINLINK_MAX_STALENESS = 1 days;
    uint256 public constant MAX_DIVERGENCE = 0.005e18; // 0.5%

    address public governor;

    address public safe = COVE_STAGING_COMMUNITY_MULTISIG;

    function _buildPrefix() internal view override returns (string memory) {
        return "Staging_";
    }

    function deploy() public {
        deployer.setAutoBroadcast(true);

        address basketManager = deployer.getAddress(buildBasketManagerName());

        vm.startBroadcast(COVE_STAGING_COMMUNITY_MULTISIG);

        BasketManager(basketManager).grantRole(REBALANCE_PROPOSER_ROLE, STAGING_COVE_SILVERBACK_AWS_ACCOUNT);
        BasketManager(basketManager).grantRole(TOKENSWAP_PROPOSER_ROLE, STAGING_COVE_SILVERBACK_AWS_ACCOUNT);
        BasketManager(basketManager).grantRole(TOKENSWAP_EXECUTOR_ROLE, STAGING_COVE_SILVERBACK_AWS_ACCOUNT);
        BasketManager(basketManager).revokeRole(REBALANCE_PROPOSER_ROLE, BOOSTIES_SILVERBACK_AWS_ACCOUNT);
        BasketManager(basketManager).revokeRole(TOKENSWAP_PROPOSER_ROLE, BOOSTIES_SILVERBACK_AWS_ACCOUNT);
        BasketManager(basketManager).revokeRole(TOKENSWAP_EXECUTOR_ROLE, BOOSTIES_SILVERBACK_AWS_ACCOUNT);

        vm.stopBroadcast();

        // executeBatch(false);
    }
}
