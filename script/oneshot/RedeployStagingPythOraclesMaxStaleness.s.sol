// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";
import { console } from "forge-std/console.sol";

import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";

import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";
import { CustomDeployerFunctions } from "script/utils/CustomDeployerFunctions.sol";

import { VerifyStates_Staging } from "script/verify/VerifyStates_Staging.s.sol";
import { AnchoredOracle } from "src/oracles/AnchoredOracle.sol";
import { Constants } from "test/utils/Constants.t.sol";

/**
 * @title RedeployStagingPythOraclesMaxStalenes
 * @notice Script to redeploy the pyth oracles for staging environment and increase max staleness to 60 seconds
 */
contract RedeployStagingPythOraclesMaxStalenes is
    DeployScript,
    Constants,
    StdAssertions,
    BatchScript,
    BuildDeploymentJsonNames
{
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    // Oracle configuration parameters
    uint256 public constant MAX_DIVERGENCE = 0.005e18; // 0.5%
    uint256 public constant MAX_STALENESS = 60 seconds;
    uint256 public constant MAX_CONF_WIDTH = 50; //0.5%

    address public governor;

    address public safe = COVE_STAGING_COMMUNITY_MULTISIG;

    address[] public assets;

    function _buildPrefix() internal view override returns (string memory) {
        return "Staging_";
    }

    function deploy() public isBatch(safe) {
        deployer.setAutoBroadcast(true);

        assets = new address[](5);
        assets[0] = ETH_USDC;
        assets[1] = ETH_SUPERUSDC;
        assets[2] = ETH_SUSDE;
        assets[3] = ETH_SFRXUSD;
        assets[4] = ETH_YSYG_YVUSDS_1;

        // Print current configuration
        _printCurrentConfiguration(assets);

        // 0. USD
        // Primary: USDC --(Pyth)--> USD
        // Anchor: USDC --(Chainlink)--> USD
        _deployUSDCOracle();
        // 1. SUPERUSDC
        // Primary: SUPERUSDC-->(4626)--> USDC-->(Pyth)--> USD
        // Anchor: SUPERUSDC-->(4626)--> USDC-->(Chainlink)--> USD
        _deploySUPERUSDCOracle();
        // 2. sUSDe
        // Primary: sUSDe --(Pyth)--> USD
        // Anchor: sUSDe --(4626)--> USDe --(Chainlink)--> USD
        _deploySUSDEOracle();
        // 3. sfrxUSD
        // Primary: sfrxUSD --(4626)--> frxUSD --(Pyth)--> USD
        // Anchor: sfrxUSD --(4626)--> frxUSD --(CurveEMA)--> USDE --(Chainlink)--> USD
        _deploySFRXUSDOracle();
        // 4. ysyG-yvUSDS-1
        // Primary: ysyG-yvUSDS-1 --(ChainedERC4626)--> USDS --(Pyth)--> USD
        // Anchor: ysyG-yvUSDS-1 --(ChainedERC4626)--> USDS --(Chainlink)--> USD
        _deployYSYG_YVUSDSOracle();

        // Print final configuration
        console.log("\n--- Final Configuration ---");
        _printCurrentConfiguration(assets);

        (new VerifyStates_Staging()).verifyDeployment();

        // executeBatch(false);
    }

    function _printCurrentConfiguration(address[] memory assets_) private {
        EulerRouter router = EulerRouter(deployer.getAddress(buildEulerRouterName()));

        console.log("--- Current EulerRouter Configuration ---");
        console.log("EulerRouter address:", address(router));
        governor = router.governor();
        console.log("Governor:", governor);

        // Check configured oracles
        console.log("\n--- Configured Oracles ---");
        for (uint256 i = 0; i < assets_.length; i++) {
            address asset = assets_[i];
            string memory assetSymbol = IERC20Metadata(asset).symbol();
            address currentAnchoredOracle = router.getConfiguredOracle(asset, USD);
            address primaryOracle = AnchoredOracle(currentAnchoredOracle).primaryOracle();
            address anchorOracle = AnchoredOracle(currentAnchoredOracle).anchorOracle();

            console.log(
                string.concat(
                    assetSymbol,
                    "/USD\nCurrent Anchored Oracle: ",
                    vm.toString(currentAnchoredOracle),
                    "\nPrimary Oracle: ",
                    vm.toString(primaryOracle),
                    "\nAnchor Oracle: ",
                    vm.toString(anchorOracle),
                    "\n"
                )
            );
        }
    }

    function _deployUSDCOracle() private {
        EulerRouter router = EulerRouter(deployer.getAddress(buildEulerRouterName()));
        address currentAnchoredOracle = router.getConfiguredOracle(ETH_USDC, USD);
        address currentAnchorOracle = AnchoredOracle(currentAnchoredOracle).anchorOracle();

        // Deploy new pyth primary oracles
        address newPrimaryOracle = address(
            deployer.deploy_PythOracle(
                buildPythOracleName(ETH_USDC, USD),
                PYTH,
                ETH_USDC,
                USD,
                PYTH_USDC_USD_FEED,
                MAX_STALENESS,
                MAX_CONF_WIDTH
            )
        );

        // Deploy anchored oracle
        address newAnchoredOracle = address(
            deployer.deploy_AnchoredOracle(
                buildAnchoredOracleName(ETH_USDC, USD), newPrimaryOracle, currentAnchorOracle, MAX_DIVERGENCE
            )
        );
        addToBatch(
            address(router),
            0,
            abi.encodeWithSelector(EulerRouter.govSetConfig.selector, ETH_USDC, USD, newAnchoredOracle)
        );
    }

    function _deploySUPERUSDCOracle() private {
        EulerRouter router = EulerRouter(deployer.getAddress(buildEulerRouterName()));
        address currentAnchoredOracle = router.getConfiguredOracle(ETH_SUPERUSDC, USD);
        address currentAnchorOracle = AnchoredOracle(currentAnchoredOracle).anchorOracle();

        address underlyingAsset = IERC4626(ETH_SUPERUSDC).asset();
        address underlyingPythOracle = address(
            deployer.deploy_PythOracle(
                buildPythOracleName(underlyingAsset, USD),
                PYTH,
                underlyingAsset,
                USD,
                PYTH_USDC_USD_FEED,
                MAX_STALENESS,
                MAX_CONF_WIDTH
            )
        );
        address erc4626Oracle = deployer.getAddress(buildERC4626OracleName(ETH_SUPERUSDC, underlyingAsset));
        address newPrimaryOracle = address(
            deployer.deploy_CrossAdapter(
                buildCrossAdapterName(ETH_SUPERUSDC, underlyingAsset, USD, "4626", "Pyth"),
                ETH_SUPERUSDC,
                underlyingAsset,
                USD,
                erc4626Oracle,
                underlyingPythOracle
            )
        );
        // Deploy anchored oracle
        address newAnchoredOracle = address(
            deployer.deploy_AnchoredOracle(
                buildAnchoredOracleName(ETH_SUPERUSDC, USD), newPrimaryOracle, currentAnchorOracle, MAX_DIVERGENCE
            )
        );
        addToBatch(
            address(router),
            0,
            abi.encodeWithSelector(EulerRouter.govSetConfig.selector, ETH_SUPERUSDC, USD, newAnchoredOracle)
        );
    }

    function _deploySUSDEOracle() private {
        EulerRouter router = EulerRouter(deployer.getAddress(buildEulerRouterName()));
        address currentAnchoredOracle = router.getConfiguredOracle(ETH_SUSDE, USD);
        address currentAnchorOracle = AnchoredOracle(currentAnchoredOracle).anchorOracle();

        // Deploy new pyth primary oracles
        address newPrimaryOracle = address(
            deployer.deploy_PythOracle(
                buildPythOracleName(ETH_SUSDE, USD),
                PYTH,
                ETH_SUSDE,
                USD,
                PYTH_SUSDE_USD_FEED,
                MAX_STALENESS,
                MAX_CONF_WIDTH
            )
        );

        // Deploy anchored oracle
        address newAnchoredOracle = address(
            deployer.deploy_AnchoredOracle(
                buildAnchoredOracleName(ETH_SUSDE, USD), newPrimaryOracle, currentAnchorOracle, MAX_DIVERGENCE
            )
        );
        addToBatch(
            address(router),
            0,
            abi.encodeWithSelector(EulerRouter.govSetConfig.selector, ETH_SUSDE, USD, newAnchoredOracle)
        );
    }

    function _deploySFRXUSDOracle() private {
        EulerRouter router = EulerRouter(deployer.getAddress(buildEulerRouterName()));
        address currentAnchoredOracle = router.getConfiguredOracle(ETH_SFRXUSD, USD);
        address currentAnchorOracle = AnchoredOracle(currentAnchoredOracle).anchorOracle();

        address underlyingAsset = IERC4626(ETH_SFRXUSD).asset();
        address underlyingPythOracle = address(
            deployer.deploy_PythOracle(
                buildPythOracleName(underlyingAsset, USD),
                PYTH,
                underlyingAsset,
                USD,
                PYTH_FRXUSD_USD_FEED,
                MAX_STALENESS,
                MAX_CONF_WIDTH
            )
        );
        address erc4626Oracle = deployer.getAddress(buildERC4626OracleName(ETH_SFRXUSD, underlyingAsset));
        address newPrimaryOracle = address(
            deployer.deploy_CrossAdapter(
                buildCrossAdapterName(ETH_SFRXUSD, underlyingAsset, USD, "4626", "Pyth"),
                ETH_SFRXUSD,
                underlyingAsset,
                USD,
                erc4626Oracle,
                underlyingPythOracle
            )
        );
        // Deploy anchored oracle
        address newAnchoredOracle = address(
            deployer.deploy_AnchoredOracle(
                buildAnchoredOracleName(ETH_SFRXUSD, USD), newPrimaryOracle, currentAnchorOracle, MAX_DIVERGENCE
            )
        );
        addToBatch(
            address(router),
            0,
            abi.encodeWithSelector(EulerRouter.govSetConfig.selector, ETH_SFRXUSD, USD, newAnchoredOracle)
        );
    }

    function _deployYSYG_YVUSDSOracle() private {
        EulerRouter router = EulerRouter(deployer.getAddress(buildEulerRouterName()));
        address currentAnchoredOracle = router.getConfiguredOracle(ETH_YSYG_YVUSDS_1, USD);
        // Anchor: ysyG-yvUSDS-1 --(ChainedERC4626)--> USDS --(Chainlink)--> USD
        address currentAnchorOracle = AnchoredOracle(currentAnchoredOracle).anchorOracle();
        // primary oracle is an anchored oracle with primary oracle as a chained erc4626 oracle
        // and pyth and as the anchor
        address initialVault = ETH_YSYG_YVUSDS_1;
        address targetAsset = ETH_USDS;
        address currentChainedOracle =
            address(deployer.getAddress(buildChainedERC4626OracleName(initialVault, targetAsset)));
        address newPythOracle = address(
            deployer.deploy_PythOracle(
                buildPythOracleName(targetAsset, USD),
                PYTH,
                targetAsset,
                USD,
                PYTH_USDS_USD_FEED,
                MAX_STALENESS,
                MAX_CONF_WIDTH
            )
        );

        address newPrimaryCrossAdapter = address(
            deployer.deploy_CrossAdapter(
                buildCrossAdapterName(initialVault, targetAsset, USD, "ChainedERC4626", "Pyth"),
                initialVault,
                targetAsset,
                USD,
                currentChainedOracle,
                newPythOracle
            )
        );
        // Deploy anchored oracle
        address newAnchoredOracle = address(
            deployer.deploy_AnchoredOracle(
                buildAnchoredOracleName(ETH_YSYG_YVUSDS_1, USD),
                newPrimaryCrossAdapter,
                currentAnchorOracle,
                MAX_DIVERGENCE
            )
        );
        addToBatch(
            address(router),
            0,
            abi.encodeWithSelector(EulerRouter.govSetConfig.selector, ETH_YSYG_YVUSDS_1, USD, newAnchoredOracle)
        );
    }
}
