// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { BaseStrategy } from "tokenized-strategy-3.0.4/src/BaseStrategy.sol";

import { IMilkman } from "src/interfaces/deps/milkman/IMilkman.sol";
import { IAutopool } from "src/interfaces/deps/tokemak/IAutopool.sol";
import { IAutopoolMainRewarder } from "src/interfaces/deps/tokemak/IAutopoolMainRewarder.sol";

/// @title AutopoolCompounder
/// @notice A Yearn V3 strategy that compounds Tokemak Autopool rewards
/// @dev Accepts any Tokemak Autopool ERC4626 vault as the asset, stakes it, and compounds rewards
contract AutopoolCompounder is BaseStrategy {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// CONSTANTS ///

    /// @notice The Autopool vault (ERC4626) that this strategy manages
    IAutopool public immutable autopool;

    /// @notice The base asset of the autopool (e.g., USDC for autoUSD)
    IERC20 public immutable baseAsset;

    /// @notice The Tokemak AutopoolMainRewarder for staking
    IAutopoolMainRewarder public immutable rewarder;

    /// @notice The Milkman contract for async swaps
    IMilkman public immutable milkman;

    /// STATE VARIABLES ///

    /// @notice Mapping from reward token to its price checker
    mapping(address => address) public priceCheckerByToken;

    /// @notice Set of configured reward tokens
    EnumerableSet.AddressSet private _configuredRewardTokens;

    /// @notice Maximum deviation allowed for price checks (in basis points)
    uint256 public maxPriceDeviationBps = 500; // 5%

    /// EVENTS ///

    event PriceCheckerUpdated(address indexed rewardToken, address indexed priceChecker);
    event MaxPriceDeviationUpdated(uint256 maxDeviationBps);
    event RewardsClaimedAndSwapped(address indexed rewardToken, uint256 amount);
    event BaseAssetCompounded(uint256 amount, uint256 sharesMinted);

    /// ERRORS ///

    error ZeroAddress();
    error InvalidAsset();
    error CannotSetCheckerForAsset();
    error InvalidPriceChecker();
    error InvalidMaxDeviation();

    /// CONSTRUCTOR ///

    /// @notice Initialize the strategy
    /// @param _autopool The Tokemak Autopool vault to manage
    /// @param _rewarder The AutopoolMainRewarder contract
    /// @param _milkman The Milkman contract for swaps
    constructor(address _autopool, address _rewarder, address _milkman) BaseStrategy(_autopool, "AutopoolCompounder") {
        if (_autopool == address(0) || _rewarder == address(0) || _milkman == address(0)) {
            revert ZeroAddress();
        }

        autopool = IAutopool(_autopool);
        rewarder = IAutopoolMainRewarder(_rewarder);
        milkman = IMilkman(_milkman);

        // Verify the rewarder accepts our autopool token
        if (rewarder.stakingToken() != _autopool) {
            revert InvalidAsset();
        }

        // Get the base asset from the autopool
        baseAsset = IERC20(autopool.asset());
    }

    /// MANAGEMENT FUNCTIONS ///

    /// @notice Update the price checker for a reward token
    /// @param rewardToken The reward token address
    /// @param priceChecker The price checker contract address
    function updatePriceChecker(address rewardToken, address priceChecker) external onlyManagement {
        // Prevent setting a price checker for the autopool asset
        if (rewardToken == address(autopool)) {
            revert CannotSetCheckerForAsset();
        }

        priceCheckerByToken[rewardToken] = priceChecker;

        if (priceChecker == address(0)) {
            _configuredRewardTokens.remove(rewardToken);
        } else {
            _configuredRewardTokens.add(rewardToken);
        }

        emit PriceCheckerUpdated(rewardToken, priceChecker);
    }

    /// @notice Set the maximum price deviation for swaps
    /// @param _maxDeviationBps The max deviation in basis points
    function setMaxPriceDeviation(uint256 _maxDeviationBps) external onlyManagement {
        if (_maxDeviationBps > 10_000) {
            revert InvalidMaxDeviation();
        }
        maxPriceDeviationBps = _maxDeviationBps;
        emit MaxPriceDeviationUpdated(_maxDeviationBps);
    }

    /// KEEPER FUNCTIONS ///

    /// @notice Cancel a stuck swap and recover tokens
    /// @param amountIn The amount of tokens in the swap
    /// @param fromToken The token being swapped from
    /// @param toToken The token being swapped to
    /// @param priceChecker The price checker used in the swap
    /// @param priceCheckerData The data passed to the price checker
    /// @dev Only callable by management to recover stuck swaps
    function cancelSwap(
        uint256 amountIn,
        address fromToken,
        address toToken,
        address priceChecker,
        bytes calldata priceCheckerData
    )
        external
        onlyKeepers
    {
        // Cancel the swap in Milkman, which will transfer the tokens back to this contract
        milkman.cancelSwap(amountIn, IERC20(fromToken), IERC20(toToken), address(this), priceChecker, priceCheckerData);
    }

    /// @notice Claim rewards and initiate swaps via Milkman
    function claimRewardsAndSwap() external onlyKeepers {
        // Claim all rewards including extras
        rewarder.getReward(address(this), address(this), true);

        // Process main reward token
        address mainReward = rewarder.rewardToken();
        _processRewardToken(mainReward);

        // Also process any configured tokens that might not be in the rewarder
        uint256 configuredLen = _configuredRewardTokens.length();
        for (uint256 i = 0; i < configuredLen; i++) {
            address token = _configuredRewardTokens.at(i);
            _processRewardToken(token);
        }
    }

    /// @notice Process a single reward token for swapping
    function _processRewardToken(address token) internal {
        uint256 balance = IERC20(token).balanceOf(address(this));

        // Skip if balance is below minimum or no price checker configured
        if (balance == 0) {
            return;
        }

        address priceChecker = priceCheckerByToken[token];
        if (priceChecker == address(0)) {
            return;
        }

        // Approve Milkman and request swap
        IERC20(token).forceApprove(address(milkman), balance);
        milkman.requestSwapExactTokensForTokens(
            balance, IERC20(token), baseAsset, address(this), priceChecker, abi.encode(maxPriceDeviationBps)
        );

        emit RewardsClaimedAndSwapped(token, balance);
    }

    /// YEARN V3 STRATEGY HOOKS ///

    /// @notice Deploy funds by staking autopool tokens
    /// @param amount The amount to deploy
    function _deployFunds(uint256 amount) internal override {
        if (amount == 0) return;

        // Approve and stake autopool tokens
        IERC20(address(asset)).forceApprove(address(rewarder), amount);
        rewarder.stake(address(this), amount);
    }

    /// @notice Free funds by unstaking autopool tokens
    /// @param amount The amount to free
    function _freeFunds(uint256 amount) internal override {
        if (amount == 0) return;

        // Withdraw without claiming rewards
        rewarder.withdraw(address(this), amount, false);
    }

    /// @notice Harvest and report strategy performance
    /// @return The total assets under management
    function _harvestAndReport() internal override returns (uint256) {
        // If not shutdown, claim rewards and swap
        if (!TokenizedStrategy.isShutdown()) {
            // Compound any settled base asset
            uint256 baseBalance = baseAsset.balanceOf(address(this));
            if (baseBalance > 0) {
                // Approve and deposit base asset to get autopool shares
                baseAsset.forceApprove(address(autopool), baseBalance);

                uint256 sharesMinted = autopool.deposit(baseBalance, address(this));
                _deployFunds(sharesMinted);
            }
        }

        // Return the total balance of the strategy
        uint256 looseBalance = IERC20(address(asset)).balanceOf(address(this));
        return stakedBalance() + looseBalance;
    }

    /// VIEW FUNCTIONS ///

    /// @notice Get all configured reward tokens
    /// @return An array of configured reward token addresses
    function getConfiguredRewardTokens() external view returns (address[] memory) {
        return _configuredRewardTokens.values();
    }

    /// @notice Get the total staked balance
    /// @return The amount staked in the rewarder
    function stakedBalance() public view returns (uint256) {
        return rewarder.balanceOf(address(this));
    }

    /// @notice Get pending rewards
    /// @return The amount of pending main rewards (TOKE)
    function pendingRewards() external view returns (uint256) {
        return rewarder.earned(address(this));
    }
}
