// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { BaseStrategy, ERC20 } from "tokenized-strategy-3.0.4/src/BaseStrategy.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IAutopoolMainRewarder } from "src/interfaces/deps/tokemak/IAutopoolMainRewarder.sol";
import { IAutopool } from "src/interfaces/deps/tokemak/IAutopool.sol";
import { IMilkman } from "src/interfaces/deps/milkman/IMilkman.sol";
import { IPriceChecker } from "src/interfaces/deps/milkman/IPriceChecker.sol";

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
    EnumerableSet.AddressSet private configuredRewardTokens;
    
    /// @notice Minimum amount of reward token to trigger a swap
    mapping(address => uint256) public minRewardToSell;
    
    /// @notice Minimum amount of base asset to trigger compounding
    uint256 public minBaseAssetToCompound;
    
    /// @notice Maximum deviation allowed for price checks (in basis points)
    uint256 public maxPriceDeviationBps = 500; // 5%

    /// EVENTS ///
    
    event PriceCheckerUpdated(address indexed rewardToken, address indexed priceChecker);
    event MinRewardToSellUpdated(address indexed rewardToken, uint256 minAmount);
    event MinBaseAssetToCompoundUpdated(uint256 minAmount);
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
    constructor(
        address _autopool,
        address _rewarder,
        address _milkman
    ) BaseStrategy(
        _autopool,
        "AutopoolCompounder"
    ) {
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
        
        // Set default minimum amounts
        minBaseAssetToCompound = 100 * 10 ** ERC20(address(baseAsset)).decimals();
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
            configuredRewardTokens.remove(rewardToken);
        } else {
            configuredRewardTokens.add(rewardToken);
        }
        
        emit PriceCheckerUpdated(rewardToken, priceChecker);
    }
    
    /// @notice Set the minimum reward amount to trigger a swap
    /// @param rewardToken The reward token
    /// @param minAmount The minimum amount
    function setMinRewardToSell(address rewardToken, uint256 minAmount) external onlyManagement {
        minRewardToSell[rewardToken] = minAmount;
        emit MinRewardToSellUpdated(rewardToken, minAmount);
    }
    
    /// @notice Set the minimum base asset amount to trigger compounding
    /// @param minAmount The minimum amount
    function setMinBaseAssetToCompound(uint256 minAmount) external onlyManagement {
        minBaseAssetToCompound = minAmount;
        emit MinBaseAssetToCompoundUpdated(minAmount);
    }
    
    /// @notice Set the maximum price deviation for swaps
    /// @param _maxDeviationBps The max deviation in basis points
    function setMaxPriceDeviation(uint256 _maxDeviationBps) external onlyManagement {
        if (_maxDeviationBps > 10000) {
            revert InvalidMaxDeviation();
        }
        maxPriceDeviationBps = _maxDeviationBps;
        emit MaxPriceDeviationUpdated(_maxDeviationBps);
    }

    /// KEEPER FUNCTIONS ///
    
    /// @notice Claim rewards and initiate swaps via Milkman
    function claimRewardsAndSwap() external onlyKeepers {
        // Claim all rewards including extras
        rewarder.getReward(address(this), address(this), true);
        
        // Process main reward token
        address mainReward = rewarder.rewardToken();
        _processRewardToken(mainReward);
        
        // Process extra rewards
        uint256 extraRewardsLen = rewarder.extraRewardsLength();
        for (uint256 i = 0; i < extraRewardsLen; i++) {
            address extraReward = rewarder.extraRewards(i);
            _processRewardToken(extraReward);
        }
        
        // Also process any configured tokens that might not be in the rewarder
        uint256 configuredLen = configuredRewardTokens.length();
        for (uint256 i = 0; i < configuredLen; i++) {
            address token = configuredRewardTokens.at(i);
            _processRewardToken(token);
        }
    }
    
    /// @notice Process a single reward token for swapping
    function _processRewardToken(address token) internal {
        uint256 balance = IERC20(token).balanceOf(address(this));
        
        // Skip if balance is below minimum or no price checker configured
        if (balance == 0 || balance < minRewardToSell[token]) {
            return;
        }
        
        address priceChecker = priceCheckerByToken[token];
        if (priceChecker == address(0)) {
            return;
        }
        
        // Approve Milkman and request swap
        IERC20(token).forceApprove(address(milkman), balance);
        
        bytes memory priceCheckerData = abi.encode(maxPriceDeviationBps);
        
        milkman.requestSwapExactTokensForTokens(
            balance,
            IERC20(token),
            baseAsset,
            address(this),
            priceChecker,
            priceCheckerData
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
            // Claim and swap rewards
            this.claimRewardsAndSwap();
            
            // Compound any settled base asset
            uint256 baseBalance = baseAsset.balanceOf(address(this));
            if (baseBalance >= minBaseAssetToCompound) {
                // Approve and deposit base asset to get autopool shares
                baseAsset.safeApprove(address(autopool), 0);
                baseAsset.safeApprove(address(autopool), baseBalance);
                
                uint256 sharesMinted = autopool.deposit(baseBalance, address(this));
                
                // Immediately stake the new shares
                _deployFunds(sharesMinted);
                
                emit BaseAssetCompounded(baseBalance, sharesMinted);
            }
        }
        
        // Calculate total assets (loose + staked autopool tokens)
        uint256 looseBalance = IERC20(address(asset)).balanceOf(address(this));
        uint256 stakedBalance = rewarder.balanceOf(address(this));
        
        return looseBalance + stakedBalance;
    }
    
    /// @notice Check if we should trigger a harvest
    /// @param callCost The cost of calling harvest
    /// @return True if harvest should be triggered
    function harvestTrigger(uint256 callCost) public view override returns (bool) {
        // Check if we have claimable rewards above threshold
        uint256 earnedRewards = rewarder.earned(address(this));
        if (earnedRewards > minRewardToSell[rewarder.rewardToken()]) {
            return true;
        }
        
        // Check if we have base asset to compound
        if (baseAsset.balanceOf(address(this)) >= minBaseAssetToCompound) {
            return true;
        }
        
        // Use default trigger logic
        return super.harvestTrigger(callCost);
    }

    /// VIEW FUNCTIONS ///
    
    /// @notice Get all configured reward tokens
    /// @return An array of configured reward token addresses
    function getConfiguredRewardTokens() external view returns (address[] memory) {
        return configuredRewardTokens.values();
    }
    
    /// @notice Get the total staked balance
    /// @return The amount staked in the rewarder
    function stakedBalance() external view returns (uint256) {
        return rewarder.balanceOf(address(this));
    }
    
    /// @notice Get pending rewards
    /// @return The amount of pending main rewards
    function pendingRewards() external view returns (uint256) {
        return rewarder.earned(address(this));
    }
}