// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { CREATE3Factory } from "create3-factory/src/CREATE3Factory.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { ICurvePool } from "euler-price-oracle/src/adapter/curve/ICurvePool.sol";
import { DeployScript } from "forge-deploy/DeployScript.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";
import { console } from "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { FeeCollector } from "src/FeeCollector.sol";
import { IMasterRegistry } from "src/interfaces/IMasterRegistry.sol";

import { BasicRetryOperator } from "src/operators/BasicRetryOperator.sol";
import { FarmingPluginFactory } from "src/rewards/FarmingPluginFactory.sol";
import { ManagedWeightStrategy } from "src/strategies/ManagedWeightStrategy.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";
import { IERC20Plugins } from "token-plugins-upgradeable/contracts/interfaces/IERC20Plugins.sol";

import { BuildDeploymentJsonNames } from "./utils/BuildDeploymentJsonNames.sol";
import { CustomDeployerFunctions } from "./utils/CustomDeployerFunctions.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { Constants } from "test/utils/Constants.t.sol";

struct BasketTokenDeployment {
    // BasketToken initialize arguments
    string name; // BasketToken name. At initialization this will be prefixed with "Cove "
    string symbol; // BasketToken symbol. At initialization this will be prefixed with "cove"
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
    address public rewardToken;
    IMasterRegistry public masterRegistry;

    bool public shouldBroadcast;

    address[] public registryAddressesToAdd;
    bytes32[] public registryNamesToAdd;
    bytes32[] public registryNamesToUpdate;
    bytes[] public multicallData;

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

        // Deploy farming plugins for each basket token with COVE rewards
        _deployPluginsViaFactory();

        // Give up all permissions from the deployer to the admin/manager multisig
        _cleanPermissions();

        // Stop the prank if not in production
        if (!shouldBroadcast) {
            vm.stopPrank();
        }

        _postDeploy();
    }

    // solhint-disable-next-line no-empty-blocks
    function _postDeploy() internal virtual { }

    // solhint-disable-next-line no-empty-blocks
    function _setPermissionedAddresses() internal virtual { }

    // solhint-disable-next-line no-empty-blocks
    function _deployNonCoreContracts() internal virtual { }

    modifier onlyIfMissing(string memory name) {
        address addr = getAddress(name);
        if (addr != address(0)) {
            return;
        }
        _;
    }

    // Gets deployment address
    function getAddress(string memory name) public view returns (address addr) {
        addr = deployer.getAddress(name);
    }

    function getAddressOrRevert(string memory name) public view returns (address addr) {
        addr = deployer.getAddress(name);
        require(addr != address(0), string.concat("Deployment ", name, " not found"));
    }

    function _deployCoreContracts() internal virtual {
        address assetRegistry = address(deployer.deploy_AssetRegistry(buildAssetRegistryName(), COVE_DEPLOYER_ADDRESS));
        address strategyRegistry =
            address(deployer.deploy_StrategyRegistry(buildStrategyRegistryName(), COVE_DEPLOYER_ADDRESS));
        address eulerRouter =
            address(deployer.deploy_EulerRouter(buildEulerRouterName(), _evc(), COVE_DEPLOYER_ADDRESS));
        _deployBasketManager(_feeCollectorSalt());
        _deployFeeCollector(_feeCollectorSalt());
        _deployAndSetCowSwapAdapter();
        _deployFarmingPluginFactory();
        address basicRetryOperator = address(
            deployer.deploy_BasicRetryOperator(
                buildBasicRetryOperatorName(), COVE_DEPLOYER_ADDRESS, COVE_DEPLOYER_ADDRESS
            )
        );

        // Add all core contract names to the collection
        _addToMasterRegistryLater("AssetRegistry", assetRegistry);
        _addToMasterRegistryLater("StrategyRegistry", strategyRegistry);
        _addToMasterRegistryLater("EulerRouter", eulerRouter);
        _addToMasterRegistryLater("BasketManager", getAddressOrRevert(buildBasketManagerName()));
        _addToMasterRegistryLater("FeeCollector", getAddressOrRevert(buildFeeCollectorName()));
        _addToMasterRegistryLater("CowSwapAdapter", getAddressOrRevert(buildCowSwapAdapterName()));
        _addToMasterRegistryLater("FarmingPluginFactory", getAddressOrRevert(buildFarmingPluginFactoryName()));
        _addToMasterRegistryLater("BasicRetryOperator", basicRetryOperator);
    }

    function _feeCollectorSalt() internal view virtual returns (bytes32);

    function _evc() internal view virtual returns (address) {
        if (block.chainid == BASE_CHAIN_ID) {
            return BASE_EVC;
        }
        return EVC;
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

        address basketManager = getAddressOrRevert(buildBasketManagerName());
        if (shouldBroadcast) {
            vm.broadcast();
        }
        address basketToken = BasketManager(basketManager)
            .createNewBasket(
                deployment.name, deployment.symbol, deployment.rootAsset, deployment.bitFlag, deployment.strategy
            );
        deployer.save(buildBasketTokenName(deployment.name), basketToken, "BasketToken.sol:BasketToken");
        require(
            getAddressOrRevert(buildBasketTokenName(deployment.name)) == basketToken,
            "Failed to save BasketToken deployment"
        );
        require(BasketToken(basketToken).bitFlag() == deployment.bitFlag, "Failed to set bitFlag in BasketToken");
        assertEq(
            BasketManager(basketManager).basketAssets(basketToken),
            AssetRegistry(getAddressOrRevert(buildAssetRegistryName())).getAssets(deployment.bitFlag),
            "Failed to set basket assets in BasketManager"
        );
        // Set approvals for the BasicRetryOperator
        BasicRetryOperator basicRetryOperator = BasicRetryOperator(getAddressOrRevert(buildBasicRetryOperatorName()));
        if (shouldBroadcast) {
            vm.broadcast();
        }
        basicRetryOperator.approveDeposits(BasketToken(basketToken), type(uint256).max);
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
            getAddressOrRevert(buildEulerRouterName()),
            getAddressOrRevert(buildStrategyRegistryName()),
            getAddressOrRevert(buildAssetRegistryName()),
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
        bytes memory constructorArgs =
            abi.encode(COVE_DEPLOYER_ADDRESS, getAddressOrRevert(buildBasketManagerName()), treasury);
        // Deploy FeeCollector contract using CREATE3
        bytes memory creationBytecode = abi.encodePacked(type(FeeCollector).creationCode, constructorArgs);
        if (shouldBroadcast) {
            vm.broadcast();
        }
        feeCollector = address(factory.deploy(feeCollectorSalt, creationBytecode));
        deployer.save(
            buildFeeCollectorName(), feeCollector, "FeeCollector.sol:FeeCollector", constructorArgs, creationBytecode
        );
        require(getAddressOrRevert(buildFeeCollectorName()) == feeCollector, "Failed to save FeeCollector deployment");
    }

    // Deploys cow swap adapter, sets it as the token swap adapter in BasketManager
    function _deployAndSetCowSwapAdapter()
        internal
        onlyIfMissing(buildCowSwapAdapterName())
        returns (address cowSwapAdapter)
    {
        address cowSwapCloneImplementation = address(
            deployer.deploy_CoWSwapClone(buildCoWSwapCloneImplementationName())
        );
        cowSwapAdapter = address(deployer.deploy_CoWSwapAdapter(buildCowSwapAdapterName(), cowSwapCloneImplementation));
        address basketManager = getAddressOrRevert(buildBasketManagerName());
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
                getAddressOrRevert(buildBasketManagerName())
            )
        );
        ManagedWeightStrategy mwStrategy = ManagedWeightStrategy(strategy);
        if (shouldBroadcast) {
            vm.startBroadcast();
        }
        mwStrategy.grantRole(MANAGER_ROLE, externalManager);
        StrategyRegistry(getAddressOrRevert(buildStrategyRegistryName())).grantRole(_WEIGHT_STRATEGY_ROLE, strategy);
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
        AssetRegistry assetRegistry = AssetRegistry(getAddressOrRevert(buildAssetRegistryName()));
        if (assetRegistry.getAssetStatus(asset) != AssetRegistry.AssetStatus.DISABLED) {
            return;
        }
        if (shouldBroadcast) {
            vm.broadcast();
        }
        assetRegistry.addAsset(asset);
    }

    function _finalizeRegistryAdditions() internal {
        // First check if any registry names already exist in the master registry
        address registry = getAddressOrRevert(buildMasterRegistryName());
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

        if (multicallData.length > 0) {
            if (shouldBroadcast) {
                vm.broadcast();
            }
            Multicall(registry).multicall(multicallData);
        }
    }

    // First deploys a pyth oracle and chainlink oracle. Then Deploys an anchored oracle using the two privously
    // deployed oracles.
    // Enable the anchored oracle for the given asset and USD
    function _deployDefaultAnchoredOracleForAsset(address asset, OracleOptions memory oracleOptions) internal {
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
        // Register the asset/USD anchored oracle if it's not already registered
        _registerAnchoredOracleWithEulerRouter(asset, anchoredOracle);
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
        // Register the asset/USD anchored oracle if it's not already registered
        _registerAnchoredOracleWithEulerRouter(asset, anchoredOracle);
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
        uint256 baseAssetIndex,
        uint256 crossAssetIndex,
        OracleOptions memory quoteOracleOptions
    )
        internal
    {
        // Deploy CurveEMA Oracle
        require(
            ICurvePool(pool).coins(baseAssetIndex) == base && ICurvePool(pool).coins(crossAssetIndex) == crossAsset,
            "Incorrect set of base and cross asset indices"
        );
        require(baseAssetIndex == 0 || crossAssetIndex == 0, "One of the base or cross asset indices must be 0");

        address curveBase;
        address curveQuote;
        uint256 priceOracleIndex;
        if (baseAssetIndex == 0) {
            curveQuote = base;
            curveBase = crossAsset;
            priceOracleIndex = crossAssetIndex - 1;
        } else {
            curveQuote = crossAsset;
            curveBase = base;
            priceOracleIndex = baseAssetIndex - 1;
        }
        address curveEMAOracle = address(
            deployer.deploy_CurveEMAOracle(
                buildCurveEMAOracleName(curveBase, curveQuote), curveBase, pool, priceOracleIndex
            )
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
                buildCrossAdapterName(base, crossAsset, USD, "CurveEMA", "Chainlink"),
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
        // Register the asset/USD anchored oracle using EulerRouter if it's not already registered
        _registerAnchoredOracleWithEulerRouter(base, anchoredOracle);
    }

    function _deployAnchoredOracleWith4626ForAsset(
        address asset,
        bool shouldChain4626ForPyth,
        bool shouldChain4626ForChainlink,
        OracleOptions memory oracleOptions
    )
        internal
    {
        address primaryOracle;
        address underlyingAsset = IERC4626(asset).asset();
        if (shouldChain4626ForPyth) {
            address pythOracle = address(
                deployer.deploy_PythOracle(
                    buildPythOracleName(underlyingAsset, USD),
                    PYTH,
                    underlyingAsset,
                    USD,
                    oracleOptions.pythPriceFeed,
                    oracleOptions.pythMaxStaleness,
                    oracleOptions.pythMaxConfWidth
                )
            );
            address erc4626Oracle =
                address(deployer.deploy_ERC4626Oracle(buildERC4626OracleName(asset, underlyingAsset), IERC4626(asset)));
            primaryOracle = address(
                deployer.deploy_CrossAdapter(
                    buildCrossAdapterName(asset, underlyingAsset, USD, "4626", "Pyth"),
                    asset,
                    underlyingAsset,
                    USD,
                    erc4626Oracle,
                    pythOracle
                )
            );
        } else {
            primaryOracle = address(
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
        }

        address anchorOracle;
        if (shouldChain4626ForChainlink) {
            address chainlinkOracle = address(
                deployer.deploy_ChainlinkOracle(
                    buildChainlinkOracleName(underlyingAsset, USD),
                    underlyingAsset,
                    USD,
                    oracleOptions.chainlinkPriceFeed,
                    oracleOptions.chainlinkMaxStaleness
                )
            );
            address erc4626Oracle =
                address(deployer.deploy_ERC4626Oracle(buildERC4626OracleName(asset, underlyingAsset), IERC4626(asset)));
            anchorOracle = address(
                deployer.deploy_CrossAdapter(
                    buildCrossAdapterName(asset, underlyingAsset, USD, "4626", "Chainlink"),
                    asset,
                    underlyingAsset,
                    USD,
                    erc4626Oracle,
                    chainlinkOracle
                )
            );
        } else {
            anchorOracle = address(
                deployer.deploy_ChainlinkOracle(
                    buildChainlinkOracleName(asset, USD),
                    asset,
                    USD,
                    oracleOptions.chainlinkPriceFeed,
                    oracleOptions.chainlinkMaxStaleness
                )
            );
        }

        address anchoredOracle = address(
            deployer.deploy_AnchoredOracle(
                buildAnchoredOracleName(asset, USD), primaryOracle, anchorOracle, oracleOptions.maxDivergence
            )
        );
        // Register the asset/USD anchored oracle using EulerRouter if it's not already registered
        _registerAnchoredOracleWithEulerRouter(asset, anchoredOracle);
    }

    /// @notice Deploys an anchored oracle with a 4626 vault and a CurveEMA oracle for assets that need to be priced
    /// through a curve pool
    /// @dev This function supports pricing paths like:
    /// primary: sfrxUSD -(4626)-> frxUSD -(pyth) -> USD
    /// anchor: sfrxUSD -(4626)-> frxUSD -(curve ema)-> USDE -(chainlink) -> USD
    /// @param asset The ERC4626 vault asset to price (e.g., sfrxUSD)
    /// @param curvePool The Curve pool containing the underlying asset and cross asset
    /// @param crossAsset The asset to cross-price through (e.g., USDE)
    /// @param baseAssetIndex Index of underlying asset in curve pool coins array
    /// @param crossAssetIndex Index of cross asset in curve pool coins array
    /// @param oracleOptions Options for crossAsset/USD price feeds
    function _deployAnchoredOracleWith4626CurveEMAOracleUnderlying(
        address asset, // e.g., sfrxUSD (ERC4626)
        address curvePool, // Pool containing underlyingAsset and crossAsset
        address crossAsset, // e.g., USDE
        uint256 baseAssetIndex, // Index of underlyingAsset in curve pool coins array
        uint256 crossAssetIndex, // Index of crossAsset in curve pool coins array
        OracleOptions memory oracleOptions // Options for crossAsset/USD feeds
    )
        internal
    {
        // --- 1. Get Underlying Asset ---
        address underlyingAsset = IERC4626(asset).asset(); // e.g., frxUSD

        // --- 2. Deploy Individual Oracles ---
        // 2a. ERC4626 Oracle (asset -> underlyingAsset)
        address erc4626Oracle =
            address(deployer.deploy_ERC4626Oracle(buildERC4626OracleName(asset, underlyingAsset), IERC4626(asset)));

        // 2b. CurveEMA Oracle (underlyingAsset -> crossAsset)
        address curveBase;
        address curveQuote;
        uint256 priceOracleIndex;
        if (baseAssetIndex == 0) {
            // underlyingAsset is index 0
            curveQuote = underlyingAsset;
            curveBase = crossAsset;
            priceOracleIndex = crossAssetIndex - 1;
        } else {
            // crossAsset is index 0
            curveQuote = crossAsset;
            curveBase = underlyingAsset;
            priceOracleIndex = baseAssetIndex - 1;
        }
        address curveEMAOracle = address(
            deployer.deploy_CurveEMAOracleUnderlying(
                buildCurveEMAOracleUnderlyingName(curveBase, curveQuote),
                curvePool,
                curveBase,
                curveQuote,
                priceOracleIndex,
                true, // isBaseUnderlying
                true // isQuoteUnderlying
            )
        );

        // 2c. Pyth Oracle (underlyingAsset -> USD)
        address pythOracleUnderlyingUSD = address(
            deployer.deploy_PythOracle(
                buildPythOracleName(underlyingAsset, USD),
                PYTH,
                underlyingAsset,
                USD,
                oracleOptions.pythPriceFeed,
                oracleOptions.pythMaxStaleness,
                oracleOptions.pythMaxConfWidth
            )
        );

        // 2d. Chainlink Oracle (crossAsset -> USD)
        address chainlinkOracleCrossUSD = address(
            deployer.deploy_ChainlinkOracle(
                buildChainlinkOracleName(crossAsset, USD),
                crossAsset,
                USD,
                oracleOptions.chainlinkPriceFeed,
                oracleOptions.chainlinkMaxStaleness
            )
        );

        // --- 3. Deploy Intermediate Cross Adapter (asset -> crossAsset) ---
        address assetToCrossAssetAdapter = address(
            deployer.deploy_CrossAdapter(
                buildCrossAdapterName(asset, underlyingAsset, crossAsset, "4626", "CurveEMAUnderlying"),
                asset,
                underlyingAsset,
                crossAsset,
                erc4626Oracle,
                curveEMAOracle
            )
        );

        // --- 4. Deploy Final Cross Adapters (asset -> USD) ---

        // 4a. Primary: asset -(4626)-> underlyingAsset -(pyth)-> USD
        address primaryCrossAdapter = address(
            deployer.deploy_CrossAdapter(
                buildCrossAdapterName(asset, underlyingAsset, USD, "4626", "Pyth"),
                asset,
                underlyingAsset,
                USD,
                erc4626Oracle,
                pythOracleUnderlyingUSD
            )
        );

        // 4b. Anchor: asset -(4626)-> underlyingAsset -(curve ema)-> crossAsset -(chainlink)-> USD
        address anchorCrossAdapter = address(
            deployer.deploy_CrossAdapter(
                buildCrossAdapterName(asset, crossAsset, USD, "CrossAdapter", "Chainlink"),
                asset,
                crossAsset,
                USD,
                assetToCrossAssetAdapter,
                chainlinkOracleCrossUSD
            )
        );

        // --- 5. Deploy Anchored Oracle (asset -> USD) ---
        address anchoredOracle = address(
            deployer.deploy_AnchoredOracle(
                buildAnchoredOracleName(asset, USD),
                primaryCrossAdapter,
                anchorCrossAdapter,
                oracleOptions.maxDivergence
            )
        );

        // --- 6. Register the final oracle ---
        _registerAnchoredOracleWithEulerRouter(asset, anchoredOracle);
    }

    /// @notice Registers an anchored oracle for an asset/USD pair with the EulerRouter if it's not already registered
    function _registerAnchoredOracleWithEulerRouter(address asset, address oracle) internal {
        EulerRouter eulerRouter = EulerRouter(getAddressOrRevert(buildEulerRouterName()));
        address configuredOracle = eulerRouter.getConfiguredOracle(asset, USD);
        console.log("Previously configured oracle for %s/USD: %s", asset, configuredOracle);
        if (configuredOracle != oracle) {
            console.log("Registering anchored oracle for %s/USD with oracle %s", asset, oracle);
            if (eulerRouter.governor() == COVE_DEPLOYER_ADDRESS) {
                if (shouldBroadcast) {
                    vm.broadcast();
                }
                eulerRouter.govSetConfig(asset, USD, oracle);
            } else {
                console.log(
                    "Pranking eulerRouter governor %s to register anchored oracle for %s/USD with oracle %s",
                    eulerRouter.governor(),
                    asset,
                    oracle
                );
                vm.prank(eulerRouter.governor());
                eulerRouter.govSetConfig(asset, USD, oracle);
            }
        } else {
            console.log("Anchored oracle for %s/USD already registered correctly", asset);
        }
    }

    // Performs calls to grant permissions once deployment is successful
    function _cleanPermissions() internal {
        if (shouldBroadcast) {
            vm.startBroadcast();
        }
        // AssetRegistry
        AssetRegistry assetRegistry = AssetRegistry(getAddressOrRevert(buildAssetRegistryName()));
        if (assetRegistry.hasRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS)) {
            if (assetRegistry.hasRole(MANAGER_ROLE, COVE_DEPLOYER_ADDRESS)) {
                assetRegistry.grantRole(MANAGER_ROLE, manager);
                assetRegistry.revokeRole(MANAGER_ROLE, COVE_DEPLOYER_ADDRESS);
            }
            assetRegistry.grantRole(DEFAULT_ADMIN_ROLE, admin);
            assetRegistry.revokeRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS);
        }

        // StrategyRegistry
        StrategyRegistry strategyRegistry = StrategyRegistry(getAddressOrRevert(buildStrategyRegistryName()));
        if (strategyRegistry.hasRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS)) {
            strategyRegistry.grantRole(DEFAULT_ADMIN_ROLE, admin);
            strategyRegistry.revokeRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS);
        }

        // EulerRouter
        EulerRouter eulerRouter = EulerRouter(getAddressOrRevert(buildEulerRouterName()));
        if (eulerRouter.governor() == COVE_DEPLOYER_ADDRESS) {
            eulerRouter.transferGovernance(admin);
        }

        // BasketManager
        BasketManager bm = BasketManager(getAddressOrRevert(buildBasketManagerName()));
        if (bm.hasRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS)) {
            bm.grantRole(MANAGER_ROLE, manager);
            bm.grantRole(REBALANCE_PROPOSER_ROLE, rebalanceProposer);
            bm.grantRole(TOKENSWAP_PROPOSER_ROLE, tokenSwapProposer);
            bm.grantRole(TOKENSWAP_EXECUTOR_ROLE, tokenSwapExecutor);
            bm.grantRole(TIMELOCK_ROLE, timelock);
            bm.grantRole(PAUSER_ROLE, pauser);
            bm.grantRole(PAUSER_ROLE, admin);
            bm.grantRole(PAUSER_ROLE, manager);
            bm.grantRole(PAUSER_ROLE, COVE_DEPLOYER_ADDRESS);
            bm.grantRole(DEFAULT_ADMIN_ROLE, admin);
            bm.revokeRole(MANAGER_ROLE, COVE_DEPLOYER_ADDRESS);
            bm.revokeRole(TIMELOCK_ROLE, COVE_DEPLOYER_ADDRESS);
            bm.revokeRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS);
        }

        // FarmingPluginFactory
        FarmingPluginFactory farmingPluginFactory =
            FarmingPluginFactory(getAddressOrRevert(buildFarmingPluginFactoryName()));
        if (farmingPluginFactory.hasRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS)) {
            farmingPluginFactory.grantRole(DEFAULT_ADMIN_ROLE, admin);
            farmingPluginFactory.grantRole(MANAGER_ROLE, manager);
            if (farmingPluginFactory.hasRole(MANAGER_ROLE, COVE_DEPLOYER_ADDRESS)) {
                farmingPluginFactory.revokeRole(MANAGER_ROLE, COVE_DEPLOYER_ADDRESS);
            }
            farmingPluginFactory.revokeRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS);
        }

        // BasicRetryOperator
        BasicRetryOperator basicRetryOperator = BasicRetryOperator(getAddressOrRevert(buildBasicRetryOperatorName()));
        if (basicRetryOperator.hasRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS)) {
            basicRetryOperator.grantRole(DEFAULT_ADMIN_ROLE, admin);
            basicRetryOperator.grantRole(MANAGER_ROLE, manager);
            if (basicRetryOperator.hasRole(MANAGER_ROLE, COVE_DEPLOYER_ADDRESS)) {
                basicRetryOperator.revokeRole(MANAGER_ROLE, COVE_DEPLOYER_ADDRESS);
            }
            basicRetryOperator.revokeRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS);
        }

        // FeeCollector
        FeeCollector feeCollector = FeeCollector(getAddressOrRevert(buildFeeCollectorName()));
        if (feeCollector.hasRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS)) {
            feeCollector.grantRole(DEFAULT_ADMIN_ROLE, admin);
            feeCollector.revokeRole(DEFAULT_ADMIN_ROLE, COVE_DEPLOYER_ADDRESS);
        }

        if (shouldBroadcast) {
            vm.stopBroadcast();
        }

        _cleanPermissionsExtra();
    }

    // solhint-disable-next-line no-empty-blocks
    function _cleanPermissionsExtra() internal virtual { }

    /// @notice Deploys an anchored oracle using ChainedERC4626Oracle for a chain of ERC4626 vaults
    /// @param initialVault The starting ERC4626 vault in the chain
    /// @param targetAsset The final underlying asset to reach
    /// @param oracleOptions Oracle configuration options for the target asset/USD pair
    function _deployAnchoredOracleWithChainedERC4626(
        address initialVault,
        address targetAsset,
        OracleOptions memory oracleOptions
    )
        internal
    {
        // Deploy ChainedERC4626Oracle for price conversion through the vault chain
        address chainedERC4626Oracle = address(
            deployer.deploy_ChainedERC4626Oracle(
                buildChainedERC4626OracleName(initialVault, targetAsset), IERC4626(initialVault), targetAsset
            )
        );

        // Deploy Pyth oracle for target asset/USD price
        address pythOracle = address(
            deployer.deploy_PythOracle(
                buildPythOracleName(targetAsset, USD),
                PYTH,
                targetAsset,
                USD,
                oracleOptions.pythPriceFeed,
                oracleOptions.pythMaxStaleness,
                oracleOptions.pythMaxConfWidth
            )
        );

        // Deploy Chainlink oracle for target asset/USD price
        address chainlinkOracle = address(
            deployer.deploy_ChainlinkOracle(
                buildChainlinkOracleName(targetAsset, USD),
                targetAsset,
                USD,
                oracleOptions.chainlinkPriceFeed,
                oracleOptions.chainlinkMaxStaleness
            )
        );

        // Deploy Cross Adapters for both oracle combinations
        address primaryCrossAdapter = address(
            deployer.deploy_CrossAdapter(
                buildCrossAdapterName(initialVault, targetAsset, USD, "ChainedERC4626", "Pyth"),
                initialVault,
                targetAsset,
                USD,
                chainedERC4626Oracle,
                pythOracle
            )
        );

        address anchorCrossAdapter = address(
            deployer.deploy_CrossAdapter(
                buildCrossAdapterName(initialVault, targetAsset, USD, "ChainedERC4626", "Chainlink"),
                initialVault,
                targetAsset,
                USD,
                chainedERC4626Oracle,
                chainlinkOracle
            )
        );

        // Deploy Anchored Oracle combining both cross adapters
        address anchoredOracle = address(
            deployer.deploy_AnchoredOracle(
                buildAnchoredOracleName(initialVault, USD),
                primaryCrossAdapter,
                anchorCrossAdapter,
                oracleOptions.maxDivergence
            )
        );

        // Register the vault/USD anchored oracle using EulerRouter
        _registerAnchoredOracleWithEulerRouter(initialVault, anchoredOracle);
    }

    function _deployFarmingPluginFactory() internal returns (address) {
        address farmingPluginFactory = address(
            deployer.deploy_FarmingPluginFactory(
                buildFarmingPluginFactoryName(), COVE_DEPLOYER_ADDRESS, COVE_DEPLOYER_ADDRESS, admin
            )
        );
        return farmingPluginFactory;
    }

    function _deployPluginsViaFactory() internal virtual {
        address farmingPluginFactory = getAddressOrRevert(buildFarmingPluginFactoryName());
        address basketManager = getAddressOrRevert(buildBasketManagerName());
        address[] memory basketTokens = BasketManager(basketManager).basketTokens();
        for (uint256 i = 0; i < basketTokens.length; i++) {
            address basketToken = basketTokens[i];
            // check if plugin already exists
            address plugin = FarmingPluginFactory(farmingPluginFactory)
                .computePluginAddress(IERC20Plugins(basketToken), IERC20(rewardToken));
            // check for contract size
            uint256 codeSize;
            assembly {
                codeSize := extcodesize(plugin)
            }
            if (codeSize == 0) {
                if (shouldBroadcast) {
                    vm.broadcast();
                }
                plugin = FarmingPluginFactory(farmingPluginFactory)
                    .deployFarmingPluginWithDefaultOwner(IERC20Plugins(basketToken), IERC20(rewardToken));
            }
            deployer.save(buildFarmingPluginName(basketToken, rewardToken), plugin, "FarmingPlugin.sol:FarmingPlugin");
        }
    }

    function assetsToBitFlag(address[] memory assets) public view returns (uint256 bitFlag) {
        return AssetRegistry(getAddressOrRevert(buildAssetRegistryName())).getAssetsBitFlag(assets);
    }

    function _buildPrefix() internal view virtual override returns (string memory) {
        return "DEFAULT_";
    }
}
