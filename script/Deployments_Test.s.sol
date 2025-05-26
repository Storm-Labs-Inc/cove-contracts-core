// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { BasketTokenDeployment, Deployments, OracleOptions } from "./Deployments.s.sol";
import { CustomDeployerFunctions } from "./utils/CustomDeployerFunctions.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";

contract DeploymentsTest is Deployments {
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    function _buildPrefix() internal pure override returns (string memory) {
        return "Test_";
    }

    function _setPermissionedAddresses() internal virtual override {
        // Set permissioned addresses
        // Integration test deploy
        admin = COVE_OPS_MULTISIG;
        treasury = COVE_OPS_MULTISIG;
        pauser = COVE_OPS_MULTISIG;
        manager = COVE_OPS_MULTISIG;
        timelock = COVE_OPS_MULTISIG;
        rebalanceProposer = COVE_OPS_MULTISIG;
        tokenSwapProposer = COVE_OPS_MULTISIG;
        tokenSwapExecutor = COVE_OPS_MULTISIG;
        rewardToken = address(deployer.deploy_ERC20Mock(string.concat(_buildPrefix(), "CoveMockERC20")));
    }

    function _feeCollectorSalt() internal pure override returns (bytes32) {
        return keccak256(abi.encodePacked("Test_FeeCollector"));
    }

    function _deployNonCoreContracts() internal override {
        // For integration test purposes
        address[] memory basketAssets = new address[](6);
        basketAssets[0] = ETH_WETH;
        basketAssets[1] = ETH_SUSDE;
        basketAssets[2] = ETH_WEETH;
        basketAssets[3] = ETH_EZETH;
        basketAssets[4] = ETH_RSETH;
        basketAssets[5] = ETH_RETH;

        // 0. WETH
        _deployDefaultAnchoredOracleForAsset(
            ETH_WETH,
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
            OracleOptions({
                pythPriceFeed: PYTH_SUSDE_USD_FEED,
                pythMaxStaleness: 15 minutes,
                pythMaxConfWidth: 100,
                chainlinkPriceFeed: ETH_CHAINLINK_SUSDE_USD_FEED,
                chainlinkMaxStaleness: 1 days, // TODO: confirm staleness duration
                maxDivergence: 0.5e18
            })
        );
        _addAssetToAssetRegistry(ETH_SUSDE);

        // 2. weETH/ETH -> USD
        _deployChainlinkCrossAdapterForNonUSDPair(
            ETH_WEETH,
            OracleOptions({
                pythPriceFeed: PYTH_WEETH_USD_FEED,
                pythMaxStaleness: 15 minutes,
                pythMaxConfWidth: 100,
                chainlinkPriceFeed: ETH_CHAINLINK_WEETH_ETH_FEED,
                chainlinkMaxStaleness: 1 days, // TODO: confirm staleness duration
                maxDivergence: 0.5e18
            }),
            ETH,
            ETH_CHAINLINK_ETH_USD_FEED
        );
        _addAssetToAssetRegistry(ETH_WEETH);

        // 3. ezETH/ETH -> USD
        _deployChainlinkCrossAdapterForNonUSDPair(
            ETH_EZETH,
            OracleOptions({
                pythPriceFeed: PYTH_WEETH_USD_FEED, // TODO: change to ezETH feed once found
                pythMaxStaleness: 15 minutes,
                pythMaxConfWidth: 100,
                chainlinkPriceFeed: ETH_CHAINLINK_EZETH_ETH_FEED,
                chainlinkMaxStaleness: 1 days, // TODO: confirm staleness duration
                maxDivergence: 0.5e18
            }),
            ETH,
            ETH_CHAINLINK_ETH_USD_FEED
        );
        _addAssetToAssetRegistry(ETH_EZETH);

        // 4. rsETH/ETH -> USD
        _deployChainlinkCrossAdapterForNonUSDPair(
            ETH_RSETH,
            OracleOptions({
                pythPriceFeed: PYTH_WEETH_USD_FEED, // TODO: change to rsETH feed once found
                pythMaxStaleness: 15 minutes,
                pythMaxConfWidth: 100,
                chainlinkPriceFeed: ETH_CHAINLINK_RSETH_ETH_FEED,
                chainlinkMaxStaleness: 1 days, // TODO: confirm staleness duration
                maxDivergence: 0.5e18
            }),
            ETH,
            ETH_CHAINLINK_ETH_USD_FEED
        );
        _addAssetToAssetRegistry(ETH_RSETH);

        // 5. rETH/ETH -> USD
        _deployChainlinkCrossAdapterForNonUSDPair(
            ETH_RETH,
            OracleOptions({
                pythPriceFeed: PYTH_RETH_USD_FEED,
                pythMaxStaleness: 15 minutes,
                pythMaxConfWidth: 100,
                chainlinkPriceFeed: ETH_CHAINLINK_RETH_ETH_FEED,
                chainlinkMaxStaleness: 1 days, // TODO: confirm staleness duration
                maxDivergence: 0.5e18
            }),
            ETH,
            ETH_CHAINLINK_ETH_USD_FEED
        );
        _addAssetToAssetRegistry(ETH_RETH);
        // Deploy launch strategies
        _deployManagedStrategy(GAUNTLET_STRATEGIST, "Gauntlet V1"); // TODO: confirm strategy name

        uint64[] memory initialWeights = new uint64[](6); // TODO: confirm initial weights with Guantlet
        initialWeights[0] = 1e18;
        initialWeights[1] = 0;
        initialWeights[2] = 0;
        initialWeights[3] = 0;
        initialWeights[4] = 0;
        initialWeights[5] = 0;

        _setInitialWeightsAndDeployBasketToken(
            BasketTokenDeployment({
                name: "Gauntlet All Asset", // TODO: confirm basket name. Will be prefixed with "Cove "
                symbol: "gWETH", // TODO: confirm basket symbol. Will be prefixed with "cove"
                rootAsset: ETH_WETH, // TODO: confirm root asset
                bitFlag: assetsToBitFlag(basketAssets),
                strategy: getAddressOrRevert(buildManagedWeightStrategyName("Gauntlet V1")), // TODO: confirm strategy
                initialWeights: initialWeights
            })
        );
    }
}
