// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

// import { CREATE3Factory } from "create3-factory/src/CREATE3Factory.sol";

import { CREATE3Factory } from "create3-factory/src/CREATE3Factory.sol";

import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { ChainlinkOracle } from "euler-price-oracle/src/adapter/chainlink/ChainlinkOracle.sol";
import { PythOracle } from "euler-price-oracle/src/adapter/pyth/PythOracle.sol";
import { DeployScript } from "forge-deploy/DeployScript.sol";
import { console } from "forge-std/console.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { FeeCollector } from "src/FeeCollector.sol";
import { Constants } from "test/utils/Constants.t.sol";

import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";

contract Deployments is DeployScript, Constants {
    using DeployerFunctions for Deployer;

    address public admin;
    address public treasury;
    address public pauser;
    address public manager;
    address public timelock;
    address public rebalancer;
    address public basketTokenImplementation;

    function deploy(bool isProduction) public {
        require(msg.sender == COVE_DEPLOYER_ADDRESS, "Must use COVE DEPLOYER");
        admin = COVE_OPS_MULTISIG;
        treasury = COVE_OPS_MULTISIG;
        pauser = COVE_OPS_MULTISIG;
        manager = COVE_OPS_MULTISIG;
        timelock = COVE_OPS_MULTISIG;
        rebalancer = COVE_OPS_MULTISIG;

        deployer.setAutoBroadcast(isProduction);

        // Registries and EulerRouter
        address(deployer.deploy_AssetRegistry("AssetRegistry", admin));
        address(deployer.deploy_StrategyRegistry("StrategyRegistry", admin));
        basketTokenImplementation = address(deployer.deploy_BasketToken("BasketTokenImplementation"));
        _deployEulerRouter();
        // BasketManager
        bytes32 feeCollectorSalt = keccak256(abi.encodePacked("FeeCollector"));
        _deployBasketManager(feeCollectorSalt);
        // FeeCollector
        _deployFeeCollector(feeCollectorSalt);
        if (!isProduction) {
            vm.startPrank(COVE_DEPLOYER_ADDRESS);
        }
        _setupPermissions();
    }

    modifier deployIfMissing(string memory name) {
        if (checkDeployment(name) != address(0)) {
            return;
        }
        _;
    }

    // Deploys basket manager given a fee collector salt which must be used to deploy the fee collector using CREATE3.
    // Caller must be admin
    function _deployBasketManager(bytes32 feeCollectorSalt) internal deployIfMissing("BasketManager") {
        CREATE3Factory factory = CREATE3Factory(CREATE3_FACTORY);
        // Determine feeCollector deployment address
        address feeCollectorAddress = factory.getDeployed(COVE_DEPLOYER_ADDRESS, feeCollectorSalt);
        address(
            deployer.deploy_BasketManager(
                "BasketManager",
                basketTokenImplementation,
                deployer.getAddress("EulerRouter"),
                deployer.getAddress("StrategyRegistry"),
                deployer.getAddress("AssetRegistry"),
                COVE_DEPLOYER_ADDRESS,
                feeCollectorAddress,
                COVE_DEPLOYER_ADDRESS
            )
        );
    }

    // Uses CREATE3 to deploy a fee collector contract. Salt must be the same given to the basket manager deploy.
    function _deployFeeCollector(bytes32 feeCollectorSalt) internal deployIfMissing("FeeCollector") {
        CREATE3Factory factory = CREATE3Factory(CREATE3_FACTORY);
        // Prepare constructor arguments for FeeCollector
        bytes memory constructorArgs = abi.encode(admin, deployer.getAddress("BasketManager"), treasury);
        // Deploy FeeCollector contract using CREATE3
        bytes memory feeCollectorBytecode = abi.encodePacked(type(FeeCollector).creationCode, constructorArgs);
        address feeCollector = address(factory.deploy(feeCollectorSalt, feeCollectorBytecode));
        deployer.save(
            "FeeCollector", feeCollector, "FeeCollector.sol:FeeCollector", constructorArgs, feeCollectorBytecode
        );
        require(checkDeployment("FeeCollector") == feeCollector, "Failed to save FeeCollector deployment");
    }

    // deploy and save euler router deployment
    function _deployEulerRouter() internal deployIfMissing("EulerRouter") {
        bytes memory constructorArgs = abi.encode(EVC, admin);
        // Deploy FeeCollector contract using CREATE3
        bytes memory feeCollectorBytecode = abi.encodePacked(type(EulerRouter).creationCode, constructorArgs);
        address eulerRouter = address(new EulerRouter(EVC, admin));
        deployer.save("EulerRouter", eulerRouter, "EulerRouter.sol:EulerRouter", constructorArgs, feeCollectorBytecode);
        require(checkDeployment("EulerRouter") == eulerRouter, "Failed to save EulerRouter deployment");
    }

    // Deploys a pyth oracle and chainlink oracle. Deploys an anchored oracle using the two privously deployed oracles.
    // Adds the assets to the asset registry. Sets the anchored oracle for the given assets in the euler router.
    // name like: "ETH/USD"
    // Caller must be admin
    function deployAnchoredOracleForPair(
        string memory name,
        address baseAsset,
        address quoteAsset,
        bytes32 pythPriceFeed,
        uint256 maxStaleness,
        uint256 maxConfWidth,
        address chainLinkPriceFeed,
        uint256 maxDivergence,
        bool isProduction
    )
        public
        deployIfMissing(string.concat(name, "_AnchoredOracle"))
    {
        if (!isProduction) {
            vm.startPrank(COVE_OPS_MULTISIG);
        }
        require(msg.sender == COVE_OPS_MULTISIG, "Must use COVE MULTISIG");
        deployer.setAutoBroadcast(isProduction);
        address primary =
            address(new PythOracle(Constants.PYTH, baseAsset, quoteAsset, pythPriceFeed, maxStaleness, maxConfWidth));
        address anchor = address(new ChainlinkOracle(baseAsset, quoteAsset, chainLinkPriceFeed, maxStaleness));
        string memory oracleName = string.concat(name, "_AnchoredOracle");
        address anchoredOracle =
            address(deployer.deploy_AnchoredOracle(oracleName, address(primary), address(anchor), maxDivergence));
        _addAssets(baseAsset, quoteAsset);
        _configureEulerRouter(baseAsset, quoteAsset, anchoredOracle);
    }

    // Creates a bitflag that includes all given asset indices.
    function includeAssets(uint8[] memory assetIndices) public pure returns (uint256 bitFlag) {
        for (uint256 i = 0; i < assetIndices.length; i++) {
            bitFlag |= 1 << assetIndices[i];
        }
    }

    // Checks thatn a deployment exists
    function checkDeployment(string memory name) public view returns (address addr) {
        if (deployer.has(name)) {
            addr = deployer.getAddress(name);
            console.log("Deployment already exists for", name, " at", vm.toString(addr));
        }
    }

    // Gets deployment address
    function getAddress(string memory name) public view returns (address addr) {
        addr = deployer.getAddress(name);
    }

    // Performs calls to grant permissions once deployment is successfull
    function _setupPermissions() internal {
        require(msg.sender == COVE_DEPLOYER_ADDRESS, "Must use COVE DEPLOYER");
        BasketManager bm = BasketManager(deployer.getAddress("BasketManager"));
        bm.grantRole(MANAGER_ROLE, manager);
        bm.grantRole(REBALANCER_ROLE, rebalancer);
        bm.grantRole(TIMELOCK_ROLE, timelock);
        bm.grantRole(PAUSER_ROLE, pauser);
        bm.grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // Adds assets to the asset registry. Trys are used as the call will fail if the assets have already been added.
    function _addAssets(address baseAsset, address quoteAsset) internal {
        AssetRegistry assetRegistry = AssetRegistry(deployer.getAddress("AssetRegistry"));
        try assetRegistry.addAsset(baseAsset) { } catch { }
        try assetRegistry.addAsset(quoteAsset) { } catch { }
    }

    // Configures the euler router for the given asset pair
    function _configureEulerRouter(address baseAsset, address quoteAsset, address anchoredOracle) internal {
        address eulerRouterAddress = deployer.getAddress("EulerRouter");
        EulerRouter(eulerRouterAddress).govSetConfig(baseAsset, quoteAsset, anchoredOracle);
        EulerRouter(eulerRouterAddress).govSetConfig(quoteAsset, baseAsset, anchoredOracle);
    }
}

// example run in current setup: DEPLOYMENT_CONTEXT=localhost forge script script/CoveDeployments.s.sol --rpc-url
// http://localhost:8545 --broadcast --private-key <key> -v
// && ./forge-deploy sync;
