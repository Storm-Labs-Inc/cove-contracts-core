// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";

import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";
import { Constants } from "test/utils/Constants.t.sol";

/**
 * @title Production_SetDYfiRedeemer
 * @notice Updates all Yearn gauge strategies deployed through CoveYearnGaugeFactory to use the new dYFI redeemer.
 *         For now, the new redeemer address is set to the zero address as a placeholder.
 */
// solhint-disable var-name-mixedcase
contract SetDYfiRedeemer is DeployScript, Constants, BatchScript, BuildDeploymentJsonNames {
    using DeployerFunctions for Deployer;

    // ------------------------------------------------------------------
    // Constants / Config
    // ------------------------------------------------------------------

    /// @notice Safe that will execute the batch (Community multisig in production).
    address public constant safe = COVE_COMMUNITY_MULTISIG;

    /// @notice Placeholder for the new dYFI redeemer address; will be updated in a follow-up transaction.
    address public constant NEW_DYFI_REDEEMER = address(0);

    // ------------------------------------------------------------------
    // Interfaces
    // ------------------------------------------------------------------

    /// @dev Minimal interface for the Yearn gauge strategy.
    interface IYearnGaugeStrategy {
        function setDYfiRedeemer(address newDYfiRedeemer) external;
    }

    /// @dev Minimal interface for the CoveYearnGaugeFactory needed by this script.
    interface ICoveYearnGaugeFactory {
        struct GaugeInfo {
            address yearnVaultAsset;
            address yearnVault;
            bool isVaultV2;
            address yearnGauge;
            address coveYearnStrategy;
            address autoCompoundingGauge;
            address nonAutoCompoundingGauge;
        }

        function numOfSupportedYearnGauges() external view returns (uint256);

        function getAllGaugeInfo(uint256 limit, uint256 offset) external view returns (GaugeInfo[] memory);
    }

    // ------------------------------------------------------------------
    // DeployScript overrides
    // ------------------------------------------------------------------

    /// @inheritdoc BuildDeploymentJsonNames
    function _buildPrefix() internal pure override returns (string memory) {
        return "Production_";
    }

    /// @notice Entry point called by `DeployScript.run()`.
    function deploy() public isBatch(safe) {
        // Allow foundry to auto-broadcast transactions produced by this script.
        deployer.setAutoBroadcast(true);

        // Resolve the address of the factory from previous deployments.
        address factoryAddr = deployer.getAddress(buildCoveYearnGaugeFactoryName());
        require(factoryAddr != address(0), "Factory not found in deployments");

        ICoveYearnGaugeFactory factory = ICoveYearnGaugeFactory(factoryAddr);

        // Retrieve all gauge infos in one call.
        uint256 total = factory.numOfSupportedYearnGauges();
        ICoveYearnGaugeFactory.GaugeInfo[] memory infos = factory.getAllGaugeInfo(total, 0);

        // Prepare batched txns: set the dYFI redeemer for every strategy.
        for (uint256 i = 0; i < infos.length; i++) {
            address strategy = infos[i].coveYearnStrategy;
            if (strategy == address(0)) continue; // Skip if no strategy for some reason

            addToBatch(
                strategy,
                0,
                abi.encodeWithSelector(IYearnGaugeStrategy.setDYfiRedeemer.selector, NEW_DYFI_REDEEMER)
            );
        }

        // Execute the batch if there is at least one operation.
        if (encodedTxns.length > 0) {
            executeBatch(true);
        }
    }
}