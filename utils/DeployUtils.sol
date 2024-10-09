// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { CREATE3Factory } from "lib/create3-factory/src/CREATE3Factory.sol";
import { EulerRouter } from "lib/euler-price-oracle/src/EulerRouter.sol";
import { ChainlinkOracle } from "lib/euler-price-oracle/src/adapter/chainlink/ChainlinkOracle.sol";
import { PythOracle } from "lib/euler-price-oracle/src/adapter/pyth/PythOracle.sol";

import { Constants } from "test/utils/Constants.t.sol";

import { AnchoredOracle } from "src/AnchoredOracle.sol";
import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { FeeCollector } from "src/FeeCollector.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";

contract DeployUtils is Constants {
    // Steps for completing a rebalance
    // 1. Propose Rebalance
    // - permissioned to the _REBALANCER_ROLE
    // - Requirements for a rebalance to happen:
    // - - any pending deposits / redeems
    // - - have an imbalance in target vs current weights for basket larger than $500
    // - - call proposeRebalance() with array of target basket tokens
    // - - *note currently you can propose any number of baskets as long as one meets the above requirement. This is so
    // all provided baskets are considered for internal trades. This may involve additional checks in the future
    // - if successful the rebalance status is updated to REBALANCE_PROPOSED and timer is started. Basket tokens
    // involved
    // in this rebalance have their requestIds incremented so that any future deposit/redeem request are handled by the
    // next redemption cycle.
    // 2. Propose token swaps
    // - permissioned to the _REBALANCER_ROLE
    // - provide arrays of internal/external token swaps
    // - these trades MUST result in the targeted weights ($ wise) for this call to succeed.
    // - if successful the rebalance status is TOKEN_SWAP_PROPOSED
    // 3. Execute Token swaps
    // - permissioned to the _REBALANCER_ROLE
    // - if external trades are proposed they must be executed on the token swap adapter. This can only happen after a
    // set amount of time has passed to allow for the trades to happen. Calling execute token swap can result in any
    // amount of trade success. The function returns all tokens back to the basket manager.
    // - when token swaps are executed the status is updated to TOKEN_SWAP_EXECUTED
    // 4. Complete Rebalance
    // - permissionless
    // - This must be called at least 15 minutes after propose token swap has been called.
    // - If external trades have been executed gets the results and updates internal accounting
    // - Processes internal trades and pending redeptions.
    // - *note in the instance the target weights have not been met by the time of calling completeRebalance() a retry
    // is initiated. In this case the status is set to REBALANCE_PROPOSED to allow for additional internal / external
    // trades to be proposed and the steps above repeated. If the retry cycle happens the maximum amount of times the
    // rebalance is completed regardless. If pending redemptions cannot be fulfilled because of an in-complete rebalance
    // the basket tokens are notified and users with pending redemptions must claim their shares back and request a
    // redeem once again.

    /// DEPLOY FUNCTIONS ///

    // Deploys a pyth oracle and chainlink oracle. Deploys an anchored oracle using the two privously deployed oracles.
    // Adds the assets to the asset registry. Sets the anchored oracle for the given assets in the euler router.
    // name like: "ETH/USD"
    // caller must be admin
    function _deployAnchoredOracleForPair(
        string memory name,
        address baseAsset,
        address quoteAsset,
        bytes32 pythPriceFeed,
        address chainLinkPriceFeed,
        uint256 maxDivergence,
        address assetRegistry,
        address eulerRouter
    )
        public
        returns (address anchoredOracle)
    {
        PythOracle primary = new PythOracle(Constants.PYTH, baseAsset, quoteAsset, pythPriceFeed, 15 minutes, 500);
        ChainlinkOracle anchor = new ChainlinkOracle(baseAsset, quoteAsset, chainLinkPriceFeed, 1 days);
        string memory oracleName = string.concat(name, "_AnchoredOracle");
        anchoredOracle = address(new AnchoredOracle(address(primary), address(anchor), maxDivergence));
        AssetRegistry assetRegistry = AssetRegistry(assetRegistry);
        // if asset already added will revert
        try assetRegistry.addAsset(baseAsset) { } catch { }
        try assetRegistry.addAsset(quoteAsset) { } catch { }
        EulerRouter(eulerRouter).govSetConfig(baseAsset, quoteAsset, anchoredOracle);
        EulerRouter(eulerRouter).govSetConfig(quoteAsset, baseAsset, anchoredOracle);
    }

    // Creates a bitflag that includes all given asset indices.
    function _includeAssets(uint8[] memory assetIndices) internal pure returns (uint256 bitFlag) {
        for (uint256 i = 0; i < assetIndices.length; i++) {
            bitFlag |= 1 << assetIndices[i];
        }
    }

    // Deploys basket manager given a fee collector salt which must be used to deploy the fee collector using CREATE3.
    // Caller must be admin
    function _deployBasketManager(
        bytes32 feeCollectorSalt,
        address basketTokenImplementation,
        address eulerRouter,
        address StrategyRegistry,
        address assetRegistry,
        address admin,
        address pauser
    )
        internal
        returns (address basketManager)
    {
        CREATE3Factory factory = CREATE3Factory(CREATE3_FACTORY);
        // Determine feeCollector deployment address
        address feeCollectorAddress = factory.getDeployed(COVE_DEPLOYER_ADDRESS, feeCollectorSalt);
        address basketManager = address(
            new BasketManager(
                basketTokenImplementation,
                eulerRouter,
                StrategyRegistry,
                assetRegistry,
                admin,
                pauser,
                feeCollectorAddress
            )
        );
        BasketManager bm = BasketManager(basketManager);
        // Admin must make below calls after deployment
        // bm.grantRole(MANAGER_ROLE, manager);
        // bm.grantRole(REBALANCER_ROLE, rebalancer);
        // bm.grantRole(TIMELOCK_ROLE, timelock);
    }

    // Uses CREATE3 to deploy a fee collector contract. Salt must be the same given to the basket manager deploy.
    function _deployFeeCollector(
        bytes32 feeCollectorSalt,
        address admin,
        address basketManager,
        address treasury
    )
        internal
        returns (address feeCollector)
    {
        CREATE3Factory factory = CREATE3Factory(CREATE3_FACTORY);
        // Prepare constructor arguments for FeeCollector
        bytes memory constructorArgs = abi.encode(admin, basketManager, treasury);
        // Deploy FeeCollector contract using CREATE3
        bytes memory feeCollectorBytecode = abi.encodePacked(type(FeeCollector).creationCode, constructorArgs);
        address feeCollector = factory.deploy(feeCollectorSalt, feeCollectorBytecode);
    }
}
