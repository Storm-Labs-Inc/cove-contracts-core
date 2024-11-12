// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { console } from "forge-std/console.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IPyth } from "euler-price-oracle/lib/pyth-sdk-solidity/IPyth.sol";
import { PythStructs } from "euler-price-oracle/lib/pyth-sdk-solidity/PythStructs.sol";

import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";

import { AnchoredOracle } from "src/AnchoredOracle.sol";
import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { ManagedWeightStrategy } from "src/strategies/ManagedWeightStrategy.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";
import { WeightStrategy } from "src/strategies/WeightStrategy.sol";
import { Status } from "src/types/BasketManagerStorage.sol";

import { BasketTradeOwnership, ExternalTrade, InternalTrade } from "src/types/Trades.sol";
import { Constants } from "test/utils/Constants.t.sol";

import { Deployer, DeployerFunctions } from "generated/deployer/DeployerFunctions.g.sol";
import { BasketTokenDeployment, Deployments, OracleOptions } from "script/Deployments.s.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

// Steps for completing a rebalance
// 1. Propose Rebalance
// - permissioned to the _REBALANCER_ROLE
// - Requirements for a rebalance to happen:
//   - any pending deposits / redeems
//   - have an imbalance in target vs current weights for basket larger than $500
// - Call proposeRebalance() with array of target basket tokens
//   - Note: currently you can propose any number of baskets as long as one meets the above requirement.
//     This is so all provided baskets are considered for internal trades. This may involve additional checks in the
// future
// - If successful, the rebalance status is updated to REBALANCE_PROPOSED and timer is started.
//   Basket tokens involved in this rebalance have their requestIds incremented so that any future deposit/redeem
// requests are handled by the next redemption cycle.
// 2. Propose token swaps
// - Permissioned to the _REBALANCER_ROLE
// - Provide arrays of internal/external token swaps
// - These trades MUST result in the targeted weights ($ wise) for this call to succeed.
// - If successful, the rebalance status is TOKEN_SWAP_PROPOSED
// 3. Execute Token swaps
// - Permissioned to the _REBALANCER_ROLE
// - If external trades are proposed, they must be executed on the token swap adapter. This can only happen after a set
// amount of time has passed to allow for the trades to happen.
// - Calling execute token swap can result in any amount of trade success. The function returns all tokens back to the
// basket manager.
// - When token swaps are executed, the status is updated to TOKEN_SWAP_EXECUTED
// 4. Complete Rebalance
// - Permissionless
// - This must be called at least 15 minutes after propose token swap has been called.
// - If external trades have been executed, gets the results and updates internal accounting
// - Processes internal trades and pending redemptions.
// - Note: In the instance the target weights have not been met by the time of calling completeRebalance(), a retry is
// initiated.
//   In this case, the status is set to REBALANCE_PROPOSED to allow for additional internal/external trades to be
// proposed and the steps above repeated.
//   If the retry cycle happens the maximum amount of times, the rebalance is completed regardless.
//   If pending redemptions cannot be fulfilled because of an incomplete rebalance, the basket tokens are notified and
// users with pending redemptions must claim their shares back and request a redeem once again.

contract IntegrationTest is BaseTest, Constants {
    using FixedPointMathLib for uint256;

    mapping(string => address) public contracts;
    mapping(address => mapping(address => uint256)) public basketUserPendingDeposits;
    mapping(address => mapping(address => uint256)) public basketUserPendingRedeems;
    mapping(address => mapping(address => uint256)) public basketUserRequestId;
    mapping(address => string) public assetNames;
    BasketManager public bm;
    Deployments public deployments;
    address public mockSwapAdapter;

    mapping(bytes32 => uint256) public tradeAmounts; // To avoid duplicate trades

    function setUp() public override {
        // Fork Ethereum mainnet at block 20892640 for consistent testing and to cache RPC calls
        // https://etherscan.io/block/20892640
        forkNetworkAt("mainnet", 20_892_640);
        super.setUp();
        // Allow cheatcodes for contract deployed by deploy script
        vm.allowCheatcodes(0xa5F044DA84f50f2F6fD7c309C5A8225BCE8b886B);
        deployments = new Deployments();
        deployments.deploy(false);

        bm = BasketManager(deployments.getAddress("BasketManager"));

        // We use a mock token swap adapter as using CowSwap is not possible in a forked environment
        mockSwapAdapter = createUser("MockTokenSwapAdapter");
        vm.prank(deployments.admin());
        bm.setTokenSwapAdapter(mockSwapAdapter);
        // Store asset names for oracle lookups
        assetNames[ETH_WETH] = "WETH";
        assetNames[ETH_SUSDE] = "SUSDE";
        assetNames[ETH_WEETH] = "weETH";
        assetNames[ETH_EZETH] = "ezETH";
        assetNames[ETH_RSETH] = "rsETH";
        assetNames[ETH_RETH] = "rETH";
    }

    function test_setUp() public view {
        // Forge-deploy checks
        assertNotEq(address(bm), address(0));
        assertNotEq(deployments.getAddress("AssetRegistry"), address(0));
        assertNotEq(deployments.getAddress("StrategyRegistry"), address(0));
        assertNotEq(deployments.getAddress("EulerRouter"), address(0));
        assertNotEq(deployments.getAddress("FeeCollector"), address(0));

        // Launch parameter checks
        assertEq(bm.numOfBasketTokens(), 1); // TODO: Update this after finalizing the launch basket tokens
    }

    function testFuzz_completeRebalance_processDeposits(uint256 numUsers, uint256 entropy) public {
        numUsers = bound(numUsers, 1, 100);

        // Request deposit for all users
        address[] memory basketTokens = bm.basketTokens();

        for (uint256 i = 0; i < numUsers; ++i) {
            address user = vm.addr(i + 1);
            // Generate pseudo-random amount
            uint256 amount = uint256(keccak256(abi.encodePacked(i, entropy))) % (1000 ether - 1e4) + 1e4;
            for (uint256 j = 0; j < basketTokens.length; ++j) {
                _requestDepositToBasket(user, basketTokens[j], amount);
            }
        }

        // Propose rebalance
        _updatePythOracleTimeStamps();
        vm.prank(deployments.rebalanceProposer());
        bm.proposeRebalance(basketTokens);
        assertEq(bm.rebalanceStatus().timestamp, block.timestamp);
        assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
        assertEq(bm.rebalanceStatus().basketMask, 1);
        assertEq(bm.rebalanceStatus().basketHash, keccak256(abi.encodePacked(basketTokens)));

        // Propose token swaps
        // Note: For the first rebalance no trades are proposed and only deposits are processed
        ExternalTrade[] memory externalTradesLocal = new ExternalTrade[](0);
        InternalTrade[] memory internalTradesLocal = new InternalTrade[](0);

        vm.prank(deployments.tokenSwapProposer());
        bm.proposeTokenSwap(internalTradesLocal, externalTradesLocal, basketTokens);
        assertEq(bm.rebalanceStatus().timestamp, block.timestamp);
        assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_PROPOSED));

        vm.warp(block.timestamp + 15 minutes);
        // Complete rebalance
        bm.completeRebalance(externalTradesLocal, basketTokens);
        assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.NOT_STARTED));
    }

    function test_calculateExternalTrades() public {
        testFuzz_completeRebalance_processDeposits(100, 100);
        vm.warp(block.timestamp + REBALANCE_COOLDOWN_SEC);
        uint64[] memory newTargetWeights = new uint64[](6);
        newTargetWeights[0] = 5e17; // 50%
        newTargetWeights[1] = 5e17; // 50%
        newTargetWeights[2] = 0; // 0%
        newTargetWeights[3] = 0; // 0%
        newTargetWeights[4] = 0; // 0%
        newTargetWeights[5] = 0; // 0%

        // Calculate external trades
        _updatePythOracleTimeStamps();
        ExternalTrade[] memory externalTrades = _calculateExternalTrades(newTargetWeights);

        // Update strategy with new target weights
        ManagedWeightStrategy strategy =
            ManagedWeightStrategy(deployments.getAddress("Gauntlet V1_ManagedWeightStrategy"));
        address[] memory basketAssets = bm.basketAssets(bm.basketTokens()[0]);
        uint256 bitflag = AssetRegistry(deployments.getAddress("AssetRegistry")).getAssetsBitFlag(basketAssets);

        vm.prank(GAUNTLET_STRATEGIST);
        strategy.setTargetWeights(bitflag, newTargetWeights);

        // Propose rebalance
        address[] memory basketTokens = bm.basketTokens();
        vm.prank(deployments.rebalanceProposer());
        bm.proposeRebalance(basketTokens);

        // Propose token swap with calculated trades
        vm.prank(deployments.tokenSwapProposer());
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        bm.proposeTokenSwap(internalTrades, externalTrades, basketTokens);
        vm.warp(block.timestamp + 15 minutes);
        bm.completeRebalance(externalTrades, basketTokens);
    }

    // Calculate external trades based on new target weights
    function _calculateExternalTrades(uint64[] memory newTargetWeights)
        internal
        view
        returns (ExternalTrade[] memory)
    {
        address basketToken = bm.basketTokens()[0];
        address[] memory basketAssets = bm.basketAssets(basketToken);
        uint256 assetCount = basketAssets.length;

        require(newTargetWeights.length == assetCount, "Mismatched weights and assets");

        // Fetch current balances and prices
        (uint256[] memory currentValuesUSD, uint256 totalValueUSD) = _getCurrentUSDValue(basketToken, basketAssets);

        // Calculate desired values based on new target weights
        uint256[] memory desiredValuesUSD = _calculateDesiredValues(totalValueUSD, newTargetWeights);

        // Determine surplus and deficit for each asset
        (uint256[] memory surplusUSD, uint256[] memory deficitUSD) =
            _calculateDeficitSurplus(currentValuesUSD, desiredValuesUSD, assetCount);

        // Identify assets to sell (surplus) and buy (deficit)
        ExternalTrade[] memory trades = _identifyAndPrepareTrades(basketToken, basketAssets, surplusUSD, deficitUSD);

        return trades;
    }

    function _getCurrentUSDValue(
        address basketToken,
        address[] memory basketAssets
    )
        internal
        view
        returns (uint256[] memory currentValuesUSD, uint256 totalValueUSD)
    {
        uint256 assetCount = basketAssets.length;
        currentValuesUSD = new uint256[](assetCount);
        totalValueUSD = 0;

        for (uint256 i = 0; i < assetCount; ++i) {
            uint256 balance = bm.basketBalanceOf(basketToken, basketAssets[i]);
            // Skip if asset balance is 0
            if (balance == 0) {
                continue;
            }
            currentValuesUSD[i] = _getAssetValue(basketAssets[i], balance);
            totalValueUSD += currentValuesUSD[i];
        }
    }

    function _calculateDesiredValues(
        uint256 totalValueUSD,
        uint64[] memory newTargetWeights
    )
        internal
        pure
        returns (uint256[] memory desiredValuesUSD)
    {
        uint256 assetCount = newTargetWeights.length;
        desiredValuesUSD = new uint256[](assetCount);
        for (uint256 i = 0; i < assetCount; ++i) {
            desiredValuesUSD[i] = (totalValueUSD * uint256(newTargetWeights[i])) / 1e18;
        }
    }

    function _calculateDeficitSurplus(
        uint256[] memory currentValuesUSD,
        uint256[] memory desiredValuesUSD,
        uint256 assetCount
    )
        internal
        pure
        returns (uint256[] memory surplusUSD, uint256[] memory deficitUSD)
    {
        surplusUSD = new uint256[](assetCount);
        deficitUSD = new uint256[](assetCount);

        for (uint256 i = 0; i < assetCount; ++i) {
            if (currentValuesUSD[i] > desiredValuesUSD[i]) {
                surplusUSD[i] = currentValuesUSD[i] - desiredValuesUSD[i];
            } else if (desiredValuesUSD[i] > currentValuesUSD[i]) {
                deficitUSD[i] = desiredValuesUSD[i] - currentValuesUSD[i];
            }
            // No action needed if values are equal
        }
    }

    function _identifyAndPrepareTrades(
        address basketToken,
        address[] memory basketAssets,
        uint256[] memory surplusUSD,
        uint256[] memory deficitUSD
    )
        internal
        view
        returns (ExternalTrade[] memory trades)
    {
        uint256 assetCount = basketAssets.length;

        // Since we can't dynamically resize memory arrays, we estimate the maximum number of trades and trim later
        ExternalTrade[] memory tempTrades = new ExternalTrade[](assetCount * assetCount);
        uint256 tradeCount = 0;

        for (uint256 i = 0; i < assetCount; ++i) {
            if (deficitUSD[i] > 0) {
                uint256 remainingDeficitUSD = deficitUSD[i];
                address deficitAsset = basketAssets[i];
                for (uint256 j = 0; j < assetCount; ++j) {
                    if (surplusUSD[j] > 0) {
                        uint256 availableSurplusUSD = surplusUSD[j];
                        address surplusAsset = basketAssets[j];
                        uint256 tradeValueUSD =
                            remainingDeficitUSD < availableSurplusUSD ? remainingDeficitUSD : availableSurplusUSD;

                        // Prepare trade and add to array
                        _addExternalTrade(
                            basketToken,
                            surplusAsset,
                            deficitAsset,
                            _valueToAmount(surplusAsset, tradeValueUSD), // sellAssetAmount
                            _valueToAmount(deficitAsset, tradeValueUSD), // buyAssetAmount
                            tempTrades,
                            tradeCount
                        );
                        tradeCount++;

                        // Update surplus and deficit
                        surplusUSD[j] -= tradeValueUSD;
                        remainingDeficitUSD -= tradeValueUSD;

                        if (remainingDeficitUSD == 0) {
                            break; // Deficit met, move to next deficit asset
                        }
                    }
                }
            }
        }

        // Trim the trades array to the actual number of trades
        trades = new ExternalTrade[](tradeCount);
        for (uint256 k = 0; k < tradeCount; ++k) {
            trades[k] = tempTrades[k];
        }
    }

    function _addExternalTrade(
        address basketToken,
        address sellAsset,
        address buyAsset,
        uint256 sellAssetAmount,
        uint256 minBuyAmount,
        ExternalTrade[] memory trades,
        uint256 tradeCount
    )
        internal
        view
    {
        // Check if trade already exists
        bool tradeExists = false;
        for (uint256 i = 0; i < tradeCount; ++i) {
            if (trades[i].sellToken == sellAsset && trades[i].buyToken == buyAsset) {
                // Update existing trade
                trades[i].sellAmount += sellAssetAmount;
                trades[i].minAmount += (minBuyAmount * 95) / 100;
                tradeExists = true;
                break;
            }
        }

        if (!tradeExists) {
            // Prepare trade ownership
            BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](1);
            tradeOwnerships[0] = BasketTradeOwnership({ basket: basketToken, tradeOwnership: uint96(1e18) });

            // Create new external trade
            ExternalTrade memory newTrade = ExternalTrade({
                sellToken: sellAsset,
                buyToken: buyAsset,
                sellAmount: sellAssetAmount,
                minAmount: (minBuyAmount * 95) / 100, // Applying slippage tolerance
                basketTradeOwnership: tradeOwnerships
            });

            // Add new trade to trades array
            trades[tradeCount] = newTrade;
        }
    }

    function _valueToAmount(address asset, uint256 valueUSD) internal view returns (uint256 amount) {
        uint256 assetPriceUSD = _getAssetPrice(asset);
        uint256 assetDecimals = 10 ** ERC20(asset).decimals();
        amount = (valueUSD * assetDecimals) / assetPriceUSD;
    }

    function _getAssetPrice(address asset) internal view returns (uint256 price) {
        string memory assetName = assetNames[asset];
        AnchoredOracle assetOracle =
            AnchoredOracle(deployments.getAddress(string(abi.encodePacked(assetName, "_AnchoredOracle"))));
        price = assetOracle.getQuote(10 ** ERC20(asset).decimals(), asset, USD);
    }

    function _getAssetValue(address asset, uint256 amount) internal view returns (uint256 value) {
        string memory assetName = assetNames[asset];
        AnchoredOracle assetOracle =
            AnchoredOracle(deployments.getAddress(string(abi.encodePacked(assetName, "_AnchoredOracle"))));
        value = assetOracle.getQuote(amount, asset, USD);
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
        assertEq(balanceBefore + amount, IERC20(asset).balanceOf(basket));
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
        assertEq(balanceBefore - shares, IERC20(basket).balanceOf(user));
        vm.stopPrank();
    }

    // Assumes oracles for all assets are deployed and added
    function _createNewBasket(
        string memory name,
        address[] memory assets,
        address baseAsset,
        address strategy
    )
        internal
        returns (address basket)
    {
        uint256 bitflag = AssetRegistry(deployments.getAddress("AssetRegistry")).getAssetsBitFlag(assets);
        vm.prank(deployments.admin());
        basket = bm.createNewBasket(string(abi.encodePacked(name, " Basket")), name, baseAsset, bitflag, strategy);
    }

    // Oracles are stuck on one block, mock updating oracle data with same price but with a valid publish time
    function _updatePythOracleTimeStamp(bytes32 pythPriceFeed) internal {
        PythStructs.Price memory res = IPyth(PYTH).getPriceUnsafe(pythPriceFeed);
        res.publishTime = block.timestamp;
        vm.mockCall(PYTH, abi.encodeCall(IPyth.getPriceUnsafe, (pythPriceFeed)), abi.encode(res));
    }

    function _updatePythOracleTimeStamps() internal {
        bytes32[] memory pythPriceFeeds = new bytes32[](4);
        pythPriceFeeds[0] = PYTH_ETH_USD_FEED;
        pythPriceFeeds[1] = PYTH_SUSE_USD_FEED;
        pythPriceFeeds[2] = PYTH_WEETH_USD_FEED;
        // pythPriceFeeds[3] = PYTH_EZETH_USD_FEED;
        // pythPriceFeeds[4] = PYTH_RSETH_USD_FEED;
        pythPriceFeeds[3] = PYTH_RETH_USD_FEED;

        // Currently doesn't work with Pyth contract
        for (uint256 i = 0; i < pythPriceFeeds.length; ++i) {
            _updatePythOracleTimeStamp(pythPriceFeeds[i]);
        }
    }
}
