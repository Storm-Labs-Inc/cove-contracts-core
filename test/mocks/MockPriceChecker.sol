// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IPriceChecker } from "src/interfaces/deps/milkman/IPriceChecker.sol";

contract MockPriceChecker is IPriceChecker {
    bool public shouldApprove = true;
    uint256 public minOutputRequired;
    
    function checkPrice(
        uint256 amountIn,
        address fromToken,
        address toToken,
        uint256 minOut,
        bytes calldata data
    ) external view returns (bool) {
        // Simple mock: approve if minOut meets threshold
        if (minOutputRequired > 0) {
            return minOut >= minOutputRequired;
        }
        return shouldApprove;
    }
    
    function setShouldApprove(bool approve) external {
        shouldApprove = approve;
    }
    
    function setMinOutputRequired(uint256 minOutput) external {
        minOutputRequired = minOutput;
    }
}