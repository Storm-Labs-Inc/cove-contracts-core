// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IMilkman } from "src/interfaces/deps/milkman/IMilkman.sol";

contract MockMilkman is IMilkman {
    using SafeERC20 for IERC20;

    struct SwapRequest {
        uint256 amountIn;
        address fromToken;
        address toToken;
        address to;
        bytes32 appData;
        address priceChecker;
        bytes priceCheckerData;
        bool executed;
    }

    mapping(uint256 => SwapRequest) public swapRequests;
    uint256 public nextRequestId;

    // For testing: immediate swap execution ratio (e.g., 950 = 95% of value)
    uint256 public swapRatio = 950; // 95%

    function requestSwapExactTokensForTokens(
        uint256 amountIn,
        IERC20 fromToken,
        IERC20 toToken,
        address to,
        bytes32 appData,
        address priceChecker,
        bytes calldata priceCheckerData
    )
        external
    {
        // Transfer tokens from sender
        fromToken.safeTransferFrom(msg.sender, address(this), amountIn);

        // Store swap request
        swapRequests[nextRequestId] = SwapRequest({
            amountIn: amountIn,
            fromToken: address(fromToken),
            toToken: address(toToken),
            to: to,
            appData: appData,
            priceChecker: priceChecker,
            priceCheckerData: priceCheckerData,
            executed: false
        });

        emit SwapRequested(
            address(this),
            msg.sender,
            amountIn,
            address(fromToken),
            address(toToken),
            to,
            appData,
            priceChecker,
            priceCheckerData
        );

        nextRequestId++;
    }

    function cancelSwap(
        uint256 amountIn,
        IERC20 fromToken,
        IERC20 toToken,
        address to,
        address priceChecker,
        bytes calldata /*priceCheckerData*/
    )
        external
    {
        // For testing: Find the matching swap request and mark as cancelled
        // In real Milkman, this would verify the swap hash
        for (uint256 i = 0; i < nextRequestId; i++) {
            SwapRequest storage request = swapRequests[i];
            if (
                !request.executed && request.amountIn == amountIn && request.fromToken == address(fromToken)
                    && request.toToken == address(toToken) && request.to == to && request.priceChecker == priceChecker
            ) {
                // Transfer tokens back to the sender (strategy)
                fromToken.safeTransfer(msg.sender, amountIn);
                request.executed = true; // Mark as handled
                return;
            }
        }

        // If no matching swap found, just transfer tokens back
        // (simulating that Milkman has the tokens)
        fromToken.safeTransfer(msg.sender, amountIn);
    }

    // Mock function to simulate swap execution
    function executeSwap(uint256 requestId) external {
        SwapRequest storage request = swapRequests[requestId];
        require(!request.executed, "Already executed");

        request.executed = true;

        // Calculate output amount (simplified mock logic)
        uint256 outputAmount = (request.amountIn * swapRatio) / 1000;

        // Mock the swap by minting output tokens
        deal(request.toToken, request.to, outputAmount);
    }

    function setSwapRatio(uint256 ratio) external {
        swapRatio = ratio;
    }

    // Helper function to deal tokens in tests
    function deal(address token, address to, uint256 amount) internal {
        // This would use vm.deal or similar in actual tests
        bytes memory data = abi.encodeWithSignature("mint(address,uint256)", to, amount);
        (bool success,) = token.call(data);
        if (!success) {
            // Try transfer if mint doesn't work
            IERC20(token).safeTransfer(to, amount);
        }
    }
}
