// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

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

import { BasketTradeOwnership, ExternalTrade, InternalTrade } from "src/types/Trades.sol";
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
    address public mockSwapAdapter;

    function setUp() public override {
        // Fork ethereum mainnet at block 20113049 for consistent testing and to cache RPC calls
        // https://etherscan.io/block/20113049
        forkNetworkAt("mainnet", 20_892_640);
        super.setUp();
        // Allow cheatcodes for contract deployed by deploy script
        vm.allowCheatcodes(0xa5F044DA84f50f2F6fD7c309C5A8225BCE8b886B);
        deployments = new Deployments();
        deployments.deploy(false);

        bm = BasketManager(deployments.getAddress("BasketManager"));

        // We use a mock token swap adapter as using cowswap is not possible in a forked environment
        mockSwapAdapter = createUser("MockTokenSwapAdapter");
        vm.prank(deployments.admin());
        bm.setTokenSwapAdapter(mockSwapAdapter);
    }

    function test_setUp() public view {
        // forge-deploy checks
        assertNotEq(address(bm), address(0));
        assertNotEq(deployments.getAddress("AssetRegistry"), address(0));
        assertNotEq(deployments.getAddress("StrategyRegistry"), address(0));
        assertNotEq(deployments.getAddress("EulerRouter"), address(0));
        assertNotEq(deployments.getAddress("FeeCollector"), address(0));

        // Launch parameter checks
        assertEq(bm.numOfBasketTokens(), 1); // TODO: update this after finalizing the launch basket tokens
    }

    function testFuzz_completeRebalance_processDeposits(uint256 numUsers, uint256 entropy) public {
        numUsers = bound(numUsers, 1, 100);

        // request deposit for all users
        address[] memory basketTokens = bm.basketTokens();

        for (uint256 i = 0; i < numUsers; ++i) {
            address user = vm.addr(i + 1);
            // Generate pseudo-random amount
            uint256 amount = uint256(keccak256(abi.encodePacked(i, entropy)));
            amount = bound(amount, 1 ether, 1000 ether);
            for (uint256 j = 0; j < basketTokens.length; ++j) {
                _requestDepositToBasket(user, basketTokens[j], amount);
            }
        }

        // propose rebalance
        // TODO: track oracles better than below
        _updatePythOracleTimeStamps();
        vm.prank(deployments.rebalanceProposer());
        bm.proposeRebalance(basketTokens);
        assertEq(bm.rebalanceStatus().timestamp, block.timestamp);
        assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
        assertEq(bm.rebalanceStatus().basketMask, 1);
        assertEq(bm.rebalanceStatus().basketHash, keccak256(abi.encodePacked(basketTokens)));

        // propose token swaps
        // note: for the first rebalance no trades are proposed and only deposits are processed
        ExternalTrade[] memory externalTrades = new ExternalTrade[](0);
        InternalTrade[] memory internalTrades = new InternalTrade[](0);

        vm.prank(deployments.tokenSwapProposer());
        bm.proposeTokenSwap(internalTrades, externalTrades, basketTokens);
        assertEq(bm.rebalanceStatus().timestamp, block.timestamp);
        assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_PROPOSED));

        vm.warp(block.timestamp + 15 minutes);
        // complete rebalance
        bm.completeRebalance(externalTrades, basketTokens);
        assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.NOT_STARTED));
    }

    function _requestDepositToBasket(
        address user,
        address basket,
        uint256 amount
    )
        internal
        returns (uint256 requestId)
    {
        address asset = BasketToken(basket).asset();
        deal(asset, user, amount);
        vm.startPrank(user);
        IERC20(asset).approve(basket, amount);
        uint256 balanceBefore = IERC20(asset).balanceOf(basket);
        requestId = BasketToken(basket).requestDeposit(amount, user, user);
        assert(balanceBefore + amount == IERC20(asset).balanceOf(basket));
        vm.stopPrank();
    }

    function _requestRedeemFromBasket(
        address user,
        address basket,
        uint256 shares
    )
        internal
        returns (uint256 requestId)
    {
        vm.startPrank(user);
        BasketToken(basket).approve(user, shares);
        uint256 balanceBefore = IERC20(basket).balanceOf(user);
        requestId = BasketToken(basket).requestRedeem(shares, user, user);
        assert(balanceBefore - shares == IERC20(basket).balanceOf(user));
        vm.stopPrank();
    }

    // // Oracles are stuck on one block, mock updating oracle data with same price but with a valid publish time
    function _updatePythOracleTimeStamp(bytes32 pythPriceFeed) internal {
        PythStructs.Price memory res = IPyth(PYTH).getPriceUnsafe(pythPriceFeed);
        res.publishTime = block.timestamp;
        vm.mockCall(PYTH, abi.encodeCall(IPyth.getPriceUnsafe, (pythPriceFeed)), abi.encode(res));
    }

    function _updatePythOracleTimeStamps() internal {
        bytes32[] memory pythPriceFeeds = new bytes32[](2);
        pythPriceFeeds[0] = PYTH_ETH_USD_FEED;
        pythPriceFeeds[1] = PYTH_SUSE_USD_FEED;
        // TODO: currently dont work with pyth contract
        // pythPriceFeeds[2] = PYTH_GHO_USD_FEED;
        // pythPriceFeeds[3] = PYTH_CBBTC_USD_FEED;
        for (uint256 i = 0; i < pythPriceFeeds.length; ++i) {
            _updatePythOracleTimeStamp(pythPriceFeeds[i]);
        }
    }
}
