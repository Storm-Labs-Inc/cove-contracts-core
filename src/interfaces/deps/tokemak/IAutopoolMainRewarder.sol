// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/// @title IAutopoolMainRewarder
/// @notice Interface for Tokemak's AutopoolMainRewarder contract
/// @dev Used to stake autopool vault tokens and claim rewards
interface IAutopoolMainRewarder {
    /// @notice Stakes autopool tokens for a given account
    /// @param account The account to stake for
    /// @param amount The amount of autopool tokens to stake
    function stake(address account, uint256 amount) external;

    /// @notice Withdraws staked autopool tokens
    /// @param account The account to withdraw for
    /// @param amount The amount to withdraw
    /// @param claim Whether to claim rewards
    function withdraw(address account, uint256 amount, bool claim) external;

    /// @notice Claims rewards for an account
    /// @param account The account to claim for
    /// @param recipient The recipient of the rewards
    /// @param claimExtras Whether to claim extra rewards
    function getReward(address account, address recipient, bool claimExtras) external;

    /// @notice Returns the balance of staked tokens for an account
    /// @param account The account to check
    /// @return The staked balance
    function balanceOf(address account) external view returns (uint256);

    /// @notice Returns the amount of earned rewards for an account
    /// @param account The account to check
    /// @return The earned rewards
    function earned(address account) external view returns (uint256);

    /// @notice Returns the main reward token address
    /// @return The reward token address
    function rewardToken() external view returns (address);

    /// @notice Returns the staking token (autopool vault token)
    /// @return The staking token address
    function stakingToken() external view returns (address);

    /// @notice Returns the number of extra reward contracts
    /// @return The count of extra rewards
    function extraRewardsLength() external view returns (uint256);

    /// @notice Returns an extra reward contract at index
    /// @param index The index of the extra reward
    /// @return The extra reward contract address
    function extraRewards(uint256 index) external view returns (address);
}