// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { CREATE3Factory } from "create3-factory/src/CREATE3Factory.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { ChainlinkOracle } from "euler-price-oracle/src/adapter/chainlink/ChainlinkOracle.sol";
import { PythOracle } from "euler-price-oracle/src/adapter/pyth/PythOracle.sol";
import { DeployScript } from "forge-deploy/DeployScript.sol";

import { console } from "forge-std/console.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { FeeCollector } from "src/FeeCollector.sol";
import { ManagedWeightStrategy } from "src/strategies/ManagedWeightStrategy.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";
import { WeightStrategy } from "src/strategies/WeightStrategy.sol";
import { Constants } from "test/utils/Constants.t.sol";

import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";

struct BasketTokenDeployment {
    address asset;
    string name;
    string symbol;
    uint256 bitFlag;
    uint64[] initialWeights;
}

struct OracleOptions {
    bytes32 pythPriceFeed;
    uint256 pythMaxStaleness;
    uint256 pythMaxConfWidth;
    address chainlinkPriceFeed;
    uint256 chainlinkMaxStaleness;
    uint256 maxDivergence;
}

contract Deployments is DeployScript, Constants {
    using DeployerFunctions for Deployer;

    address public admin;
    address public treasury;
    address public pauser;
    address public manager;
    address public timelock;
    address public rebalancer;
    address public basketTokenImplementation;

    function deploy(
        BasketTokenDeployment[] memory basketTokenDeployments,
        OracleOptions[] memory oracleOptions,
        bool isProduction
    )
        public
    {
        require(msg.sender == COVE_DEPLOYER_ADDRESS, "Caller must be COVE DEPLOYER");
        if (!isProduction) {
            vm.startPrank(COVE_DEPLOYER_ADDRESS);
        }
        admin = COVE_OPS_MULTISIG;
        treasury = COVE_OPS_MULTISIG;
        pauser = COVE_OPS_MULTISIG;
        manager = COVE_OPS_MULTISIG;
        timelock = COVE_OPS_MULTISIG;
        rebalancer = COVE_OPS_MULTISIG;
        deployer.setAutoBroadcast(isProduction);

        _deployCoreContracts();
        bytes32 feeCollectorSalt = keccak256(abi.encodePacked("FeeCollector"));
        _deployBasketManager(feeCollectorSalt);
        _deployFeeCollector(feeCollectorSalt);

        for (uint256 i = 0; i < basketTokenDeployments.length; i++) {
            _deployAnchoredOracleForPair(basketTokenDeployments[i], oracleOptions[i]);
            _deployBasketTokenAndStrategy(basketTokenDeployments[i]);
        }
        _cleanPermissions();
    }

    modifier deployIfMissing(string memory name) {
        if (checkDeployment(name) != address(0)) {
            return;
        }
        _;
    }

    // Returns a bitflag that includes all given asset indices.
    function getBitflagFromIndicies(uint8[] memory assetIndices) public pure returns (uint256 bitFlag) {
        for (uint256 i = 0; i < assetIndices.length; i++) {
            bitFlag |= 1 << assetIndices[i];
        }
    }

    // Checks that a deployment exists
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

    function _deployCoreContracts() private {
        deployer.deploy_AssetRegistry("AssetRegistry", COVE_DEPLOYER_ADDRESS);
        deployer.deploy_StrategyRegistry("StrategyRegistry", COVE_DEPLOYER_ADDRESS);
        basketTokenImplementation = address(deployer.deploy_BasketToken("BasketTokenImplementation"));
        _deployEulerRouter();
    }

    function _deployBasketTokenAndStrategy(BasketTokenDeployment memory deployment) private {
        address strategy = _deployStrategy(deployment);
        // TODO: any way to handle this better, if other basket use USD this will fail in the current bm setup.
        try AssetRegistry(deployer.getAddress("AssetRegistry")).addAsset(USD) { } catch { }
        bytes memory basketTokenConstructorArgs = abi.encode(
            string.concat(deployment.name, "_basketToken"),
            deployment.name,
            deployment.asset,
            deployment.bitFlag,
            strategy
        );
        address basketManagerAddress = deployer.getAddress("BasketManager");
        address basketAddress = BasketManager(basketManagerAddress).createNewBasket(
            string.concat(deployment.name, "_basketToken"),
            deployment.name,
            deployment.asset,
            deployment.bitFlag,
            strategy
        );
        bytes memory basketCreationCode = abi.encodePacked(type(BasketManager).creationCode, basketTokenConstructorArgs);
        deployer.save(
            string.concat(deployment.name, "_BasketToken"),
            basketAddress,
            "BasketToken.sol:BasketToken",
            basketTokenConstructorArgs,
            basketCreationCode
        );
    }

    // Deploys basket manager given a fee collector salt which must be used to deploy the fee collector using CREATE3.
    function _deployBasketManager(bytes32 feeCollectorSalt) private deployIfMissing("BasketManager") {
        CREATE3Factory factory = CREATE3Factory(CREATE3_FACTORY);
        // Determine feeCollector deployment address
        address feeCollectorAddress = factory.getDeployed(COVE_DEPLOYER_ADDRESS, feeCollectorSalt);
        BasketManager bm = deployer.deploy_BasketManager(
            "BasketManager",
            basketTokenImplementation,
            deployer.getAddress("EulerRouter"),
            deployer.getAddress("StrategyRegistry"),
            deployer.getAddress("AssetRegistry"),
            COVE_DEPLOYER_ADDRESS,
            feeCollectorAddress,
            COVE_DEPLOYER_ADDRESS
        );
        bm.grantRole(MANAGER_ROLE, COVE_DEPLOYER_ADDRESS);
    }

    // Uses CREATE3 to deploy a fee collector contract. Salt must be the same given to the basket manager deploy.
    function _deployFeeCollector(bytes32 feeCollectorSalt) private deployIfMissing("FeeCollector") {
        CREATE3Factory factory = CREATE3Factory(CREATE3_FACTORY);
        // Prepare constructor arguments for FeeCollector
        bytes memory constructorArgs = abi.encode(admin, deployer.getAddress("BasketManager"), treasury);
        // Deploy FeeCollector contract using CREATE3
        bytes memory creationBytecode = abi.encodePacked(type(FeeCollector).creationCode, constructorArgs);
        address feeCollector = address(factory.deploy(feeCollectorSalt, creationBytecode));
        deployer.save("FeeCollector", feeCollector, "FeeCollector.sol:FeeCollector", constructorArgs, creationBytecode);
        require(checkDeployment("FeeCollector") == feeCollector, "Failed to save FeeCollector deployment");
    }

    // Deploys and save euler router deployment
    function _deployEulerRouter() private deployIfMissing("EulerRouter") {
        bytes memory constructorArgs = abi.encode(EVC, admin);
        // Deploy FeeCollector contract using CREATE3
        bytes memory creationBytecode = abi.encodePacked(type(EulerRouter).creationCode, constructorArgs);
        address eulerRouter = address(new EulerRouter(EVC, COVE_DEPLOYER_ADDRESS));
        deployer.save("EulerRouter", eulerRouter, "EulerRouter.sol:EulerRouter", constructorArgs, creationBytecode);
        require(checkDeployment("EulerRouter") == eulerRouter, "Failed to save EulerRouter deployment");
    }

    // Deploys a managed weight strategy for the given basket token deployment
    function _deployStrategy(BasketTokenDeployment memory deployment) private returns (address strategy) {
        strategy = address(
            deployer.deploy_ManagedWeightStrategy(
                string.concat(deployment.name, "_ManagedWeightStrategy"),
                address(COVE_DEPLOYER_ADDRESS),
                getAddress("BasketManager")
            )
        );
        ManagedWeightStrategy mwStrategy = ManagedWeightStrategy(strategy);
        mwStrategy.setTargetWeights(deployment.bitFlag, deployment.initialWeights);
        mwStrategy.grantRole(DEFAULT_ADMIN_ROLE, admin);
        mwStrategy.revokeRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS);
        StrategyRegistry(getAddress("StrategyRegistry")).grantRole(_WEIGHT_STRATEGY_ROLE, strategy);
        // TODO: remove for production
        vm.mockCall(
            strategy,
            abi.encodeWithSelector(WeightStrategy.supportsBitFlag.selector, deployment.bitFlag),
            abi.encode(true)
        );
        AssetRegistry assetRegistry = AssetRegistry(deployer.getAddress("AssetRegistry"));
        try assetRegistry.addAsset(address(deployment.asset)) { } catch { }
    }

    // Deploys a pyth oracle for given base and quote assets
    function _deployPythOracle(
        string memory name,
        address baseAsset,
        address quoteAsset,
        bytes32 pythPriceFeed,
        uint256 pythMaxStaleness,
        uint256 maxConfWidth
    )
        private
        returns (address primary)
    {
        bytes memory pythOracleContsructorArgs =
            abi.encode(PYTH, baseAsset, quoteAsset, pythPriceFeed, pythMaxStaleness, maxConfWidth);
        primary = address(
            new PythOracle(Constants.PYTH, baseAsset, quoteAsset, pythPriceFeed, pythMaxStaleness, maxConfWidth)
        );
        deployer.save(
            string.concat(name, "_PythOracle"),
            primary,
            "PythOracle.sol:PythOracle",
            pythOracleContsructorArgs,
            abi.encodePacked(type(PythOracle).creationCode, pythOracleContsructorArgs)
        );
    }

    // Deploys a Chainlink oracle for the given base and quote assets
    function _deployChainlinkOracle(
        string memory name,
        address baseAsset,
        address quoteAsset,
        address chainLinkPriceFeed,
        uint256 chainLinkMaxStaleness
    )
        private
        returns (address anchor)
    {
        bytes memory chainLinkOracleContsructorArgs =
            abi.encode(CHAINLINK_ETH_USD_FEED, baseAsset, quoteAsset, chainLinkPriceFeed, chainLinkMaxStaleness);
        anchor = address(new ChainlinkOracle(baseAsset, quoteAsset, chainLinkPriceFeed, chainLinkMaxStaleness));
        deployer.save(
            string.concat(name, "_ChainlinkOracle"),
            address(new ChainlinkOracle(baseAsset, quoteAsset, chainLinkPriceFeed, chainLinkMaxStaleness)),
            "ChainlinkOracle.sol:ChainlinkOracle",
            chainLinkOracleContsructorArgs,
            abi.encodePacked(type(ChainlinkOracle).creationCode, chainLinkOracleContsructorArgs)
        );
    }

    // Deploys a pyth oracle and chainlink oracle. Deploys an anchored oracle using the two privously deployed oracles.
    // Adds the assets to the asset registry. Sets the anchored oracle for the given assets in the euler router.
    function _deployAnchoredOracleForPair(
        BasketTokenDeployment memory deployment,
        OracleOptions memory oracleOptions
    )
        private
        deployIfMissing(string.concat(deployment.name, "_AnchoredOracle"))
    {
        address primary = _deployPythOracle(
            deployment.name,
            deployment.asset,
            USD,
            oracleOptions.pythPriceFeed,
            oracleOptions.pythMaxStaleness,
            oracleOptions.pythMaxConfWidth
        );
        address anchor = _deployChainlinkOracle(
            deployment.name,
            deployment.asset,
            USD,
            oracleOptions.chainlinkPriceFeed,
            oracleOptions.chainlinkMaxStaleness
        );
        string memory oracleName = string.concat(deployment.name, "_AnchoredOracle");
        address anchoredOracle =
            address(deployer.deploy_AnchoredOracle(oracleName, primary, anchor, oracleOptions.maxDivergence));
        EulerRouter(deployer.getAddress("EulerRouter")).govSetConfig(deployment.asset, USD, anchoredOracle);
    }

    // Performs calls to grant permissions once deployment is successful
    function _cleanPermissions() private {
        AssetRegistry(deployer.getAddress("AssetRegistry")).grantRole(DEFAULT_ADMIN_ROLE, admin);
        AssetRegistry(deployer.getAddress("AssetRegistry")).revokeRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS);
        StrategyRegistry(deployer.getAddress("StrategyRegistry")).grantRole(DEFAULT_ADMIN_ROLE, admin);
        StrategyRegistry(deployer.getAddress("StrategyRegistry")).revokeRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS);
        EulerRouter(deployer.getAddress("EulerRouter")).transferGovernance(admin);
        BasketManager bm = BasketManager(deployer.getAddress("BasketManager"));
        bm.grantRole(MANAGER_ROLE, manager);
        bm.grantRole(REBALANCER_ROLE, rebalancer);
        bm.grantRole(TIMELOCK_ROLE, timelock);
        bm.grantRole(PAUSER_ROLE, pauser);
        bm.grantRole(DEFAULT_ADMIN_ROLE, admin);
        bm.revokeRole(MANAGER_ROLE, COVE_DEPLOYER_ADDRESS);
        bm.revokeRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS);
    }
}

// example run in current setup: DEPLOYMENT_CONTEXT=localhost forge script script/Deployments.s.sol --rpc-url
// http://localhost:8545 --broadcast --private-key <key> -v
// && ./forge-deploy sync;
