// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { console } from "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPyth } from "@pyth/IPyth.sol";
import { PythStructs } from "@pyth/PythStructs.sol";
import { CREATE3Factory } from "create3-factory/src/CREATE3Factory.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { ChainlinkOracle } from "euler-price-oracle/src/adapter/chainlink/ChainlinkOracle.sol";
import { PythOracle } from "euler-price-oracle/src/adapter/pyth/PythOracle.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { Constants } from "test/utils/Constants.t.sol";

import { AnchoredOracle } from "src/AnchoredOracle.sol";
import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { FeeCollector } from "src/FeeCollector.sol";
import { ManagedWeightStrategy } from "src/strategies/ManagedWeightStrategy.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";
import { WeightStrategy } from "src/strategies/WeightStrategy.sol";

import { ExternalTrade } from "src/types/Trades.sol";
import { DeploySetup } from "test/utils/DeploySetup.t.sol";

contract DeploySetup is BaseTest, Constants {
    using FixedPointMathLib for uint256;

    mapping(string => address) public contracts;
    mapping(address => mapping(address => uint256)) public basketUserPendingDeposits;
    mapping(address => mapping(address => uint256)) public basketUserPendingRedeems;
    mapping(address => mapping(address => uint256)) public basketUserRequestId;
    address[] public assets;

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

    function setUp() public override {
        // Fork ethereum mainnet at block 20113049 for consistent testing and to cache RPC calls
        // https://etherscan.io/block/20113049
        forkNetworkAt("mainnet", 20_892_640);
        super.setUp();
        vm.startPrank(COVE_DEPLOYER_ADDRESS);

        // USERS
        users["alice"] = createUser("alice");
        users["admin"] = COVE_COMMUNITY_MULTISIG;
        users["treasury"] = COVE_OPS_MULTISIG;
        users["pauser"] = COVE_OPS_MULTISIG;
        users["manager"] = COVE_OPS_MULTISIG;
        users["rebalancer"] = COVE_OPS_MULTISIG;

        // REGISTRIES
        contracts["assetRegistry"] = address(new AssetRegistry(users["admin"]));
        contracts["strategyRegistry"] = address(new StrategyRegistry(users["admin"]));

        // BASKET MANAGER
        contracts["basketTokenImplementation"] = address(new BasketToken());
        contracts["eulerRouter"] = address(new EulerRouter(users["admin"]));
        bytes32 feeCollectorSalt = keccak256(abi.encodePacked("FeeCollector"));
        _deployBasketManager(feeCollectorSalt);
        _deployFeeCollector(feeCollectorSalt);
        vm.stopPrank();
    }

    function testFuzz_singleDepositor_completeRebalance(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1, type(uint256).max);

        BasketManager bm = BasketManager(contracts["basketManager"]);
        address[] memory assets = new address[](2);
        assets[0] = WETH;
        assets[1] = USD;
        string memory name = "WETH/USD";
        uint8[] memory assetIndexes = new uint8[](2);
        assetIndexes[0] = 0;
        assetIndexes[1] = 1;
        uint256 bitFlag = _includeAssets(assetIndexes);
        address basketAddress =
            _deployBasket("WETH/USD", assets, bitFlag, PYTH_ETH_USD_FEED, CHAINLINK_ETH_USD_FEED, 0.5e18);
        BasketToken basket = BasketToken(basketAddress);
        console.log(basketAddress);
        address[] memory baskets = new address[](1);
        baskets[0] = basketAddress;
        uint64[] memory weights = new uint64[](2);
        weights[0] = 5e17;
        weights[1] = 5e17;
        vm.prank(users["admin"]);
        ManagedWeightStrategy(contracts[string.concat("mwStrategy_", name)]).setTargetWeights(bitFlag, weights);
        uint256 depositAmount = 1000e18;
        _requestDepositToBasket(basketAddress, users["alice"], depositAmount);
        vm.prank(users["rebalancer"]);
        bm.proposeRebalance(baskets);
        vm.warp(block.timestamp + 15 minutes);
        _updatePythOracleTimeStamp(PYTH_ETH_USD_FEED);
        ExternalTrade[] memory trades = new ExternalTrade[](0);
        vm.prank(users["rebalancer"]);
        bm.completeRebalance(trades, baskets);
        uint256 balanceBefore = basket.balanceOf(users["alice"]);
        vm.prank(users["alice"]);
        basket.deposit(depositAmount, users["alice"], users["alice"]);
        uint256 balanceAfter = basket.balanceOf(users["alice"]);
        assertGt(balanceAfter, balanceBefore);
    }
}
