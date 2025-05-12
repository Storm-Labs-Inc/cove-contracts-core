// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { IMasterRegistry } from "src/interfaces/IMasterRegistry.sol";
import { Constants } from "test/utils/Constants.t.sol";

contract UpdateRegistryNames is DeployScript, Constants, StdAssertions {
    using DeployerFunctions for Deployer;

    IMasterRegistry public masterRegistry;
    IMasterRegistry public stagingMasterRegistry;
    bool public shouldBroadcast;

    // Called from DeployScript's run() function
    function deploy() public virtual {
        deploy(true);
    }

    function deploy(bool shouldBroadcast_) public {
        shouldBroadcast = shouldBroadcast_;

        // Only allow COVE_DEPLOYER to update in production
        require(msg.sender == COVE_DEPLOYER_ADDRESS, "Caller must be COVE DEPLOYER");

        masterRegistry = IMasterRegistry(COVE_MASTER_REGISTRY);
        stagingMasterRegistry = IMasterRegistry(COVE_STAGING_MASTER_REGISTRY);

        // Core contract names that need to be updated
        string[] memory registryNames = new string[](7);
        registryNames[0] = "AssetRegistry";
        registryNames[1] = "StrategyRegistry";
        registryNames[2] = "EulerRouter";
        registryNames[3] = "BasketManager";
        registryNames[4] = "FeeCollector";
        registryNames[5] = "CowSwapAdapter";
        registryNames[6] = "Staging_Stables_FarmingPlugin";

        // Update names in master registry
        _updateRegistryNames(registryNames);
    }

    function _getDeadAddress(uint256 index) private pure returns (address) {
        // Create a unique dead address for each registry by incorporating the index
        // Each address will be 0xDEADBEEF0000...{index}
        require(index < 16, "Index too large"); // Ensure index fits in last digit
        bytes20 base = bytes20(hex"DEADBEEF000000000000000000000000000000");
        return address(uint160(bytes20(base)) + uint160(index));
    }

    function _updateRegistryNames(string[] memory registryNames) private {
        // First update old names in master registry to point to dead addresses
        bytes[] memory masterRegistryCalls = new bytes[](registryNames.length);
        bytes[] memory stagingRegistryCalls = new bytes[](registryNames.length);
        for (uint256 i = 0; i < registryNames.length; i++) {
            bytes32 nameBytes = bytes32(bytes(registryNames[i]));

            // Update old name to point to dead address in master registry
            masterRegistryCalls[i] =
                abi.encodeWithSelector(IMasterRegistry.updateRegistry.selector, nameBytes, _getDeadAddress(i));
            address registryAddress;
            if (i == registryNames.length - 1) {
                registryAddress = deployer.getAddress(registryNames[i]);
            } else {
                registryAddress = deployer.getAddress(string.concat("Staging_", registryNames[i]));
            }
            require(registryAddress != address(0), "Registry address not found");
            // Add new entry to staging registry
            stagingRegistryCalls[i] =
                abi.encodeWithSelector(IMasterRegistry.addRegistry.selector, nameBytes, registryAddress);
        }

        if (shouldBroadcast) {
            vm.startBroadcast();
        }
        Multicall(address(masterRegistry)).multicall(masterRegistryCalls);
        Multicall(address(stagingMasterRegistry)).multicall(stagingRegistryCalls);
        if (shouldBroadcast) {
            vm.stopBroadcast();
        }
    }
}
