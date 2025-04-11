// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { CrossAdapter } from "euler-price-oracle/src/adapter/CrossAdapter.sol";
import { ChainlinkOracle } from "euler-price-oracle/src/adapter/chainlink/ChainlinkOracle.sol";
import { PythOracle } from "euler-price-oracle/src/adapter/pyth/PythOracle.sol";
import { DeployScript } from "forge-deploy/DeployScript.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";
import { console } from "forge-std/console.sol";

import { BuildDeploymentJsonNames } from "./utils/BuildDeploymentJsonNames.sol";
import { CustomDeployerFunctions } from "./utils/CustomDeployerFunctions.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { AnchoredOracle } from "src/oracles/AnchoredOracle.sol";
import { ERC4626Oracle } from "src/oracles/ERC4626Oracle.sol";
import { Constants } from "test/utils/Constants.t.sol";

/**
 * @title UpdateStagingOracles
 * @notice Script to update the oracles for 4626 tokens in the staging environment
 * @dev This script deploys and configures oracles for sUSDe, sDAI, and sFRAX
 */
// solhint-disable var-name-mixedcase
contract UpdateStagingOracles is DeployScript, Constants, StdAssertions, BatchScript, BuildDeploymentJsonNames {
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    // Staging EulerRouter address
    address public constant STAGING_EULER_ROUTER = 0xb96e038998049BA86c220Dda4048AC17E1109453;

    // Oracle configuration parameters
    uint256 public constant PYTH_MAX_STALENESS = 30 seconds;
    uint256 public constant PYTH_MAX_CONF_WIDTH = 50; // 0.5%
    uint256 public constant CHAINLINK_MAX_STALENESS = 1 days;
    uint256 public constant MAX_DIVERGENCE = 0.005e18; // 0.5%

    address public governor;

    address public safe = COVE_STAGING_COMMUNITY_MULTISIG;

    function _buildPrefix() internal view override returns (string memory) {
        return "Staging_";
    }

    function deploy() public isBatch(safe) {
        deployer.setAutoBroadcast(true);
        // Print current configuration
        _printCurrentConfiguration();

        // Deploy and configure oracles for sUSDe
        _deploySUSDEOracles();

        // Deploy and configure oracles for sDAI
        _deploySDaiOracles();

        // Deploy and configure oracles for sFRAX
        _deploySFraxOracles();

        // Print final configuration
        console.log("\n--- Final Configuration ---");
        _printCurrentConfiguration();

        // executeBatch(false);
    }

    function _printCurrentConfiguration() private {
        EulerRouter router = EulerRouter(STAGING_EULER_ROUTER);

        console.log("--- Current EulerRouter Configuration ---");
        console.log("EulerRouter address:", address(router));
        governor = router.governor();
        console.log("Governor:", governor);

        // Check if tokens are configured as resolved vaults
        console.log("\n--- Resolved Vaults ---");
        address sUSDe_asset = router.resolvedVaults(ETH_SUSDE);
        console.log("sUSDe resolved to:", sUSDe_asset);

        address sDAI_asset = router.resolvedVaults(ETH_SDAI);
        console.log("sDAI resolved to:", sDAI_asset);

        address sFRAX_asset = router.resolvedVaults(ETH_SFRAX);
        console.log("sFRAX resolved to:", sFRAX_asset);

        // Check configured oracles
        console.log("\n--- Configured Oracles ---");
        address sUSDe_oracle = router.getConfiguredOracle(ETH_SUSDE, USD);
        console.log("sUSDe/USD oracle:", sUSDe_oracle);

        address sDAI_oracle = router.getConfiguredOracle(ETH_SDAI, USD);
        console.log("sDAI/USD oracle:", sDAI_oracle);

        address sFRAX_oracle = router.getConfiguredOracle(ETH_SFRAX, USD);
        console.log("sFRAX/USD oracle:", sFRAX_oracle);
    }

    function _deploySUSDEOracles() private {
        console.log("\n--- Deploying sUSDe Oracles ---");

        // 1. Skip deploying ERC4626Oracle for sUSDe since we have both Pyth and Chainlink oracles
        // 2. Deploy PythOracle for sUSDe/USD
        PythOracle sUSDe_PythOracle = deployer.deploy_PythOracle(
            buildPythOracleName(ETH_SUSDE, USD),
            PYTH,
            ETH_SUSDE,
            USD,
            PYTH_SUSDE_USD_FEED,
            PYTH_MAX_STALENESS,
            PYTH_MAX_CONF_WIDTH
        );
        console.log("sUSDe-USD_PythOracle deployed at:", address(sUSDe_PythOracle));

        // 3. Deploy ChainlinkOracle for sUSDe/USD
        ChainlinkOracle sUSDe_ChainlinkOracle = deployer.deploy_ChainlinkOracle(
            buildChainlinkOracleName(ETH_SUSDE, USD),
            ETH_SUSDE,
            USD,
            ETH_CHAINLINK_SUSDE_USD_FEED,
            CHAINLINK_MAX_STALENESS
        );
        console.log("sUSDe-USD_ChainlinkOracle deployed at:", address(sUSDe_ChainlinkOracle));

        // 4. Deploy AnchoredOracle for USDe/USD
        AnchoredOracle sUSDe_AnchoredOracle = deployer.deploy_AnchoredOracle(
            buildAnchoredOracleName(ETH_SUSDE, USD),
            address(sUSDe_PythOracle),
            address(sUSDe_ChainlinkOracle),
            MAX_DIVERGENCE
        );
        console.log("sUSDe-USD_AnchoredOracle deployed at:", address(sUSDe_AnchoredOracle));

        // 5. Configure EulerRouter
        EulerRouter router = EulerRouter(STAGING_EULER_ROUTER);

        // Remove sUSDe as a resolved vault
        addToBatch(
            address(router), 0, abi.encodeWithSelector(EulerRouter.govSetResolvedVault.selector, ETH_SUSDE, false)
        );
        console.log("Set sUSDe as a resolved vault");

        // Set sUSDe/USD oracle
        addToBatch(
            address(router),
            0,
            abi.encodeWithSelector(EulerRouter.govSetConfig.selector, ETH_SUSDE, USD, address(sUSDe_AnchoredOracle))
        );
        console.log("Set sUSDe/USD oracle");
    }

    function _deploySDaiOracles() private {
        console.log("\n--- Deploying sDAI Oracles ---");
        // 1. Deploy ERC4626Oracle for sDAI
        ERC4626Oracle sDAI_ERC4626Oracle =
            deployer.deploy_ERC4626Oracle(buildERC4626OracleName(ETH_SDAI, ETH_DAI), IERC4626(ETH_SDAI));
        console.log("sDAI-DAI_ERC4626Oracle deployed at:", address(sDAI_ERC4626Oracle));

        // 2. Deploy PythOracle for sDAI/USD
        PythOracle sDAI_PythOracle = deployer.deploy_PythOracle(
            buildPythOracleName(ETH_SDAI, USD),
            PYTH,
            ETH_SDAI,
            USD,
            PYTH_SDAI_USD_FEED,
            PYTH_MAX_STALENESS,
            PYTH_MAX_CONF_WIDTH
        );
        console.log("sDAI-USD_PythOracle deployed at:", address(sDAI_PythOracle));

        // 3. Deploy CrossAdapter for sDAI/USD
        ChainlinkOracle dai_ChainlinkOracle = deployer.deploy_ChainlinkOracle(
            buildChainlinkOracleName(ETH_DAI, USD), ETH_DAI, USD, ETH_CHAINLINK_DAI_USD_FEED, CHAINLINK_MAX_STALENESS
        );

        CrossAdapter sDAI_CrossAdapter = deployer.deploy_CrossAdapter(
            buildCrossAdapterName(ETH_SDAI, ETH_DAI, USD, "4626", "Chainlink"),
            ETH_SDAI,
            ETH_DAI,
            USD,
            address(sDAI_ERC4626Oracle),
            address(dai_ChainlinkOracle)
        );
        console.log("sDAI-USD_CrossAdapter_4626_Chainlink deployed at:", address(sDAI_CrossAdapter));

        // 4. Deploy AnchoredOracle for sDAI/USD
        AnchoredOracle sDAI_AnchoredOracle = deployer.deploy_AnchoredOracle(
            buildAnchoredOracleName(ETH_SDAI, USD), address(sDAI_PythOracle), address(sDAI_CrossAdapter), MAX_DIVERGENCE
        );
        console.log("sDAI-USD_AnchoredOracle deployed at:", address(sDAI_AnchoredOracle));

        // 5. Configure EulerRouter
        EulerRouter router = EulerRouter(STAGING_EULER_ROUTER);

        // Remove sDAI as a resolved vault
        addToBatch(
            address(router), 0, abi.encodeWithSelector(EulerRouter.govSetResolvedVault.selector, ETH_SDAI, false)
        );
        console.log("Set sDAI as a resolved vault");

        // Set DAI/USD oracle
        addToBatch(
            address(router),
            0,
            abi.encodeWithSelector(EulerRouter.govSetConfig.selector, ETH_SDAI, USD, address(sDAI_AnchoredOracle))
        );
        console.log("Set DAI/USD oracle");
    }

    function _deploySFraxOracles() private {
        console.log("\n--- Deploying sFRAX Oracles ---");
        // 1. Deploy ERC4626Oracle for sFRAX
        ERC4626Oracle sFRAX_ERC4626Oracle =
            deployer.deploy_ERC4626Oracle(buildERC4626OracleName(ETH_SFRAX, ETH_FRAX), IERC4626(ETH_SFRAX));
        console.log("sFRAX-FRAX_ERC4626Oracle deployed at:", address(sFRAX_ERC4626Oracle));

        // 2. Deploy PythOracle for FRAX/USD
        PythOracle frax_PythOracle = deployer.deploy_PythOracle(
            buildPythOracleName(ETH_FRAX, USD),
            PYTH,
            ETH_FRAX,
            USD,
            PYTH_FRAX_USD_FEED,
            PYTH_MAX_STALENESS,
            PYTH_MAX_CONF_WIDTH
        );
        console.log("FRAX_PythOracle deployed at:", address(frax_PythOracle));

        // 3. Deploy ChainlinkOracle for FRAX/USD
        ChainlinkOracle frax_ChainlinkOracle = deployer.deploy_ChainlinkOracle(
            buildChainlinkOracleName(ETH_FRAX, USD), ETH_FRAX, USD, ETH_CHAINLINK_FRAX_USD_FEED, CHAINLINK_MAX_STALENESS
        );
        console.log("FRAX_ChainlinkOracle deployed at:", address(frax_ChainlinkOracle));

        // 4. Deploy CrossAdapters for sFRAX/USD
        CrossAdapter sFRAX_CrossAdapter_4626_Chainlink = deployer.deploy_CrossAdapter(
            buildCrossAdapterName(ETH_SFRAX, ETH_FRAX, USD, "4626", "Chainlink"),
            ETH_SFRAX,
            ETH_FRAX,
            USD,
            address(sFRAX_ERC4626Oracle),
            address(frax_ChainlinkOracle)
        );
        console.log("sFRAX-USD_CrossAdapter_4626_Chainlink deployed at:", address(sFRAX_CrossAdapter_4626_Chainlink));

        CrossAdapter sFRAX_CrossAdapter_4626_Pyth = deployer.deploy_CrossAdapter(
            buildCrossAdapterName(ETH_SFRAX, ETH_FRAX, USD, "4626", "Pyth"),
            ETH_SFRAX,
            ETH_FRAX,
            USD,
            address(sFRAX_ERC4626Oracle),
            address(frax_PythOracle)
        );
        console.log("sFRAX-USD_CrossAdapter_4626_Pyth deployed at:", address(sFRAX_CrossAdapter_4626_Pyth));

        // 5. Deploy AnchoredOracle for sFRAX/USD
        AnchoredOracle sFRAX_AnchoredOracle = deployer.deploy_AnchoredOracle(
            buildAnchoredOracleName(ETH_SFRAX, USD),
            address(sFRAX_CrossAdapter_4626_Pyth),
            address(sFRAX_CrossAdapter_4626_Chainlink),
            MAX_DIVERGENCE
        );

        // 5. Configure EulerRouter
        EulerRouter router = EulerRouter(STAGING_EULER_ROUTER);

        // Set sFRAX as a resolved vault
        addToBatch(
            address(router), 0, abi.encodeWithSelector(EulerRouter.govSetResolvedVault.selector, ETH_SFRAX, false)
        );
        console.log("Set sFRAX as a resolved vault");

        // Set FRAX/USD oracle
        addToBatch(
            address(router),
            0,
            abi.encodeWithSelector(EulerRouter.govSetConfig.selector, ETH_SFRAX, USD, address(sFRAX_AnchoredOracle))
        );
        console.log("Set FRAX/USD oracle");
    }
}
