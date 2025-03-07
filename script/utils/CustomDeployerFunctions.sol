// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { FarmingPlugin } from "@1inch/farming/contracts/FarmingPlugin.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { DefaultDeployerFunction, DeployOptions } from "forge-deploy/DefaultDeployerFunction.sol";
import { Deployer } from "forge-deploy/Deployer.sol";
import { Vm } from "forge-std/Vm.sol";

import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { CrossAdapter } from "euler-price-oracle/src/adapter/CrossAdapter.sol";
import { ChainlinkOracle } from "euler-price-oracle/src/adapter/chainlink/ChainlinkOracle.sol";
import { PythOracle } from "euler-price-oracle/src/adapter/pyth/PythOracle.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketManagerUtils } from "src/libraries/BasketManagerUtils.sol";
import { ERC20Mock } from "test/utils/mocks/ERC20Mock.sol";
// Artifact constants

string constant Artifact_PythOracle = "PythOracle.sol:PythOracle";
string constant Artifact_ChainlinkOracle = "ChainlinkOracle.sol:ChainlinkOracle";
string constant Artifact_CrossAdapter = "CrossAdapter.sol:CrossAdapter";
string constant Artifact_FarmingPlugin = "FarmingPlugin.sol:FarmingPlugin";
string constant Artifact_TimelockController = "TimelockController.sol:TimelockController";
string constant Artifact_ERC20Mock = "ERC20Mock.sol:ERC20Mock";
string constant Artifact_EulerRouter = "EulerRouter.sol:EulerRouter";
string constant Artifact_BasketManager = "BasketManager.sol:BasketManager";
string constant Artifact_BasketManagerUtils = "BasketManagerUtils.sol:BasketManagerUtils";

Vm constant vm = Vm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D));

/// @title CustomDeployerFunctions
/// @notice Custom deployer functions for contracts missing from forge-deploy generated code

library CustomDeployerFunctions {
    function deploy_PythOracle(
        Deployer deployer,
        string memory name,
        address pythOracle,
        address base,
        address quote,
        bytes32 feed,
        uint256 maxStaleness,
        uint256 maxConfWidth
    )
        internal
        returns (PythOracle)
    {
        bytes memory args = abi.encode(pythOracle, base, quote, feed, maxStaleness, maxConfWidth);
        return PythOracle(DefaultDeployerFunction.deploy(deployer, name, Artifact_PythOracle, args));
    }

    function deploy_PythOracle(
        Deployer deployer,
        string memory name,
        address pythOracle,
        address base,
        address quote,
        bytes32 feed,
        uint256 maxStaleness,
        uint256 maxConfWidth,
        DeployOptions memory options
    )
        internal
        returns (PythOracle)
    {
        bytes memory args = abi.encode(pythOracle, base, quote, feed, maxStaleness, maxConfWidth);
        return PythOracle(DefaultDeployerFunction.deploy(deployer, name, Artifact_PythOracle, args, options));
    }

    function deploy_ChainlinkOracle(
        Deployer deployer,
        string memory name,
        address base,
        address quote,
        address feed,
        uint256 maxStaleness
    )
        internal
        returns (ChainlinkOracle)
    {
        bytes memory args = abi.encode(base, quote, feed, maxStaleness);
        return ChainlinkOracle(DefaultDeployerFunction.deploy(deployer, name, Artifact_ChainlinkOracle, args));
    }

    function deploy_ChainlinkOracle(
        Deployer deployer,
        string memory name,
        address base,
        address quote,
        address feed,
        uint256 maxStaleness,
        DeployOptions memory options
    )
        internal
        returns (ChainlinkOracle)
    {
        bytes memory args = abi.encode(base, quote, feed, maxStaleness);
        return ChainlinkOracle(DefaultDeployerFunction.deploy(deployer, name, Artifact_ChainlinkOracle, args, options));
    }

    function deploy_CrossAdapter(
        Deployer deployer,
        string memory name,
        address base,
        address cross,
        address quote,
        address oracleBaseCross,
        address oracleCrossQuote
    )
        internal
        returns (CrossAdapter)
    {
        bytes memory args = abi.encode(base, cross, quote, oracleBaseCross, oracleCrossQuote);
        return CrossAdapter(DefaultDeployerFunction.deploy(deployer, name, Artifact_CrossAdapter, args));
    }

    function deploy_CrossAdapter(
        Deployer deployer,
        string memory name,
        address base,
        address cross,
        address quote,
        address oracleBaseCross,
        address oracleCrossQuote,
        DeployOptions memory options
    )
        internal
        returns (CrossAdapter)
    {
        bytes memory args = abi.encode(base, cross, quote, oracleBaseCross, oracleCrossQuote);
        return CrossAdapter(DefaultDeployerFunction.deploy(deployer, name, Artifact_CrossAdapter, args, options));
    }

    function deploy_FarmingPlugin(
        Deployer deployer,
        string memory name,
        address farmableToken,
        address rewardsToken,
        address owner
    )
        internal
        returns (FarmingPlugin)
    {
        bytes memory args = abi.encode(farmableToken, rewardsToken, owner);
        return FarmingPlugin(DefaultDeployerFunction.deploy(deployer, name, Artifact_FarmingPlugin, args));
    }

    function deploy_FarmingPlugin(
        Deployer deployer,
        string memory name,
        address farmableToken,
        address rewardsToken,
        address owner,
        DeployOptions memory options
    )
        internal
        returns (FarmingPlugin)
    {
        bytes memory args = abi.encode(farmableToken, rewardsToken, owner);
        return FarmingPlugin(DefaultDeployerFunction.deploy(deployer, name, Artifact_FarmingPlugin, args, options));
    }

    function deploy_TimelockController(
        Deployer deployer,
        string memory name,
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    )
        internal
        returns (TimelockController)
    {
        bytes memory args = abi.encode(minDelay, proposers, executors, admin);
        return TimelockController(DefaultDeployerFunction.deploy(deployer, name, Artifact_TimelockController, args));
    }

    function deploy_TimelockController(
        Deployer deployer,
        string memory name,
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin,
        DeployOptions memory options
    )
        internal
        returns (TimelockController)
    {
        bytes memory args = abi.encode(minDelay, proposers, executors, admin);
        return TimelockController(
            DefaultDeployerFunction.deploy(deployer, name, Artifact_TimelockController, args, options)
        );
    }

    function deploy_ERC20Mock(Deployer deployer, string memory name) internal returns (ERC20Mock) {
        bytes memory args = abi.encode();
        return ERC20Mock(DefaultDeployerFunction.deploy(deployer, name, Artifact_ERC20Mock, args));
    }

    function deploy_ERC20Mock(
        Deployer deployer,
        string memory name,
        DeployOptions memory options
    )
        internal
        returns (ERC20Mock)
    {
        bytes memory args = abi.encode();
        return ERC20Mock(DefaultDeployerFunction.deploy(deployer, name, Artifact_ERC20Mock, args, options));
    }

    function deploy_EulerRouter(
        Deployer deployer,
        string memory name,
        address evc,
        address governor
    )
        internal
        returns (EulerRouter)
    {
        bytes memory args = abi.encode(evc, governor);
        return EulerRouter(DefaultDeployerFunction.deploy(deployer, name, Artifact_EulerRouter, args));
    }

    function deploy_EulerRouter(
        Deployer deployer,
        string memory name,
        address evc,
        address governor,
        DeployOptions memory options
    )
        internal
        returns (EulerRouter)
    {
        bytes memory args = abi.encode(evc, governor);
        return EulerRouter(DefaultDeployerFunction.deploy(deployer, name, Artifact_EulerRouter, args, options));
    }

    function deploy_BasketManager_Custom(
        Deployer deployer,
        string memory name,
        string memory basketManagerUtilsName,
        address basketTokenImplementation,
        address eulerRouter,
        address strategyRegistry,
        address assetRegistry,
        address admin,
        address feeCollector
    )
        internal
        returns (BasketManager bm)
    {
        address bmAddress = deployer.getAddress(name);
        if (bmAddress != address(0)) {
            return BasketManager(bmAddress);
        }
        if (deployer.autoBroadcasting()) {
            vm.broadcast();
        }
        bm = new BasketManager(
            basketTokenImplementation, eulerRouter, strategyRegistry, assetRegistry, admin, feeCollector
        );
        // Replace with main contract artifact manually after deployment
        deployer.save(name, address(bm), Artifact_BasketManagerUtils);
        if (deployer.getAddress(basketManagerUtilsName) == address(0)) {
            deployer.save(basketManagerUtilsName, address(BasketManagerUtils), Artifact_BasketManagerUtils);
        }
        return bm;
    }
}
