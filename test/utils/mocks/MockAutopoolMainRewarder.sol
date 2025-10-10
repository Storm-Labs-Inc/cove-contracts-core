// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAutopoolMainRewarder } from "src/interfaces/deps/tokemak/IAutopoolMainRewarder.sol";

contract MockAutopoolMainRewarder is IAutopoolMainRewarder {
    using SafeERC20 for IERC20;

    address public immutable stakingToken;
    address public immutable rewardToken;

    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public earned;
    address[] public extraRewards;

    uint256 public rewardRate = 1e18; // 1 token per second per staked token
    mapping(address => uint256) public lastUpdateTime;

    constructor(address _stakingToken, address _rewardToken) {
        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
    }

    function stake(address account, uint256 amount) external {
        _updateReward(account);
        IERC20(stakingToken).safeTransferFrom(msg.sender, address(this), amount);
        balanceOf[account] += amount;
    }

    function withdraw(address account, uint256 amount, bool claim) external {
        _updateReward(account);
        balanceOf[account] -= amount;
        IERC20(stakingToken).safeTransfer(account, amount);

        if (claim) {
            this.getReward(account, account, true);
        }
    }

    function getReward(address account, address recipient, bool claimExtras) external {
        _updateReward(account);
        uint256 reward = earned[account];
        if (reward > 0) {
            earned[account] = 0;
            // In mock, just mint rewards for simplicity
            deal(rewardToken, recipient, reward);
        }

        if (claimExtras) {
            // Handle extra rewards if needed
            for (uint256 i = 0; i < extraRewards.length; i++) {
                // Mock implementation - just transfer some tokens
                deal(extraRewards[i], recipient, 1e18);
            }
        }
    }

    function _updateReward(address account) internal {
        if (lastUpdateTime[account] == 0) {
            lastUpdateTime[account] = block.timestamp;
            return;
        }

        uint256 timeDelta = block.timestamp - lastUpdateTime[account];
        uint256 reward = (balanceOf[account] * rewardRate * timeDelta) / 1e18;
        earned[account] += reward;
        lastUpdateTime[account] = block.timestamp;
    }

    function extraRewardsLength() external view returns (uint256) {
        return extraRewards.length;
    }

    function addExtraReward(address reward) external {
        extraRewards.push(reward);
    }

    function setRewardRate(uint256 rate) external {
        rewardRate = rate;
    }

    function setEarned(address account, uint256 amount) external {
        earned[account] = amount;
    }

    // Helper function to deal tokens in tests
    function deal(address token, address to, uint256 amount) internal {
        // This would use vm.deal or similar in actual tests
        // For now, just a placeholder
        bytes memory data = abi.encodeWithSignature("mint(address,uint256)", to, amount);
        (bool success,) = token.call(data);
        if (!success) {
            // Try transfer if mint doesn't work
            IERC20(token).safeTransfer(to, amount);
        }
    }
}
