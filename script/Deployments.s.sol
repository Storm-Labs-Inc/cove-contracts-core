// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { CREATE3Factory } from "create3-factory/src/CREATE3Factory.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { DeployScript } from "forge-deploy/DeployScript.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { FeeCollector } from "src/FeeCollector.sol";
import { IMasterRegistry } from "src/interfaces/IMasterRegistry.sol";
import { ManagedWeightStrategy } from "src/strategies/ManagedWeightStrategy.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";

import { BuildDeploymentJsonNames } from "./utils/BuildDeploymentJsonNames.sol";
import { CustomDeployerFunctions } from "./utils/CustomDeployerFunctions.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { Constants } from "test/utils/Constants.t.sol";

struct BasketTokenDeployment {
    // BasketToken initialize arguments
    string name; // BasketToken name. At initialization this will be prefixed with "CoveBasket "
    string symbol; // BasketToken symbol. At initialization this will be prefixed with "cvt"
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
abstract contract Deployments is DeployScript, Constants, StdAssertions, BuildDeploymentJsonNames {
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    address public admin;
    address public treasury;
    address public pauser;
    address public manager;
    address public timelock;
    address public rebalanceProposer;
    address public tokenSwapProposer;
    address public tokenSwapExecutor;
    address public basketTokenImplementation;
    IMasterRegistry public masterRegistry;

    bool public shouldBroadcast;
    bool public isStaging;

    address[] public registryAddressesToAdd;
    bytes32[] public registryNamesToAdd;
    bytes32[] public registryNamesToUpdate;
    bytes[] public multicallData;

    bytes32 internal constant _FEE_COLLECTOR_SALT = keccak256(abi.encodePacked("FeeCollector"));

    // Called from DeployScript's run() function.
    function deploy() public virtual {
        deploy(true);
    }

    function deploy(bool shouldBroadcast_) public {
        labelKnownAddresses();
        shouldBroadcast = shouldBroadcast_;
        _setPermissionedAddresses();

        // Start the prank if not in production
        if (!shouldBroadcast) {
            vm.startPrank(COVE_DEPLOYER_ADDRESS);
        } else {
            // Only allow COVE_DEPLOYER to deploy in production
            require(msg.sender == COVE_DEPLOYER_ADDRESS, "Caller must be COVE DEPLOYER");
        }
        deployer.setAutoBroadcast(shouldBroadcast);

        // Deploy unique core contracts
        _deployCoreContracts();

        // Deploy oracles and strategies for launch asset universe and baskets
        _deployNonCoreContracts();

        // Add all collected registry names to master registry
        _finalizeRegistryAdditions();

        // Give up all permissions from the deployer to the admin/manager multisig
        _cleanPermissions();

        // Stop the prank if not in production
        if (!shouldBroadcast) {
            vm.stopPrank();
        }
    }

    function _setPermissionedAddresses() internal virtual { }

    function _deployNonCoreContracts() internal virtual { }

    modifier onlyIfMissing(string memory name) {
        if (getAddress(name) != address(0)) {
            return;
        }
        _;
    }

    // Gets deployment address
    function getAddress(string memory name) public view returns (address addr) {
        addr = deployer.getAddress(name);
    }

    function _deployCoreContracts() internal {
        address assetRegistry = address(deployer.deploy_AssetRegistry(buildAssetRegistryName(), COVE_DEPLOYER_ADDRESS));
        address strategyRegistry =
            address(deployer.deploy_StrategyRegistry(buildStrategyRegistryName(), COVE_DEPLOYER_ADDRESS));
        address eulerRouter = address(deployer.deploy_EulerRouter(buildEulerRouterName(), EVC, COVE_DEPLOYER_ADDRESS));
        address basketManager = _deployBasketManager(_FEE_COLLECTOR_SALT);
        address feeCollector = _deployFeeCollector(_FEE_COLLECTOR_SALT);
        address cowSwapAdapter = _deployAndSetCowSwapAdapter();

        // Add all core contract names to the collection
        _addToMasterRegistryLater("AssetRegistry", assetRegistry);
        _addToMasterRegistryLater("StrategyRegistry", strategyRegistry);
        _addToMasterRegistryLater("EulerRouter", eulerRouter);
        _addToMasterRegistryLater("BasketManager", basketManager);
        _addToMasterRegistryLater("FeeCollector", feeCollector);
        _addToMasterRegistryLater("CowSwapAdapter", cowSwapAdapter);
    }

    function _setInitialWeightsAndDeployBasketToken(BasketTokenDeployment memory deployment)
        internal
        onlyIfMissing(buildBasketTokenName(deployment.name))
    {
        // Set initial weights for the strategy
        ManagedWeightStrategy strategy = ManagedWeightStrategy(deployment.strategy);
        if (shouldBroadcast) {
            vm.broadcast();
        }
        strategy.setTargetWeights(deployment.bitFlag, deployment.initialWeights);

        address basketManager = getAddress(buildBasketManagerName());
        if (shouldBroadcast) {
            vm.broadcast();
        }
        address basketToken = BasketManager(basketManager).createNewBasket(
            buildBasketTokenName(deployment.name),
            deployment.symbol,
            deployment.rootAsset,
            deployment.bitFlag,
            deployment.strategy
        );
        deployer.save(buildBasketTokenName(deployment.name), basketToken, "BasketToken.sol:BasketToken");
        require(
            getAddress(buildBasketTokenName(deployment.name)) == basketToken, "Failed to save BasketToken deployment"
        );
        require(BasketToken(basketToken).bitFlag() == deployment.bitFlag, "Failed to set bitFlag in BasketToken");
        assertEq(
            BasketManager(basketManager).basketAssets(basketToken),
            AssetRegistry(getAddress(buildAssetRegistryName())).getAssets(deployment.bitFlag),
            "Failed to set basket assets in BasketManager"
        );
    }

    // Deploys basket manager given a fee collector salt which must be used to deploy the fee collector using CREATE3.
    function _deployBasketManager(bytes32 feeCollectorSalt)
        internal
        onlyIfMissing(buildBasketManagerName())
        returns (address)
    {
        basketTokenImplementation = address(deployer.deploy_BasketToken(buildBasketTokenImplementationName()));
        CREATE3Factory factory = CREATE3Factory(CREATE3_FACTORY);
        // Determine feeCollector deployment address
        address feeCollectorAddress = factory.getDeployed(COVE_DEPLOYER_ADDRESS, feeCollectorSalt);
        BasketManager bm = deployer.deploy_BasketManager_Custom(
            buildBasketManagerName(),
            buildBasketManagerUtilsName(),
            basketTokenImplementation,
            getAddress(buildEulerRouterName()),
            getAddress(buildStrategyRegistryName()),
            getAddress(buildAssetRegistryName()),
            COVE_DEPLOYER_ADDRESS,
            feeCollectorAddress
        );
        if (shouldBroadcast) {
            vm.startBroadcast();
        }
        bm.grantRole(MANAGER_ROLE, COVE_DEPLOYER_ADDRESS);
        bm.grantRole(TIMELOCK_ROLE, COVE_DEPLOYER_ADDRESS);
        if (shouldBroadcast) {
            vm.stopBroadcast();
        }
        return address(bm);
    }

    // Uses CREATE3 to deploy a fee collector contract. Salt must be the same given to the basket manager deploy.
    function _deployFeeCollector(bytes32 feeCollectorSalt)
        internal
        onlyIfMissing(buildFeeCollectorName())
        returns (address feeCollector)
    {
        CREATE3Factory factory = CREATE3Factory(CREATE3_FACTORY);
        // Prepare constructor arguments for FeeCollector
        bytes memory constructorArgs = abi.encode(admin, getAddress(buildBasketManagerName()), treasury);
        // Deploy FeeCollector contract using CREATE3
        bytes memory creationBytecode = abi.encodePacked(type(FeeCollector).creationCode, constructorArgs);
        feeCollector = address(factory.deploy(feeCollectorSalt, creationBytecode));
        deployer.save(
            buildFeeCollectorName(), feeCollector, "FeeCollector.sol:FeeCollector", constructorArgs, creationBytecode
        );
        require(getAddress(buildFeeCollectorName()) == feeCollector, "Failed to save FeeCollector deployment");
    }

    // Deploys cow swap adapter, sets it as the token swap adapter in BasketManager
    function _deployAndSetCowSwapAdapter()
        internal
        onlyIfMissing(buildCowSwapAdapterName())
        returns (address cowSwapAdapter)
    {
        address cowSwapCloneImplementation =
            address(deployer.deploy_CoWSwapClone(buildCoWSwapCloneImplementationName()));
        cowSwapAdapter = address(deployer.deploy_CoWSwapAdapter(buildCowSwapAdapterName(), cowSwapCloneImplementation));
        address basketManager = getAddress(buildBasketManagerName());
        if (shouldBroadcast) {
            vm.broadcast();
        }
        BasketManager(basketManager).setTokenSwapAdapter(cowSwapAdapter);
    }

    // Deploys a managed weight strategy for an external manager
    function _deployManagedStrategy(
        address externalManager,
        string memory strategyName
    )
        internal
        onlyIfMissing(buildManagedWeightStrategyName(strategyName))
        returns (address strategy)
    {
        strategy = address(
            deployer.deploy_ManagedWeightStrategy(
                buildManagedWeightStrategyName(strategyName),
                address(COVE_DEPLOYER_ADDRESS),
                getAddress(buildBasketManagerName())
            )
        );
        ManagedWeightStrategy mwStrategy = ManagedWeightStrategy(strategy);
        if (shouldBroadcast) {
            vm.startBroadcast();
        }
        mwStrategy.grantRole(MANAGER_ROLE, externalManager);
        mwStrategy.grantRole(DEFAULT_ADMIN_ROLE, admin);
        mwStrategy.revokeRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS);
        StrategyRegistry(getAddress(buildStrategyRegistryName())).grantRole(_WEIGHT_STRATEGY_ROLE, strategy);
        if (shouldBroadcast) {
            vm.stopBroadcast();
        }
    }

    function _addToMasterRegistryLater(string memory name, address addr) internal {
        // Check if name fits in bytes32
        require(bytes(name).length <= 32, "Name is too long");
        registryNamesToAdd.push(bytes32(bytes(name)));
        registryAddressesToAdd.push(addr);
    }

    function _addAssetToAssetRegistry(address asset) internal {
        AssetRegistry assetRegistry = AssetRegistry(getAddress(buildAssetRegistryName()));
        if (shouldBroadcast) {
            vm.broadcast();
        }
        assetRegistry.addAsset(asset);
    }

    function _finalizeRegistryAdditions() internal {
        // First check if any registry names already exist in the master registry
        address registry = isStaging ? COVE_STAGING_MASTER_REGISTRY : COVE_MASTER_REGISTRY;
        multicallData = new bytes[](0);
        for (uint256 i = 0; i < registryNamesToAdd.length; i++) {
            try IMasterRegistry(registry).resolveNameToLatestAddress(registryNamesToAdd[i]) returns (address addr) {
                if (addr != registryAddressesToAdd[i]) {
                    multicallData.push(
                        abi.encodeWithSelector(
                            IMasterRegistry.updateRegistry.selector, registryNamesToAdd[i], registryAddressesToAdd[i]
                        )
                    );
                }
            } catch {
                multicallData.push(
                    abi.encodeWithSelector(
                        IMasterRegistry.addRegistry.selector, registryNamesToAdd[i], registryAddressesToAdd[i]
                    )
                );
            }
        }
        if (shouldBroadcast) {
            vm.broadcast();
        }

        Multicall(registry).multicall(multicallData);
    }

    // First deploys a pyth oracle and chainlink oracle. Then Deploys an anchored oracle using the two privously
    // deployed oracles.
    // Enable the anchored oracle for the given asset and USD
    function _deployDefaultAnchoredOracleForAsset(
        address asset,
        OracleOptions memory oracleOptions
    )
        internal
        onlyIfMissing(buildAnchoredOracleName(asset, USD))
    {
        // Save the deployment to the array
        address primary = address(
            deployer.deploy_PythOracle(
                buildPythOracleName(asset, USD),
                PYTH,
                asset,
                USD,
                oracleOptions.pythPriceFeed,
                oracleOptions.pythMaxStaleness,
                oracleOptions.pythMaxConfWidth
            )
        );
        address anchor = address(
            deployer.deploy_ChainlinkOracle(
                buildChainlinkOracleName(asset, USD),
                asset,
                USD,
                oracleOptions.chainlinkPriceFeed,
                oracleOptions.chainlinkMaxStaleness
            )
        );
        address anchoredOracle = address(
            deployer.deploy_AnchoredOracle(
                buildAnchoredOracleName(asset, USD), primary, anchor, oracleOptions.maxDivergence
            )
        );
        // Register the asset/USD anchored oracle
        EulerRouter eulerRouter = EulerRouter(getAddress(buildEulerRouterName()));
        if (shouldBroadcast) {
            vm.broadcast();
        }
        eulerRouter.govSetConfig(asset, USD, anchoredOracle);
    }

    // A helper function that does the following (in order):
    // - Deploys a pyth oracle.
    // - Deploys two chainlink oracles (one for the base asset pair and one between the quote asset of that pair and
    // USD).
    // - Deploys a cross adapter that will resolve this chain of two oracles.
    // - Deploys an anchored oracle with the deployed pyth oracle and cross adapter.
    // - Enable the anchored oracle for the given asset and USD.
    // Note: This is for deploying assets without direct USD chainlink price feed.
    // (e.g. a chaining oracle for pyth + 4626 or pyth + pyth or chainlink + 4626 or chainlink + chainlink)
    // (e.g. sfrxETH, yETH, yvWETH-1, crvUSD, sFRAX, weETH, ezETH, rsETH)
    function _deployChainlinkCrossAdapterForNonUSDPair(
        address asset,
        OracleOptions memory oracleOptions,
        address crossAsset,
        address chainlinkCrossFeed
    )
        internal
        onlyIfMissing(buildAnchoredOracleName(asset, crossAsset))
    {
        address primary = address(
            deployer.deploy_PythOracle(
                buildPythOracleName(asset, USD),
                PYTH,
                asset,
                USD,
                oracleOptions.pythPriceFeed,
                oracleOptions.pythMaxStaleness,
                oracleOptions.pythMaxConfWidth
            )
        );
        // Asset -> CrossAsset chainlink oracle
        address chainLinkBaseCrossOracle = address(
            deployer.deploy_ChainlinkOracle(
                buildChainlinkOracleName(asset, crossAsset),
                asset,
                crossAsset,
                oracleOptions.chainlinkPriceFeed,
                oracleOptions.chainlinkMaxStaleness
            )
        );
        // CrossAsset -> USD chainlink oracle
        address chainLinkCrossUSDOracle = address(
            deployer.deploy_ChainlinkOracle(
                buildChainlinkOracleName(crossAsset, USD),
                crossAsset,
                USD,
                chainlinkCrossFeed,
                oracleOptions.chainlinkMaxStaleness
            )
        );

        address crossAdapter = address(
            deployer.deploy_CrossAdapter(
                buildCrossAdapterName(asset, crossAsset, USD, "Chainlink", "Chainlink"),
                asset,
                crossAsset,
                USD,
                chainLinkBaseCrossOracle,
                chainLinkCrossUSDOracle
            )
        );
        address anchoredOracle = address(
            deployer.deploy_AnchoredOracle(
                buildAnchoredOracleName(asset, crossAsset), primary, crossAdapter, oracleOptions.maxDivergence
            )
        );
        // Register the asset/USD anchored oracle
        EulerRouter eulerRouter = EulerRouter(getAddress(buildEulerRouterName()));
        if (shouldBroadcast) {
            vm.broadcast();
        }
        eulerRouter.govSetConfig(asset, USD, anchoredOracle);
    }

    // Helper function to deploy a CurveEMA Oracle Cross Adapter for an asset/USD pair
    // first deploys a CurveEMA Oracle, then deploys a Pyth and Chainlink oracles for the cross asset,
    // then deploys two cross adapters, one using the pyth and one using the chainlink oracle,
    // then deploys an anchored oracle with the two cross adapters,
    // finally registers the anchored oracle with the EulerRouter.
    function _deployCurveEMAOracleCrossAdapterForNonUSDPair(
        address base,
        address pool,
        address crossAsset,
        OracleOptions memory quoteOracleOptions,
        uint256 priceOracleIndex
    )
        internal
        onlyIfMissing(buildCurveEMAOracleName(base, crossAsset))
    {
        address curveEMAOracle = address(
            deployer.deploy_CurveEMAOracle(buildCurveEMAOracleName(base, crossAsset), base, pool, priceOracleIndex)
        );
        address pythOracle = address(
            deployer.deploy_PythOracle(
                buildPythOracleName(crossAsset, USD),
                PYTH,
                crossAsset,
                USD,
                quoteOracleOptions.pythPriceFeed,
                quoteOracleOptions.pythMaxStaleness,
                quoteOracleOptions.pythMaxConfWidth
            )
        );
        address chainlinkOracle = address(
            deployer.deploy_ChainlinkOracle(
                buildChainlinkOracleName(crossAsset, USD),
                crossAsset,
                USD,
                quoteOracleOptions.chainlinkPriceFeed,
                quoteOracleOptions.chainlinkMaxStaleness
            )
        );
        address primaryCrossAdapter = address(
            deployer.deploy_CrossAdapter(
                buildCrossAdapterName(base, crossAsset, USD, "CurveEMA", "Pyth"),
                base,
                crossAsset,
                USD,
                curveEMAOracle,
                pythOracle
            )
        );
        address anchorCrossAdapter = address(
            deployer.deploy_CrossAdapter(
                buildCrossAdapterName(base, crossAsset, USD, "CurveEMA", "ChainLink"),
                base,
                crossAsset,
                USD,
                curveEMAOracle,
                chainlinkOracle
            )
        );
        address anchoredOracle = address(
            deployer.deploy_AnchoredOracle(
                buildAnchoredOracleName(base, USD),
                primaryCrossAdapter,
                anchorCrossAdapter,
                quoteOracleOptions.maxDivergence
            )
        );
        // Register the asset/USD cross adapter using EulerRouter
        EulerRouter eulerRouter = EulerRouter(getAddress(buildEulerRouterName()));
        if (shouldBroadcast) {
            vm.broadcast();
        }
        eulerRouter.govSetConfig(base, USD, anchoredOracle);
    }

    // Performs calls to grant permissions once deployment is successful
    function _cleanPermissions() internal {
        if (shouldBroadcast) {
            vm.startBroadcast();
        }
        // AssetRegistry
        AssetRegistry assetRegistry = AssetRegistry(getAddress(buildAssetRegistryName()));
        assetRegistry.grantRole(DEFAULT_ADMIN_ROLE, admin);
        assetRegistry.revokeRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS);

        // StrategyRegistry
        StrategyRegistry strategyRegistry = StrategyRegistry(getAddress(buildStrategyRegistryName()));
        strategyRegistry.grantRole(DEFAULT_ADMIN_ROLE, admin);
        strategyRegistry.revokeRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS);

        // EulerRouter
        EulerRouter eulerRouter = EulerRouter(getAddress(buildEulerRouterName()));
        eulerRouter.transferGovernance(admin);

        // BasketManager
        BasketManager bm = BasketManager(getAddress(buildBasketManagerName()));
        bm.grantRole(MANAGER_ROLE, manager);
        bm.grantRole(REBALANCE_PROPOSER_ROLE, rebalanceProposer);
        bm.grantRole(TOKENSWAP_PROPOSER_ROLE, tokenSwapProposer);
        bm.grantRole(TOKENSWAP_EXECUTOR_ROLE, tokenSwapExecutor);
        bm.grantRole(TIMELOCK_ROLE, timelock);
        bm.grantRole(PAUSER_ROLE, pauser);
        bm.grantRole(DEFAULT_ADMIN_ROLE, admin);
        bm.revokeRole(MANAGER_ROLE, COVE_DEPLOYER_ADDRESS);
        bm.revokeRole(TIMELOCK_ROLE, COVE_DEPLOYER_ADDRESS);
        bm.revokeRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS);

        if (shouldBroadcast) {
            vm.stopBroadcast();
        }
    }

    function assetsToBitFlag(address[] memory assets) public view returns (uint256 bitFlag) {
        return AssetRegistry(getAddress(buildAssetRegistryName())).getAssetsBitFlag(assets);
    }

    function _buildPrefix() internal view virtual override returns (string memory) {
        return "DEFAULT_";
    }
}
