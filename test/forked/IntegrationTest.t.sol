// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { console } from "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IPyth } from "euler-price-oracle/lib/pyth-sdk-solidity/IPyth.sol";
import { PythStructs } from "euler-price-oracle/lib/pyth-sdk-solidity/PythStructs.sol";

import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { ManagedWeightStrategy } from "src/strategies/ManagedWeightStrategy.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";
import { WeightStrategy } from "src/strategies/WeightStrategy.sol";
import { Status } from "src/types/BasketManagerStorage.sol";
import { Constants } from "test/utils/Constants.t.sol";

import { ExternalTrade, InternalTrade } from "src/types/Trades.sol";

import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { BasketTokenDeployment, Deployments, OracleOptions } from "script/Deployments.s.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

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

contract IntegrationTest is BaseTest, Constants {
    using FixedPointMathLib for uint256;

    mapping(string => address) public contracts;
    mapping(address => mapping(address => uint256)) public basketUserPendingDeposits;
    mapping(address => mapping(address => uint256)) public basketUserPendingRedeems;
    mapping(address => mapping(address => uint256)) public basketUserRequestId;
    BasketManager public bm;
    Deployments public deployments;

    function setUp() public override {
        // Fork ethereum mainnet at block 20113049 for consistent testing and to cache RPC calls
        // https://etherscan.io/block/20113049
        forkNetworkAt("mainnet", 20_892_640);
        super.setUp();
        // Allow cheatcodes for contract deployed by deploy script
        vm.allowCheatcodes(0xa5F044DA84f50f2F6fD7c309C5A8225BCE8b886B);
        vm.startPrank(COVE_DEPLOYER_ADDRESS);
        deployments = new Deployments();
        uint64[] memory initialWeights = new uint64[](2);
        initialWeights[0] = 0.5e18;
        initialWeights[1] = 0.5e18;
        uint8[] memory assetIndices = new uint8[](2);
        assetIndices[0] = 0;
        assetIndices[1] = 1;
        uint256 bitFlag = deployments.getBitflagFromIndicies(assetIndices);
        BasketTokenDeployment[] memory basketTokenDeployments = new BasketTokenDeployment[](1);
        basketTokenDeployments[0] = BasketTokenDeployment({
            asset: WETH,
            name: "Test",
            symbol: "TEST",
            bitFlag: bitFlag,
            initialWeights: initialWeights
        });
        OracleOptions[] memory oracleOptions = new OracleOptions[](1);
        oracleOptions[0] = OracleOptions({
            pythPriceFeed: PYTH_ETH_USD_FEED,
            pythMaxStaleness: 15 minutes,
            pythMaxConfWidth: 500,
            chainlinkPriceFeed: CHAINLINK_ETH_USD_FEED,
            chainlinkMaxStaleness: 1 days,
            maxDivergence: 0.5e18
        });
        deployments.deploy(basketTokenDeployments, oracleOptions, false);
        vm.stopPrank();
    }

    function test_setUp() public view {
        assert(deployments.checkDeployment("BasketManager") != address(0));
        assert(deployments.checkDeployment("AssetRegistry") != address(0));
        assert(deployments.checkDeployment("StrategyRegistry") != address(0));
        assert(deployments.checkDeployment("EulerRouter") != address(0));
        assert(deployments.checkDeployment("Test_BasketToken") != address(0));
        assert(deployments.checkDeployment("FeeCollector") != address(0));
        assert(deployments.checkDeployment("Test_ManagedWeightStrategy") != address(0));
        assert(deployments.checkDeployment("Test_PythOracle") != address(0));
        assert(deployments.checkDeployment("Test_ChainlinkOracle") != address(0));
        assert(deployments.checkDeployment("Test_AnchoredOracle") != address(0));
    }
}
