// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

// TODO: Remove reliance on VM cheatcodes to meet the global requirement.
// Currently using vm.deal, vm.prank, vm.warp, etc. which should be replaced with
// alternative approaches that don't rely on cheatcodes for frontend testing.

import { FarmingPlugin } from "@1inch/farming/contracts/FarmingPlugin.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { Vm } from "forge-std/Vm.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { IMasterRegistry } from "src/interfaces/IMasterRegistry.sol";
import { BasicRetryOperator } from "src/operators/BasicRetryOperator.sol";
import { FarmingPluginFactory } from "src/rewards/FarmingPluginFactory.sol";
import { BasketTradeOwnership, ExternalTrade, InternalTrade } from "src/types/Trades.sol";

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { ERC20Mock } from "test/utils/mocks/ERC20Mock.sol";

contract GenerateStatesForFrontend is BaseTest {
    // Account used for testing
    address public user = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public basketManager;
    address public basketToken;
    address public farmingPlugin;
    address public weightStrategy;
    address public rebalanceProposer = STAGING_COVE_SILVERBACK_AWS_ACCOUNT;
    address public tokenSwapProposer = STAGING_COVE_SILVERBACK_AWS_ACCOUNT;
    address public tokenSwapExecutor = STAGING_COVE_SILVERBACK_AWS_ACCOUNT;

    uint256 public constant AIRDROP = 1_000_000;
    uint256 public constant DEPOSIT = 10_000;

    function setUp() public override {
        // https://etherscan.io/block/22442301
        // 8th May 2025, targets staging deployment with correct oracle deployments
        forkNetworkAt("mainnet", 22_442_301);
        basketManager = _getFromStagingMasterRegistry("BasketManager");
        basketToken = BasketManager(basketManager).basketTokens()[0];
        weightStrategy = BasketToken(basketToken).strategy();
        FarmingPluginFactory farmingPluginFactory =
            FarmingPluginFactory(_getFromStagingMasterRegistry("FarmingPluginFactory"));
        farmingPlugin = farmingPluginFactory.plugins(basketToken)[0];
        super.setUp();
        labelKnownAddresses();

        // Deploy basic retry operator and regiser in master registry
        address basicRetryOperator = address(new BasicRetryOperator());
        vm.prank(COVE_DEPLOYER_ADDRESS);
        IMasterRegistry(COVE_STAGING_MASTER_REGISTRY).addRegistry(
            bytes32(bytes("BasicRetryOperator")), basicRetryOperator
        );

        // Give some eth to user
        vm.deal(user, 100 ether);
        deal(ETH_WETH, user, AIRDROP * _getOneUnit(ETH_WETH));
        deal(ETH_USDC, user, AIRDROP * _getOneUnit(ETH_USDC));

        // Undo any EIP-7702 delegations via vm.etch
        // This is a hacky workaround to remove any EIP-7702 delegations until forge
        // supports emptying the account code via EIP-7702 txs.
        // https://github.com/foundry-rs/foundry/pull/10481
        vm.etch(user, new bytes(0));

        _dumpStateWithTimestamp("00_InitialState");
    }

    function test_generateStates_sucessful_deposit_and_claim_shares() public {
        // Fast forward to 1 day after the fork to ensure rebalance is possible
        vm.warp(vm.getBlockTimestamp() + 1 days);

        // Setup farming plugin with rewards
        uint256 rewardAmount = 100e18;
        uint256 rewardPeriod = 1 days;
        ERC20Mock farmingRewardToken = ERC20Mock(address(FarmingPlugin(farmingPlugin).REWARDS_TOKEN()));
        // Find the distributor of the plugin
        address owner = FarmingPlugin(farmingPlugin).owner();
        farmingRewardToken.mint(owner, rewardAmount);
        vm.startPrank(owner);
        farmingRewardToken.approve(farmingPlugin, rewardAmount);
        FarmingPlugin(farmingPlugin).setDistributor(owner);
        FarmingPlugin(farmingPlugin).startFarming(rewardAmount, rewardPeriod);
        vm.stopPrank();

        // 1. Give USDC to user
        deal(ETH_USDC, user, AIRDROP * _getOneUnit(ETH_USDC));
        _dumpStateWithTimestamp("01_AccountHasBasketAssets");

        // 2. Request deposit USDC into basket, add farming plugin
        vm.startPrank(user);
        uint256 depositAmount = DEPOSIT * _getOneUnit(ETH_USDC);
        IERC20(ETH_USDC).approve(basketToken, depositAmount);
        BasketToken(basketToken).requestDeposit(depositAmount, user, user);
        BasketToken(basketToken).addPlugin(farmingPlugin);
        vm.stopPrank();
        _dumpStateWithTimestamp("02_AccountHasPendingDeposit");

        // 3. Propose rebalance
        _refreshPriceFeeds();
        address[] memory basketTokens = new address[](1);
        basketTokens[0] = basketToken;
        vm.prank(rebalanceProposer);
        BasketManager(basketManager).proposeRebalance(basketTokens);
        _dumpStateWithTimestamp("03_AccountHasClaimableDeposit");

        // 4. Claim shares
        uint256 assets = BasketToken(basketToken).maxDeposit(user);
        vm.prank(user);
        BasketToken(basketToken).deposit(assets, user, user);
        _dumpStateWithTimestamp("04_AccountHasBasketTokensWhileRebalancing");

        // Generate external trades, execute them, mock cowswap activity, then complete rebalance
        uint64[][] memory targetWeights = _getBasketTagetWeights(basketTokens);
        ExternalTrade[] memory externalTrades = new ExternalTrade[](4);
        externalTrades[0] =
            _buildSingleExternalTrade(basketToken, ETH_USDC, ETH_SUPERUSDC, depositAmount * targetWeights[0][1] / 1e18);
        externalTrades[1] =
            _buildSingleExternalTrade(basketToken, ETH_USDC, ETH_SUSDE, depositAmount * targetWeights[0][2] / 1e18);
        externalTrades[2] =
            _buildSingleExternalTrade(basketToken, ETH_USDC, ETH_SFRXUSD, depositAmount * targetWeights[0][3] / 1e18);
        externalTrades[3] = _buildSingleExternalTrade(
            basketToken, ETH_USDC, ETH_YSYG_YVUSDS_1, depositAmount * targetWeights[0][4] / 1e18
        );

        // 5. Complete rebalance, account can now redeem
        _continueAndCompleteRebalance(basketTokens, externalTrades);
        // check rebalance status
        _dumpStateWithTimestamp("05_AccountHasBasketTokensCanProRataRedeem");

        // 6. Test account has a pending redeem in basket1
        vm.startPrank(user);
        BasketToken(basketToken).requestRedeem(BasketToken(basketToken).balanceOf(user), user, user);
        vm.stopPrank();
        _dumpStateWithTimestamp("06_AccountHasPendingRedeem");

        // Propose and complete rebalance to make the redeem claimable
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        vm.startPrank(rebalanceProposer);
        _refreshPriceFeeds();
        BasketManager(basketManager).proposeRebalance(basketTokens);
        vm.stopPrank();

        externalTrades[0] = _buildSingleExternalTrade(
            basketToken,
            ETH_SUPERUSDC,
            ETH_USDC,
            BasketManager(basketManager).basketBalanceOf(basketToken, ETH_SUPERUSDC)
        );
        externalTrades[1] = _buildSingleExternalTrade(
            basketToken, ETH_SUSDE, ETH_USDC, BasketManager(basketManager).basketBalanceOf(basketToken, ETH_SUSDE)
        );
        externalTrades[2] = _buildSingleExternalTrade(
            basketToken, ETH_SFRXUSD, ETH_USDC, BasketManager(basketManager).basketBalanceOf(basketToken, ETH_SFRXUSD)
        );
        externalTrades[3] = _buildSingleExternalTrade(
            basketToken,
            ETH_YSYG_YVUSDS_1,
            ETH_USDC,
            BasketManager(basketManager).basketBalanceOf(basketToken, ETH_YSYG_YVUSDS_1)
        );
        _continueAndCompleteRebalance(basketTokens, externalTrades);

        // Verify redeem is claimable
        assertTrue(BasketToken(basketToken).maxRedeem(user) > 0, "User has no claimable redeem");
        _dumpStateWithTimestamp("07_AccountHasClaimableRedeem");

        // Redeem shares and deposit again
        vm.startPrank(user);
        BasketToken(basketToken).redeem(BasketToken(basketToken).maxRedeem(user), user, user);
        IERC20(ETH_USDC).approve(basketToken, depositAmount);
        BasketToken(basketToken).requestDeposit(depositAmount, user, user);
        vm.stopPrank();

        // Propose and complete rebalance then claim the deposit
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        _refreshPriceFeeds();
        vm.prank(rebalanceProposer);
        BasketManager(basketManager).proposeRebalance(basketTokens);
        externalTrades[0] =
            _buildSingleExternalTrade(basketToken, ETH_USDC, ETH_SUPERUSDC, targetWeights[0][1] * depositAmount / 1e18);
        externalTrades[1] =
            _buildSingleExternalTrade(basketToken, ETH_USDC, ETH_SUSDE, targetWeights[0][2] * depositAmount / 1e18);
        externalTrades[2] =
            _buildSingleExternalTrade(basketToken, ETH_USDC, ETH_SFRXUSD, targetWeights[0][3] * depositAmount / 1e18);
        externalTrades[3] = _buildSingleExternalTrade(
            basketToken, ETH_USDC, ETH_YSYG_YVUSDS_1, targetWeights[0][4] * depositAmount / 1e18
        );
        _continueAndCompleteRebalance(basketTokens, externalTrades);
        vm.prank(user);
        BasketToken(basketToken).deposit(depositAmount, user, user);

        vm.warp(vm.getBlockTimestamp() + 1 days);

        // 8. Claim rewards
        vm.prank(user);
        assertTrue(FarmingPlugin(farmingPlugin).farmed(user) > 0, "User has no rewards to claim");
        _dumpStateWithTimestamp("08_AccountHasClaimableRewards");

        // Propose rebalance and attempt to complete rebalance until max retries is reached
        // Trades are not proposed, cycle through complete and propose rebalance until max retries is reached
        vm.startPrank(user);
        BasketToken(basketToken).requestRedeem(BasketToken(basketToken).balanceOf(user), user, user);
        vm.stopPrank();

        _refreshPriceFeeds();
        vm.startPrank(rebalanceProposer);
        BasketManager(basketManager).proposeRebalance(basketTokens);
        // Complete rebalance until max retries is reached (3)
        for (uint256 i = 0; i <= BasketManager(basketManager).retryLimit(); i++) {
            BasketManager(basketManager).retryCount();
            vm.warp(vm.getBlockTimestamp() + 15 minutes);
            _refreshPriceFeeds();
            BasketManager(basketManager).completeRebalance(
                new ExternalTrade[](0),
                basketTokens,
                _getBasketTagetWeights(basketTokens),
                _getBasketAssets(basketTokens)
            );
        }
        vm.stopPrank();

        // 9. Test account has a failed redeem
        assertTrue(BasketToken(basketToken).claimableFallbackShares(user) > 0, "FallbackShares not claimable");
        _dumpStateWithTimestamp("09_AccountHasFailedRedeem");
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
        _updatePythOracleTimeStamp(PYTH_USDS_USD_FEED);
        _updatePythOracleTimeStamp(PYTH_FRXUSD_USD_FEED);

        _updateChainLinkOracleTimeStamp(ETH_CHAINLINK_SUSDE_USD_FEED);
        _updateChainLinkOracleTimeStamp(ETH_CHAINLINK_USDC_USD_FEED);
        _updateChainLinkOracleTimeStamp(ETH_CHAINLINK_USDS_USD_FEED);
        _updateChainLinkOracleTimeStamp(ETH_CHAINLINK_USDE_USD_FEED);
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
                // solhint-disable-next-line no-unused-vars
                (uint256 sellAmount, uint256 buyAmount, uint32 validTo, address swapContract) =
                    abi.decode(logs[i].data, (uint256, uint256, uint32, address));
                // Simulate the trade being executed
                takeAway(IERC20(sellToken), swapContract, sellAmount);
                // ysyG-yvUSDS-1 uses Yearn strategy v3 implementation, which relies on the total supply of the vault
                // to calculate conversion rate between shares and assets. So we don't adjust the total supply for
                // ysyG-yvUSDS-1
                bool adjustTotalSupply = buyToken != ETH_YSYG_YVUSDS_1 && buyToken != ETH_SUPERUSDC;
                airdrop(IERC20(buyToken), swapContract, buyAmount, adjustTotalSupply);
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
