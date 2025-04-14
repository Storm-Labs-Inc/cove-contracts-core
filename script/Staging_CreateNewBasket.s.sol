// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { BasketTokenDeployment, Deployments, OracleOptions } from "./Deployments.s.sol";
import { CustomDeployerFunctions } from "./utils/CustomDeployerFunctions.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { ManagedWeightStrategy } from "src/strategies/ManagedWeightStrategy.sol";

/**
 * @title Staging_RegisterOracles
 * @notice Script to update the oracles for 4626 tokens in the staging environment
 * @dev This script deploys and configures oracles for sUSDe, sDAI, and sFRAX
 */
// solhint-disable var-name-mixedcase

contract StagingCreateNewBasket is Deployments, BatchScript {
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    address public ops_safe = COVE_STAGING_OPS_MULTISIG;
    address public community_safe = COVE_STAGING_COMMUNITY_MULTISIG;

    function _buildPrefix() internal pure override returns (string memory) {
        return "Staging_";
    }

    function deploy() public override isBatch(ops_safe) {
        require(msg.sender == COVE_DEPLOYER_ADDRESS, "Caller must be COVE DEPLOYER");
        // Start the prank if not in production
        deployer.setAutoBroadcast(true);
        BasketManager basketManager = BasketManager(deployer.getAddress(buildBasketManagerName()));
        // 1. Create new basket
        // Basket assets
        address[] memory basketAssets = new address[](5);
        basketAssets[0] = ETH_USDC;
        basketAssets[1] = ETH_SUSDE;
        basketAssets[2] = ETH_SFRXUSD;
        basketAssets[3] = ETH_YSYG_YVUSDS_1;
        basketAssets[4] = ETH_SUPERUSDC;

        // Initial weights for respective basket assets
        uint64[] memory initialWeights = new uint64[](5);
        initialWeights[0] = 0;
        initialWeights[1] = 0.25e18;
        initialWeights[2] = 0.25e18;
        initialWeights[3] = 0.25e18;
        initialWeights[4] = 0.25e18;
        // Deploy managed weight strategy
        AssetRegistry assetRegistry = AssetRegistry(getAddressOrRevert(buildAssetRegistryName()));
        // vm.prank(0x8842fe65A7Db9BB5De6d50e49aF19496da09F9b5);
        assetRegistry.addAsset(ETH_SUPERUSDC);
        BasketTokenDeployment memory deployment = BasketTokenDeployment({
            name: "StablesV2",
            symbol: "stgUSD2",
            rootAsset: ETH_USDC,
            bitFlag: assetsToBitFlag(basketAssets),
            strategy: getAddressOrRevert(buildManagedWeightStrategyName("Gauntlet V1")),
            initialWeights: initialWeights
        });

        ManagedWeightStrategy strategy =
            ManagedWeightStrategy(deployer.getAddress(buildManagedWeightStrategyName("Gauntlet V1")));
        // vm.prank(0x8842fe65A7Db9BB5De6d50e49aF19496da09F9b5);
        strategy.setTargetWeights(deployment.bitFlag, deployment.initialWeights);

        // 1. Add basket creation to multisig tx
        addToBatch(
            address(basketManager),
            0,
            abi.encodeWithSelector(
                BasketManager.createNewBasket.selector,
                buildBasketTokenName(deployment.name),
                deployment.symbol,
                deployment.rootAsset,
                deployment.bitFlag,
                deployment.strategy
            )
        );
        // 1st batch for Ops multisig
        // executeBatch(false);
        // Reset encodedTxns
        encodedTxns = new bytes[](0);
        // 2nd batch for Community multisig
        _deployAndRegisterOracle();
        // executeBatch(false);
    }

    function _deployAndRegisterOracle() internal isBatch(community_safe) {
        // 2. Deploy needed oracles
        address anchoredOracle = _deployAnchoredOracleWith4626ForAssetNoRegister(
            ETH_SUPERUSDC,
            true,
            true,
            OracleOptions({
                pythPriceFeed: PYTH_USDC_USD_FEED,
                pythMaxStaleness: 30 seconds,
                pythMaxConfWidth: 50, //0.5%
                chainlinkPriceFeed: ETH_CHAINLINK_USDC_USD_FEED,
                chainlinkMaxStaleness: 1 days,
                maxDivergence: 0.005e18 // 0.5%
             })
        );

        // 3. Add anchored oracle to multisig tx
        addToBatch(
            address(deployer.getAddress(buildEulerRouterName())),
            0,
            abi.encodeWithSelector(EulerRouter.govSetConfig.selector, ETH_SUPERUSDC, USD, anchoredOracle)
        );
    }

    function _feeCollectorSalt() internal pure override returns (bytes32) {
        return keccak256(abi.encodePacked("Staging_FeeCollector_0403"));
    }

    function _deployAnchoredOracleWith4626ForAssetNoRegister(
        address asset,
        bool shouldChain4626ForPyth,
        bool shouldChain4626ForChainlink,
        OracleOptions memory oracleOptions
    )
        internal
        returns (address)
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
                address(deployer.deploy_ERC4626Oracle(buildERC4626OracleName(asset, USD), IERC4626(asset)));
            primaryOracle = address(
                deployer.deploy_CrossAdapter(
                    buildCrossAdapterName(asset, underlyingAsset, USD, "ERC4626", "Pyth"),
                    underlyingAsset,
                    asset,
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
                address(deployer.deploy_ERC4626Oracle(buildERC4626OracleName(asset, USD), IERC4626(asset)));
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
        return anchoredOracle;
    }
}
