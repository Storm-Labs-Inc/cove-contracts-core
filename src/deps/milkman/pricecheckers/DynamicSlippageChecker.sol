// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity 0.8.28;

import { IPriceChecker } from "src/interfaces/deps/milkman/IPriceChecker.sol";
import { IExpectedOutCalculator } from "src/interfaces/deps/milkman/IExpectedOutCalculator.sol";

/// @notice Dynamic slippage checker that evaluates solver quotes against an expected output.
/// @dev Ported from Milkman with Solidity 0.8 semantics and Cove-specific layout.
contract DynamicSlippageChecker is IPriceChecker {
    string public NAME;
    IExpectedOutCalculator public immutable EXPECTED_OUT_CALCULATOR;

    uint256 internal constant MAX_BPS = 10_000;

    constructor(string memory name_, address expectedOutCalculator) {
        NAME = name_;
        EXPECTED_OUT_CALCULATOR = IExpectedOutCalculator(expectedOutCalculator);
    }

    function checkPrice(
        uint256 amountIn,
        address fromToken,
        address toToken,
        uint256,
        uint256 minOut,
        bytes calldata data
    )
        external
        view
        override
        returns (bool)
    {
        (uint256 allowedSlippageBps, bytes memory extraData) = abi.decode(data, (uint256, bytes));

        uint256 expectedOut = EXPECTED_OUT_CALCULATOR.getExpectedOut(amountIn, fromToken, toToken, extraData);

        return minOut > (expectedOut * (MAX_BPS - allowedSlippageBps)) / MAX_BPS;
    }
}
