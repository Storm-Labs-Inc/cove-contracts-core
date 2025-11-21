// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { console2 } from "forge-std/console2.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";

import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";
import { BasketManager } from "src/BasketManager.sol";
import { Constants } from "test/utils/Constants.t.sol";

/// @title Staging_ReplaceCoWSwapAdapter
/// @notice Queues a timelock transaction (via Safe batch) to replace the CoWSwap adapter on ETH staging.
contract StagingReplaceCoWSwapAdapter is DeployScript, Constants, BatchScript, BuildDeploymentJsonNames {
    using DeployerFunctions for Deployer;

    address public constant SAFE = COVE_STAGING_COMMUNITY_MULTISIG;

    string internal constant _NEW_ADAPTER_SUFFIX = "CowSwapAdapter_AppDataV1";

    function _buildPrefix() internal pure override returns (string memory) {
        return "Staging_";
    }

    function deploy() public isBatch(SAFE) {
        deployer.setAutoBroadcast(true);

        address timelock = deployer.getAddress(buildTimelockControllerName());
        address basketManager = deployer.getAddress(buildBasketManagerName());
        address newAdapter = deployer.getAddress(string.concat(_buildPrefix(), _NEW_ADAPTER_SUFFIX));
        if (newAdapter == address(0)) {
            revert("New adapter deployment not found");
        }

        uint256 delay = TimelockController(payable(timelock)).getMinDelay();
        bytes memory calldata_ = abi.encodeWithSelector(BasketManager.setTokenSwapAdapter.selector, newAdapter);

        addToBatch(
            timelock,
            0,
            abi.encodeWithSelector(
                TimelockController.schedule.selector, basketManager, 0, calldata_, bytes32(0), bytes32(0), delay
            )
        );

        console2.log("Queue setTokenSwapAdapter via timelock");
        console2.log("Timelock:", timelock);
        console2.log("BasketManager:", basketManager);
        console2.log("New adapter:", newAdapter);
        console2.log("Delay (s):", delay);

        if (encodedTxns.length > 0) {
            executeBatch(true);
        }
    }

    function executeTimelock() public {
        address timelock = deployer.getAddress(buildTimelockControllerName());
        address basketManager = deployer.getAddress(buildBasketManagerName());
        address newAdapter = deployer.getAddress(string.concat(_buildPrefix(), _NEW_ADAPTER_SUFFIX));
        if (newAdapter == address(0)) {
            revert("New adapter deployment not found");
        }

        bytes memory data = abi.encodeWithSelector(BasketManager.setTokenSwapAdapter.selector, newAdapter);
        vm.broadcast();
        TimelockController(payable(timelock)).execute(basketManager, 0, data, bytes32(0), bytes32(0));
    }
}
