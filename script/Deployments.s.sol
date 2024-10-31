// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { CREATE3Factory } from "create3-factory/src/CREATE3Factory.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { ChainlinkOracle } from "euler-price-oracle/src/adapter/chainlink/ChainlinkOracle.sol";
import { PythOracle } from "euler-price-oracle/src/adapter/pyth/PythOracle.sol";
import { DeployScript } from "forge-deploy/DeployScript.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { FeeCollector } from "src/FeeCollector.sol";
import { ManagedWeightStrategy } from "src/strategies/ManagedWeightStrategy.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";
import { Constants } from "test/utils/Constants.t.sol";

struct BasketTokenDeployment {
    // BasketToken initialize arguments
    string name;
    string symbol;
    address rootAsset;
    uint256 bitFlag;
    address strategy;
    // WeightStrategy.setTargetWeights() arguments
    uint64[] initialWeights;
}

struct OracleOptions {
    // Pyth oracle constructor arguments
    bytes32 pythPriceFeed;
    uint256 pythMaxStaleness;
    uint256 pythMaxConfWidth;
    // Chainlink oracle constructor arguments
    address chainlinkPriceFeed;
    uint256 chainlinkMaxStaleness;
    // Anchored oracle constructor arguments
    uint256 maxDivergence;
}

// TODO: ensure calls without forge-deploy are broadcasted correctly with vm.broadcast
contract Deployments is DeployScript, Constants, StdAssertions {
    using DeployerFunctions for Deployer;

    address public admin;
    address public treasury;
    address public pauser;
    address public manager;
    address public timelock;
    address public rebalanceProposer;
    address public tokenswapProposer;
    address public tokenswapExecutor;
    address public basketTokenImplementation;

    bool public isProduction;

    bytes32 private constant _FEE_COLLECTOR_SALT = keccak256(abi.encodePacked("FeeCollector"));

    // Called from DeployScript's run() function.
    function deploy() public {
        deploy(true);
    }

    function deploy(bool isProduction_) public {
        isProduction = isProduction_;
        // Start the prank if not in production
        if (!isProduction) {
            vm.startPrank(COVE_DEPLOYER_ADDRESS);
        } else {
            // Only allow COVE_DEPLOYER to deploy in production
            require(msg.sender == COVE_DEPLOYER_ADDRESS, "Caller must be COVE DEPLOYER");
        }
        deployer.setAutoBroadcast(isProduction);

        // Define permissioned addresses
        // TODO: replace with actual addresses
        admin = COVE_OPS_MULTISIG;
        treasury = COVE_OPS_MULTISIG;
        pauser = COVE_OPS_MULTISIG;
        manager = COVE_OPS_MULTISIG;
        timelock = COVE_OPS_MULTISIG;
        rebalanceProposer = COVE_OPS_MULTISIG;
        tokenswapProposer = COVE_OPS_MULTISIG;
        tokenswapExecutor = COVE_OPS_MULTISIG;

        // Deploy unique core contracts
        _deployCoreContracts();

        // Deploy oracles and strategies for launch asset universe and baskets

        // TODO: finalize the list of assets and their oracle options
        // 0. WETH
        _deployDefaultAnchoredOracleForAsset(
            ETH_WETH,
            "WETH",
            OracleOptions({
                pythPriceFeed: PYTH_ETH_USD_FEED, // TODO: confirm WETH vs ETH oracle
                pythMaxStaleness: 15 minutes,
                pythMaxConfWidth: 100,
                chainlinkPriceFeed: ETH_CHAINLINK_ETH_USD_FEED, // TODO: confirm WETH vs ETH oracle
                chainlinkMaxStaleness: 1 days, // TODO: confirm staleness duration
                maxDivergence: 0.5e18
            })
        );
        _addAssetToAssetRegistry(ETH_WETH);

        // 1. SUSDE
        _deployDefaultAnchoredOracleForAsset(
            ETH_SUSDE,
            "SUSDE",
            OracleOptions({
                pythPriceFeed: PYTH_SUSE_USD_FEED,
                pythMaxStaleness: 15 minutes,
                pythMaxConfWidth: 100,
                chainlinkPriceFeed: ETH_CHAINLINK_SUSDE_USD_FEED,
                chainlinkMaxStaleness: 1 days, // TODO: confirm staleness duration
                maxDivergence: 0.5e18
            })
        );
        _addAssetToAssetRegistry(ETH_SUSDE);

        // Deploy launch strategies
        _deployManagedStrategy(GAUNTLET_STRATEGIST, "Gauntlet V1"); // TODO: confirm strategy name

        // Deploy launch basket tokens
        address[] memory basketAssets = new address[](2); // TODO: confirm assets with Gauntlet
        basketAssets[0] = ETH_WETH;
        basketAssets[1] = ETH_SUSDE;
        uint64[] memory initialWeights = new uint64[](2); // TODO: confirm initial weights with Guantlet
        initialWeights[0] = 0.5e18;
        initialWeights[1] = 0.5e18;
        _setInitialWeightsAndDeployBasketToken(
            BasketTokenDeployment({
                name: "Gauntlet WETH-SUSDE Basket", // TODO: confirm basket name
                symbol: "GVT1", // TODO: confirm symbol
                rootAsset: ETH_WETH, // TODO: confirm root asset
                bitFlag: _assetsToBitFlag(basketAssets),
                strategy: getAddress("Gauntlet V1_ManagedWeightStrategy"), // TODO: confirm strategy
                initialWeights: initialWeights
            })
        );

        // Give up all permissions from the deployer to the admin/manager multisig
        _cleanPermissions();

        // Stop the prank if not in production
        if (!isProduction) {
            vm.stopPrank();
        }
    }

    modifier deployIfMissing(string memory name) {
        if (getAddress(name) != address(0)) {
            return;
        }
        _;
    }

    // Gets deployment address
    function getAddress(string memory name) public view returns (address addr) {
        addr = deployer.getAddress(name);
    }

    function _deployCoreContracts() private {
        deployer.deploy_AssetRegistry("AssetRegistry", COVE_DEPLOYER_ADDRESS);
        deployer.deploy_StrategyRegistry("StrategyRegistry", COVE_DEPLOYER_ADDRESS);
        _deployEulerRouter();
        _deployBasketManager(_FEE_COLLECTOR_SALT);
        _deployFeeCollector(_FEE_COLLECTOR_SALT);
    }

    function _setInitialWeightsAndDeployBasketToken(BasketTokenDeployment memory deployment) private {
        // Set initial weights for the strategy
        ManagedWeightStrategy strategy = ManagedWeightStrategy(deployment.strategy);
        if (isProduction) {
            vm.broadcast();
        }
        strategy.setTargetWeights(deployment.bitFlag, deployment.initialWeights);

        bytes memory basketTokenConstructorArgs = abi.encode(
            string.concat(deployment.name, "_basketToken"),
            deployment.name,
            deployment.rootAsset,
            deployment.bitFlag,
            deployment.strategy
        );
        address basketManager = getAddress("BasketManager");
        if (isProduction) {
            vm.broadcast();
        }
        address basketToken = BasketManager(basketManager).createNewBasket(
            string.concat(deployment.name, "_basketToken"),
            deployment.name,
            deployment.rootAsset,
            deployment.bitFlag,
            deployment.strategy
        );
        bytes memory basketCreationCode = abi.encodePacked(type(BasketManager).creationCode, basketTokenConstructorArgs);
        deployer.save(
            string.concat(deployment.name, "_BasketToken"),
            basketToken,
            "BasketToken.sol:BasketToken",
            basketTokenConstructorArgs,
            basketCreationCode
        );
        require(
            getAddress(string.concat(deployment.name, "_BasketToken")) == basketToken,
            "Failed to save BasketToken deployment"
        );
        require(BasketToken(basketToken).bitFlag() == deployment.bitFlag, "Failed to set bitFlag in BasketToken");
        assertEq(
            BasketManager(basketManager).basketAssets(basketToken),
            AssetRegistry(getAddress("AssetRegistry")).getAssets(deployment.bitFlag),
            "Failed to set basket assets in BasketManager"
        );
    }

    // Deploys basket manager given a fee collector salt which must be used to deploy the fee collector using CREATE3.
    function _deployBasketManager(bytes32 feeCollectorSalt) private deployIfMissing("BasketManager") {
        basketTokenImplementation = address(deployer.deploy_BasketToken("BasketTokenImplementation"));
        CREATE3Factory factory = CREATE3Factory(CREATE3_FACTORY);
        // Determine feeCollector deployment address
        address feeCollectorAddress = factory.getDeployed(COVE_DEPLOYER_ADDRESS, feeCollectorSalt);
        BasketManager bm = deployer.deploy_BasketManager(
            "BasketManager",
            basketTokenImplementation,
            getAddress("EulerRouter"),
            getAddress("StrategyRegistry"),
            getAddress("AssetRegistry"),
            COVE_DEPLOYER_ADDRESS,
            feeCollectorAddress
        );
        if (isProduction) {
            vm.broadcast();
        }
        bm.grantRole(MANAGER_ROLE, COVE_DEPLOYER_ADDRESS);
    }

    // Uses CREATE3 to deploy a fee collector contract. Salt must be the same given to the basket manager deploy.
    function _deployFeeCollector(bytes32 feeCollectorSalt) private deployIfMissing("FeeCollector") {
        CREATE3Factory factory = CREATE3Factory(CREATE3_FACTORY);
        // Prepare constructor arguments for FeeCollector
        bytes memory constructorArgs = abi.encode(admin, getAddress("BasketManager"), treasury);
        // Deploy FeeCollector contract using CREATE3
        bytes memory creationBytecode = abi.encodePacked(type(FeeCollector).creationCode, constructorArgs);
        address feeCollector = address(factory.deploy(feeCollectorSalt, creationBytecode));
        deployer.save("FeeCollector", feeCollector, "FeeCollector.sol:FeeCollector", constructorArgs, creationBytecode);
        require(getAddress("FeeCollector") == feeCollector, "Failed to save FeeCollector deployment");
    }

    // Deploys and save euler router deployment
    function _deployEulerRouter() private deployIfMissing("EulerRouter") {
        bytes memory constructorArgs = abi.encode(EVC, admin);
        // Deploy FeeCollector contract using CREATE3
        bytes memory creationBytecode = abi.encodePacked(type(EulerRouter).creationCode, constructorArgs);
        if (isProduction) {
            vm.broadcast();
        }
        address eulerRouter = address(new EulerRouter(EVC, COVE_DEPLOYER_ADDRESS));
        deployer.save("EulerRouter", eulerRouter, "EulerRouter.sol:EulerRouter", constructorArgs, creationBytecode);
        require(getAddress("EulerRouter") == eulerRouter, "Failed to save EulerRouter deployment");
    }

    // Deploys a managed weight strategy for an external manager
    function _deployManagedStrategy(
        address externalManager,
        string memory strategyName
    )
        private
        returns (address strategy)
    {
        strategy = address(
            deployer.deploy_ManagedWeightStrategy(
                string.concat(strategyName, "_ManagedWeightStrategy"),
                address(COVE_DEPLOYER_ADDRESS),
                getAddress("BasketManager")
            )
        );
        ManagedWeightStrategy mwStrategy = ManagedWeightStrategy(strategy);
        if (isProduction) {
            vm.startBroadcast();
        }
        mwStrategy.grantRole(MANAGER_ROLE, externalManager);
        mwStrategy.grantRole(DEFAULT_ADMIN_ROLE, admin);
        mwStrategy.revokeRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS);
        StrategyRegistry(getAddress("StrategyRegistry")).grantRole(_WEIGHT_STRATEGY_ROLE, strategy);
        if (isProduction) {
            vm.stopBroadcast();
        }
    }

    function _addAssetToAssetRegistry(address asset) private {
        AssetRegistry assetRegistry = AssetRegistry(getAddress("AssetRegistry"));
        if (isProduction) {
            vm.broadcast();
        }
        assetRegistry.addAsset(asset);
    }

    // Deploys a pyth oracle for given base and quote assets
    function _deployPythOracle(
        string memory baseAssetName,
        address baseAsset,
        address quoteAsset,
        bytes32 pythPriceFeed,
        uint256 pythMaxStaleness,
        uint256 maxConfWidth
    )
        private
        deployIfMissing(string.concat(baseAssetName, "_PythOracle"))
        returns (address pythOracle)
    {
        bytes memory pythOracleContsructorArgs =
            abi.encode(PYTH, baseAsset, quoteAsset, pythPriceFeed, pythMaxStaleness, maxConfWidth);
        if (isProduction) {
            vm.broadcast();
        }
        pythOracle = address(
            new PythOracle(Constants.PYTH, baseAsset, quoteAsset, pythPriceFeed, pythMaxStaleness, maxConfWidth)
        );
        deployer.save(
            string.concat(baseAssetName, "_PythOracle"),
            pythOracle,
            "PythOracle.sol:PythOracle",
            pythOracleContsructorArgs,
            abi.encodePacked(type(PythOracle).creationCode, pythOracleContsructorArgs)
        );
        assertEq(
            getAddress(string.concat(baseAssetName, "_PythOracle")), pythOracle, "Failed to save PythOracle deployment"
        );
    }

    // Deploys a Chainlink oracle for the given base and quote assets
    function _deployChainlinkOracle(
        string memory assetName,
        address baseAsset,
        address quoteAsset,
        address chainLinkPriceFeed,
        uint256 chainLinkMaxStaleness
    )
        private
        deployIfMissing(string.concat(assetName, "_ChainlinkOracle"))
        returns (address chainlinkOracle)
    {
        bytes memory chainLinkOracleContsructorArgs =
            abi.encode(baseAsset, quoteAsset, chainLinkPriceFeed, chainLinkMaxStaleness);
        if (isProduction) {
            vm.broadcast();
        }
        chainlinkOracle = address(new ChainlinkOracle(baseAsset, quoteAsset, chainLinkPriceFeed, chainLinkMaxStaleness));
        deployer.save(
            string.concat(assetName, "_ChainlinkOracle"),
            chainlinkOracle,
            "ChainlinkOracle.sol:ChainlinkOracle",
            chainLinkOracleContsructorArgs,
            abi.encodePacked(type(ChainlinkOracle).creationCode, chainLinkOracleContsructorArgs)
        );
        assertEq(
            getAddress(string.concat(assetName, "_ChainlinkOracle")),
            chainlinkOracle,
            "Failed to save ChainlinkOracle deployment"
        );
    }

    // First deploys a pyth oracle and chainlink oracle. Then Deploys an anchored oracle using the two privously
    // deployed oracles.
    // Enable the anchored oracle for the given asset and USD
    // Note: This is for deploying asset/USD anchored oracle for both pyth and chainlink that have asset/USD price feeds
    // Assets without direct USD price feed should not use this function to deploy their USD oracles.
    // TODO: Add a chaining oracle for assets without direct USD price feed
    // (e.g. a chaining oracle for pyth + 4626 or pyth + pyth or chainlink + 4626 or chainlink + chainlink)
    // (e.g. sfrxETH, yETH, yvWETH-1, crvUSD, sFRAX, weETH, ezETH, rsETH)
    function _deployDefaultAnchoredOracleForAsset(
        address asset,
        string memory assetName,
        OracleOptions memory oracleOptions
    )
        private
        deployIfMissing(string.concat(assetName, "_AnchoredOracle"))
    {
        address primary = _deployPythOracle(
            assetName,
            asset,
            USD,
            oracleOptions.pythPriceFeed,
            oracleOptions.pythMaxStaleness,
            oracleOptions.pythMaxConfWidth
        );
        address anchor = _deployChainlinkOracle(
            assetName, asset, USD, oracleOptions.chainlinkPriceFeed, oracleOptions.chainlinkMaxStaleness
        );
        address anchoredOracle = address(
            deployer.deploy_AnchoredOracle(
                string.concat(assetName, "_AnchoredOracle"), primary, anchor, oracleOptions.maxDivergence
            )
        );
        // Register the asset/USD anchored oracle
        EulerRouter eulerRouter = EulerRouter(getAddress("EulerRouter"));
        if (isProduction) {
            vm.broadcast();
        }
        eulerRouter.govSetConfig(asset, USD, anchoredOracle);
    }

    // Performs calls to grant permissions once deployment is successful
    function _cleanPermissions() private {
        if (isProduction) {
            vm.startBroadcast();
        }
        // AssetRegistry
        AssetRegistry assetRegistry = AssetRegistry(getAddress("AssetRegistry"));
        assetRegistry.grantRole(DEFAULT_ADMIN_ROLE, admin);
        assetRegistry.revokeRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS);

        // StrategyRegistry
        StrategyRegistry strategyRegistry = StrategyRegistry(getAddress("StrategyRegistry"));
        strategyRegistry.grantRole(DEFAULT_ADMIN_ROLE, admin);
        strategyRegistry.revokeRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS);

        // EulerRouter
        EulerRouter eulerRouter = EulerRouter(getAddress("EulerRouter"));
        eulerRouter.transferGovernance(admin);

        // BasketManager
        BasketManager bm = BasketManager(getAddress("BasketManager"));
        bm.grantRole(MANAGER_ROLE, manager);
        bm.grantRole(REBALANCE_PROPOSER_ROLE, rebalanceProposer);
        bm.grantRole(TOKENSWAP_PROPOSER_ROLE, tokenswapProposer);
        bm.grantRole(TOKENSWAP_EXECUTOR_ROLE, tokenswapExecutor);
        bm.grantRole(TIMELOCK_ROLE, timelock);
        bm.grantRole(PAUSER_ROLE, pauser);
        bm.grantRole(DEFAULT_ADMIN_ROLE, admin);
        bm.revokeRole(MANAGER_ROLE, COVE_DEPLOYER_ADDRESS);
        bm.revokeRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS);

        if (isProduction) {
            vm.stopBroadcast();
        }
    }

    function _assetsToBitFlag(address[] memory assets) private view returns (uint256 bitFlag) {
        return AssetRegistry(getAddress("AssetRegistry")).getAssetsBitFlag(assets);
    }
}
