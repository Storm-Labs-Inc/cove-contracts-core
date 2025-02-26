// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { Vm } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";

import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { IMasterRegistry } from "src/interfaces/IMasterRegistry.sol";
import { BasketTradeOwnership, ExternalTrade, InternalTrade } from "src/types/Trades.sol";

import { BaseTest } from "test/utils/BaseTest.t.sol";

contract GenerateStatesForFrontend is BaseTest {
    // Account used for testing
    address public user = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public basketManager;
    address public basketToken;
    address public rebalanceProposer = COVE_SILVERBACK_AWS_ACCOUNT;
    address public tokenSwapProposer = COVE_SILVERBACK_AWS_ACCOUNT;
    address public tokenSwapExecutor = COVE_SILVERBACK_AWS_ACCOUNT;

    uint256 public constant AIRDROP_AMOUNT = 1_000_000;
    uint256 public constant DEPOSIT_AMOUNT = 10_000;

    function setUp() public override {
        forkNetworkAt("mainnet", 21_928_744);
        basketManager = _getFromStagingMasterRegistry("BasketManager");
        basketToken = BasketManager(basketManager).basketTokens()[0];
        super.setUp();
        labelKnownAddresses();

        // Give some eth to user
        vm.deal(user, 100 ether);

        _dumpStateWithTimestamp("BaseState");
    }

    function test_generateStates_sucessful_deposit_and_claim_shares() public {
        // Fast forward to 1 day after the fork to ensure rebalance is possible
        vm.warp(vm.getBlockTimestamp() + 1 days);

        // 1. Give USDC to user
        deal(ETH_USDC, user, AIRDROP_AMOUNT * _getOneUnit(ETH_USDC));
        _dumpStateWithTimestamp("01_accountHasSomeUSDC");

        // 2. Request deposit USDC into basket
        vm.startPrank(user);
        uint256 depositAmount = DEPOSIT_AMOUNT * _getOneUnit(ETH_USDC);
        IERC20(ETH_USDC).approve(basketToken, depositAmount);
        BasketToken(basketToken).requestDeposit(depositAmount, user, user);
        vm.stopPrank();
        _dumpStateWithTimestamp("02_accountHasRequestedDeposit");

        // 3. Propose rebalance
        _refreshPriceFeeds();
        address[] memory basketTokens = new address[](1);
        basketTokens[0] = basketToken;
        vm.prank(rebalanceProposer);
        BasketManager(basketManager).proposeRebalance(basketTokens);
        _dumpStateWithTimestamp("03_accountHasClaimableBasketTokenShares");

        // 4. Claim shares
        uint256 balance = BasketToken(basketToken).maxDeposit(user);
        vm.prank(user);
        BasketToken(basketToken).deposit(balance, user, user);
        _dumpStateWithTimestamp("04_accountHasBasketTokenShares");

        // Generate external trades, execute them, mock cowswap activity, then complete rebalance
        uint64[][] memory targetWeights = _getBasketTagetWeights(basketTokens);
        ExternalTrade[] memory externalTrades = new ExternalTrade[](3);
        externalTrades[0] =
            _buildSingleExternalTrade(basketToken, ETH_USDC, ETH_SDAI, depositAmount * targetWeights[0][1] / 1e18);
        externalTrades[1] =
            _buildSingleExternalTrade(basketToken, ETH_USDC, ETH_SFRAX, depositAmount * targetWeights[0][2] / 1e18);
        externalTrades[2] =
            _buildSingleExternalTrade(basketToken, ETH_USDC, ETH_SUSDE, depositAmount * targetWeights[0][3] / 1e18);
        // 5. Complete rebalance, account can now pro-rata redeem
        _continueAndCompleteRebalance(basketTokens, externalTrades);
        _dumpStateWithTimestamp("05_protocolHasCompletedRebalance_accountCanProRataRedeem");

        // 6. Request Redeem
        vm.prank(user);
        BasketToken(basketToken).requestRedeem(balance, user, user);
        _dumpStateWithTimestamp("06_accountHasRequestedRedeem");

        vm.warp(vm.getBlockTimestamp() + 1 days);
    }

    function _getFromStagingMasterRegistry(bytes32 key) internal view returns (address) {
        return IMasterRegistry(COVE_STAGING_MASTER_REGISTRY).resolveNameToLatestAddress(key);
    }

    function _getOneUnit(address token) internal view returns (uint256) {
        return 10 ** IERC20Metadata(token).decimals();
    }

    function _refreshPriceFeeds() internal {
        _updatePythOracleTimeStamp(PYTH_SUSDE_USD_FEED);
        _updatePythOracleTimeStamp(PYTH_USDC_USD_FEED);
        _updatePythOracleTimeStamp(PYTH_SDAI_USD_FEED);
        _updatePythOracleTimeStamp(PYTH_FRAX_USD_FEED);

        _updateChainLinkOracleTimeStamp(ETH_CHAINLINK_SUSDE_USD_FEED);
        _updateChainLinkOracleTimeStamp(ETH_CHAINLINK_USDC_USD_FEED);
        _updateChainLinkOracleTimeStamp(ETH_CHAINLINK_DAI_USD_FEED);
        _updateChainLinkOracleTimeStamp(ETH_CHAINLINK_FRAX_USD_FEED);
    }

    function _getBasketTagetWeights(address[] memory basketTokens) internal view returns (uint64[][] memory) {
        uint64[][] memory targetWeights = new uint64[][](basketTokens.length);
        for (uint256 i = 0; i < basketTokens.length; i++) {
            targetWeights[i] = BasketToken(basketTokens[i]).getTargetWeights();
        }
        return targetWeights;
    }

    function _getBasketAssets(address[] memory basketTokens) internal view returns (address[][] memory) {
        address[][] memory assets = new address[][](basketTokens.length);
        for (uint256 i = 0; i < basketTokens.length; i++) {
            assets[i] = BasketToken(basketTokens[i]).getAssets();
        }
        return assets;
    }

    function _buildSingleExternalTrade(
        address basket,
        address sellToken,
        address buyToken,
        uint256 sellAmount
    )
        internal
        view
        returns (ExternalTrade memory)
    {
        EulerRouter eulerRouter = EulerRouter(_getFromStagingMasterRegistry("EulerRouter"));
        uint256 minAmount = eulerRouter.getQuote(eulerRouter.getQuote(sellAmount, sellToken, USD), USD, buyToken);
        BasketTradeOwnership[] memory basketTradeOwnership = new BasketTradeOwnership[](1);
        basketTradeOwnership[0] = BasketTradeOwnership({ basket: basket, tradeOwnership: 1e18 });
        return ExternalTrade({
            sellToken: sellToken,
            buyToken: buyToken,
            sellAmount: sellAmount,
            minAmount: minAmount,
            basketTradeOwnership: basketTradeOwnership
        });
    }

    function _continueAndCompleteRebalance(
        address[] memory basketTokens,
        ExternalTrade[] memory externalTrades
    )
        internal
    {
        vm.startPrank(tokenSwapProposer);
        BasketManager(basketManager).proposeTokenSwap(
            new InternalTrade[](0),
            externalTrades,
            basketTokens,
            _getBasketTagetWeights(basketTokens),
            _getBasketAssets(basketTokens)
        );
        vm.stopPrank();

        vm.recordLogs();
        vm.prank(tokenSwapExecutor);
        BasketManager(basketManager).executeTokenSwap(externalTrades, "");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("OrderCreated(address,address,uint256,uint256,uint32,address)")) {
                address sellToken = address(uint160(uint256(logs[i].topics[1])));
                address buyToken = address(uint160(uint256(logs[i].topics[2])));
                console.log("sellToken", sellToken);
                console.log("buyToken", buyToken);
                (uint256 sellAmount, uint256 buyAmount, uint32 validTo, address swapContract) =
                    abi.decode(logs[i].data, (uint256, uint256, uint32, address));
                console.log("sellAmount", sellAmount);
                console.log("buyAmount", buyAmount);
                console.log("validTo", validTo);
                console.log("swapContract", swapContract);
                // Simulate the trade being executed
                takeAway(IERC20(sellToken), swapContract, sellAmount);
                airdrop(IERC20(buyToken), swapContract, buyAmount);
            }
        }

        vm.warp(vm.getBlockTimestamp() + 15 minutes);
        _refreshPriceFeeds();
        vm.startPrank(rebalanceProposer);
        BasketManager(basketManager).completeRebalance(
            externalTrades, basketTokens, _getBasketTagetWeights(basketTokens), _getBasketAssets(basketTokens)
        );
        vm.stopPrank();
    }
}
