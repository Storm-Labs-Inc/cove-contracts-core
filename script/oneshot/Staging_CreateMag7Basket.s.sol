// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";
import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { VmSafe } from "forge-std/Vm.sol";

import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { FeeCollector } from "src/FeeCollector.sol";
import { AnchoredOracle } from "src/oracles/AnchoredOracle.sol";
import { ManagedWeightStrategy } from "src/strategies/ManagedWeightStrategy.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";

import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";
import { CustomDeployerFunctions } from "script/utils/CustomDeployerFunctions.sol";
import { Mag7DeploymentUtils } from "script/utils/Mag7DeploymentUtils.sol";
import { Constants } from "test/utils/Constants.t.sol";

// solhint-disable var-name-mixedcase
contract StagingCreateMag7Basket is
    DeployScript,
    Constants,
    BatchScript,
    BuildDeploymentJsonNames,
    Mag7DeploymentUtils
{
    using DeployerFunctions for Deployer;
    using CustomDeployerFunctions for Deployer;

    address public ops_safe = COVE_STAGING_OPS_MULTISIG;
    address public community_safe = COVE_STAGING_COMMUNITY_MULTISIG;

    uint256 public constant PYTH_MAX_STALENESS = 60 seconds;
    uint256 public constant PYTH_MAX_CONF_WIDTH = 50; // 0.5%
    uint256 public constant REDSTONE_MAX_STALENESS = 5 minutes;
    uint256 public constant MAG7_MAX_DIVERGENCE = 0.005e18; // 0.5%
    uint16 public constant MAG7_MANAGEMENT_FEE_BPS = 30; // 0.30%
    uint16 public constant MAG7_SPONSOR_SPLIT_BPS = 5000; // 50%

    address public mag7Strategy;
    uint256 public mag7BitFlag;
    address public mag7Basket;

    function _buildPrefix() internal pure override returns (string memory) {
        return "Staging_";
    }

    function deploy() public {
        _configure();
        communityPreBatch(false);
        encodedTxns = new bytes[](0);
        opsBatch(false);
        encodedTxns = new bytes[](0);
        communityPostBatch(false);
    }

    function communityPreBatch() public {
        communityPreBatch(true);
    }

    function communityPreBatch(bool execute_) public {
        _configure();
        address[] memory mag7Assets = _mag7EquityAssets();
        address[] memory mag7Oracles = _deployMag7Oracles(mag7Assets);
        mag7Strategy = _deployMag7Strategy();
        _buildCommunityPreBatch(mag7Assets, mag7Oracles);
        if (execute_) {
            _maybeExecuteBatch();
        }
    }

    function opsBatch() public {
        opsBatch(true);
    }

    function opsBatch(bool execute_) public {
        _configure();
        mag7Strategy = _deployMag7Strategy();
        _buildOpsBatch();
        if (execute_) {
            _maybeExecuteBatch();
        }
    }

    function communityPostBatch() public {
        communityPostBatch(true);
    }

    function communityPostBatch(bool execute_) public {
        _configure();
        _buildCommunityPostBatch();
        if (execute_) {
            _maybeExecuteBatch();
        }
    }

    function _buildCommunityPreBatch(
        address[] memory mag7Assets,
        address[] memory mag7Oracles
    )
        internal
        isBatch(community_safe)
    {
        StrategyRegistry strategyRegistry = StrategyRegistry(deployer.getAddress(buildStrategyRegistryName()));
        addToBatch(
            address(strategyRegistry),
            0,
            abi.encodeCall(strategyRegistry.grantRole, (_WEIGHT_STRATEGY_ROLE, mag7Strategy))
        );

        EulerRouter router = EulerRouter(deployer.getAddress(buildEulerRouterName()));
        for (uint256 i = 0; i < mag7Assets.length; i++) {
            addToBatch(
                address(router), 0, abi.encodeCall(EulerRouter.govSetConfig, (mag7Assets[i], USD, mag7Oracles[i]))
            );
        }

        FeeCollector feeCollector = FeeCollector(deployer.getAddress(buildFeeCollectorName()));
        addToBatch(
            address(feeCollector),
            0,
            abi.encodeCall(feeCollector.setProtocolTreasury, (COVE_STAGING_COMMUNITY_MULTISIG))
        );
    }

    function _buildOpsBatch() internal isBatch(ops_safe) {
        AssetRegistry assetRegistry = AssetRegistry(deployer.getAddress(buildAssetRegistryName()));
        address[] memory basketAssets = _mag7BasketAssets();
        for (uint256 i = 0; i < basketAssets.length; i++) {
            if (assetRegistry.getAssetStatus(basketAssets[i]) == AssetRegistry.AssetStatus.DISABLED) {
                addToBatch(address(assetRegistry), 0, abi.encodeCall(assetRegistry.addAsset, (basketAssets[i])));
            }
        }

        mag7BitFlag = assetRegistry.getAssetsBitFlag(basketAssets);

        ManagedWeightStrategy strategy = ManagedWeightStrategy(mag7Strategy);
        uint64[] memory weights = _mag7Weights();
        addToBatch(address(strategy), 0, abi.encodeCall(strategy.setTargetWeights, (mag7BitFlag, weights)));

        BasketManager basketManager = BasketManager(deployer.getAddress(buildBasketManagerName()));
        bytes memory basketData = addToBatch(
            address(basketManager),
            0,
            abi.encodeCall(BasketManager.createNewBasket, ("MAG7", "MAG7", ETH_USDC, mag7BitFlag, mag7Strategy))
        );
        mag7Basket = abi.decode(basketData, (address));
    }

    function _buildCommunityPostBatch() internal isBatch(community_safe) {
        BasketManager basketManager = BasketManager(deployer.getAddress(buildBasketManagerName()));
        if (mag7Basket == address(0)) {
            mag7Basket = _findMag7Basket(basketManager);
        }
        require(mag7Basket != address(0), "MAG7 basket not found");

        FeeCollector feeCollector = FeeCollector(deployer.getAddress(buildFeeCollectorName()));
        addToBatch(address(feeCollector), 0, abi.encodeCall(feeCollector.setSponsor, (mag7Basket, SPONSOR_GAUNTLET)));
        addToBatch(
            address(feeCollector), 0, abi.encodeCall(feeCollector.setSponsorSplit, (mag7Basket, MAG7_SPONSOR_SPLIT_BPS))
        );

        TimelockController timelock = TimelockController(payable(deployer.getAddress(buildTimelockControllerName())));
        address[] memory targets = new address[](1);
        targets[0] = address(basketManager);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(basketManager.setManagementFee, (mag7Basket, MAG7_MANAGEMENT_FEE_BPS));
        uint256 delay = timelock.getMinDelay();
        addToBatch(
            address(timelock),
            0,
            abi.encodeCall(
                TimelockController.scheduleBatch, (targets, values, calldatas, bytes32(0), bytes32(0), delay)
            )
        );
    }

    function _configure() internal {
        require(msg.sender == COVE_DEPLOYER_ADDRESS, "Caller must be COVE DEPLOYER");
        deployer.setAutoBroadcast(true);
    }

    function _maybeExecuteBatch() internal {
        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            executeBatch(true);
        } else {
            executeBatch(false);
        }
    }

    function _deployMag7Strategy() internal returns (address strategyAddr) {
        string memory strategyName = "MAG7 V1";
        strategyAddr = deployer.getAddress(buildManagedWeightStrategyName(strategyName));
        if (strategyAddr == address(0)) {
            strategyAddr = address(
                deployer.deploy_ManagedWeightStrategy(
                    buildManagedWeightStrategyName(strategyName),
                    COVE_DEPLOYER_ADDRESS,
                    deployer.getAddress(buildBasketManagerName())
                )
            );
        }

        ManagedWeightStrategy strategy = ManagedWeightStrategy(strategyAddr);
        if (!strategy.hasRole(MANAGER_ROLE, ops_safe)) {
            vm.broadcast();
            strategy.grantRole(MANAGER_ROLE, ops_safe);
        }
    }

    function _deployMag7Oracles(address[] memory mag7Assets) internal returns (address[] memory mag7Oracles) {
        mag7Oracles = new address[](mag7Assets.length);
        bytes32[] memory pythFeeds = _mag7PythFeeds();
        bytes32[] memory redstoneFeeds = _mag7RedstoneFeeds();

        for (uint256 i = 0; i < mag7Assets.length; i++) {
            address asset = mag7Assets[i];
            if (_isPythOnlyAsset(asset)) {
                address existingPyth = deployer.getAddress(buildPythOracleMarketHoursName(asset, USD));
                if (existingPyth != address(0)) {
                    _assertPythOracleMarketHoursConfig(
                        existingPyth, asset, USD, pythFeeds[i], PYTH_MAX_STALENESS, PYTH_MAX_CONF_WIDTH
                    );
                    mag7Oracles[i] = existingPyth;
                    continue;
                }

                mag7Oracles[i] = address(
                    deployer.deploy_PythOracleMarketHours(
                        buildPythOracleMarketHoursName(asset, USD),
                        PYTH,
                        asset,
                        USD,
                        pythFeeds[i],
                        PYTH_MAX_STALENESS,
                        PYTH_MAX_CONF_WIDTH
                    )
                );
                _assertPythOracleMarketHoursConfig(
                    mag7Oracles[i], asset, USD, pythFeeds[i], PYTH_MAX_STALENESS, PYTH_MAX_CONF_WIDTH
                );
                continue;
            }

            address existingAnchored = deployer.getAddress(buildAnchoredOracleName(asset, USD));
            if (existingAnchored != address(0)) {
                AnchoredOracle anchored = AnchoredOracle(existingAnchored);
                address primary = anchored.primaryOracle();
                address anchor = anchored.anchorOracle();
                _assertPythOracleMarketHoursConfig(
                    primary, asset, USD, pythFeeds[i], PYTH_MAX_STALENESS, PYTH_MAX_CONF_WIDTH
                );
                _assertRedstoneCoreOracleConfig(
                    anchor, asset, USD, redstoneFeeds[i], REDSTONE_DEFAULT_FEED_DECIMALS, REDSTONE_MAX_STALENESS
                );
                _assertAnchoredOracleConfig(existingAnchored, primary, anchor, MAG7_MAX_DIVERGENCE);
                mag7Oracles[i] = existingAnchored;
                continue;
            }

            address pythOracle = address(
                deployer.deploy_PythOracleMarketHours(
                    buildPythOracleMarketHoursName(asset, USD),
                    PYTH,
                    asset,
                    USD,
                    pythFeeds[i],
                    PYTH_MAX_STALENESS,
                    PYTH_MAX_CONF_WIDTH
                )
            );
            _assertPythOracleMarketHoursConfig(
                pythOracle, asset, USD, pythFeeds[i], PYTH_MAX_STALENESS, PYTH_MAX_CONF_WIDTH
            );
            address redstoneOracle = address(
                deployer.deploy_RedstoneCoreOracle(
                    buildRedstoneCoreOracleName(asset, USD),
                    asset,
                    USD,
                    redstoneFeeds[i],
                    REDSTONE_DEFAULT_FEED_DECIMALS,
                    REDSTONE_MAX_STALENESS
                )
            );
            _assertRedstoneCoreOracleConfig(
                redstoneOracle, asset, USD, redstoneFeeds[i], REDSTONE_DEFAULT_FEED_DECIMALS, REDSTONE_MAX_STALENESS
            );
            mag7Oracles[i] = address(
                deployer.deploy_AnchoredOracle(
                    buildAnchoredOracleName(asset, USD), pythOracle, redstoneOracle, MAG7_MAX_DIVERGENCE
                )
            );
            _assertAnchoredOracleConfig(mag7Oracles[i], pythOracle, redstoneOracle, MAG7_MAX_DIVERGENCE);
        }
    }

    function _mag7EquityAssets() internal pure returns (address[] memory assets) {
        assets = new address[](7);
        assets[0] = ETH_AAPLON;
        assets[1] = ETH_MSFTON;
        assets[2] = ETH_GOOGLON;
        assets[3] = ETH_AMZNON;
        assets[4] = ETH_NVDAON;
        assets[5] = ETH_METAON;
        assets[6] = ETH_TSLAON;
    }

    function _mag7BasketAssets() internal pure returns (address[] memory assets) {
        assets = new address[](8);
        assets[0] = ETH_USDC;
        assets[1] = ETH_AAPLON;
        assets[2] = ETH_MSFTON;
        assets[3] = ETH_GOOGLON;
        assets[4] = ETH_AMZNON;
        assets[5] = ETH_NVDAON;
        assets[6] = ETH_METAON;
        assets[7] = ETH_TSLAON;
    }

    function _mag7PythFeeds() internal pure returns (bytes32[] memory feeds) {
        feeds = new bytes32[](7);
        feeds[0] = PYTH_AAPL_USD_FEED;
        feeds[1] = PYTH_MSFT_USD_FEED;
        feeds[2] = PYTH_GOOGL_USD_FEED;
        feeds[3] = PYTH_AMZN_USD_FEED;
        feeds[4] = PYTH_NVDA_USD_FEED;
        feeds[5] = PYTH_META_USD_FEED;
        feeds[6] = PYTH_TSLA_USD_FEED;
    }

    function _mag7RedstoneFeeds() internal pure returns (bytes32[] memory feeds) {
        feeds = new bytes32[](7);
        feeds[0] = REDSTONE_AAPL_USD_FEED;
        feeds[1] = REDSTONE_MSFT_USD_FEED;
        feeds[2] = REDSTONE_GOOGL_USD_FEED;
        feeds[3] = REDSTONE_AMZN_USD_FEED;
        feeds[4] = REDSTONE_NVDA_USD_FEED;
        feeds[5] = REDSTONE_META_USD_FEED;
        feeds[6] = REDSTONE_TSLA_USD_FEED;
    }

    function _mag7Weights() internal pure returns (uint64[] memory weights) {
        weights = new uint64[](8);
        weights[0] = 0;
        uint256 baseWeight = 1_000_000_000_000_000_000;
        baseWeight = baseWeight / 7;
        uint64 baseWeight64 = uint64(baseWeight);
        uint64 remainder = uint64(1e18 - baseWeight * 7);
        for (uint256 i = 1; i < 8; i++) {
            weights[i] = baseWeight64;
        }
        weights[7] = baseWeight64 + remainder;
    }

    function _findMag7Basket(BasketManager basketManager) internal view returns (address) {
        address[] memory baskets = basketManager.basketTokens();
        for (uint256 i = 0; i < baskets.length; i++) {
            if (_stringEq(BasketToken(baskets[i]).symbol(), "coveMAG7")) {
                return baskets[i];
            }
        }
        return address(0);
    }

    function _stringEq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
