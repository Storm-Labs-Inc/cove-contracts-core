// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/// @title MathUtils
/// @notice A library to perform math operations with optimizations.
/// @dev This library is based on the code snippet from the OpenZeppelin Contracts Math library.
// solhint-disable-next-line max-line-length
/// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/05d4bf57ffed8c65256ff4ede5c3cf7a0b738e7d/contracts/utils/math/Math.sol
library MathUtils {
    /// @dev Cast a boolean (false or true) to a uint256 (0 or 1) with no jump.
    function toUint(bool b) internal pure returns (uint256 u) {
        /// @solidity memory-safe-assembly
        // solhint-disable no-inline-assembly
        // slither-disable-next-line assembly
        assembly {
            u := iszero(iszero(b))
        }
        // solhint-enable no-inline-assembly
    }

    /// @dev Branchless ternary evaluation for `a ? b : c`. Gas costs are constant.
    ///
    /// IMPORTANT: This function may reduce bytecode size and consume less gas when used standalone.
    /// However, the compiler may optimize Solidity ternary operations (i.e. `a ? b : c`) to only compute
    /// one branch when needed, making this function more expensive.
    function ternary(bool condition, uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            // branchless ternary works because:
            // b ^ (a ^ b) == a
            // b ^ 0 == b
            return b ^ ((a ^ b) * toUint(condition));
        }
    }

    /// @dev Returns the largest of two numbers.
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return ternary(a > b, a, b);
    }

    /// @dev Returns the smallest of two numbers.
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return ternary(a < b, a, b);
    }

    /// @dev Returns the average of two numbers. The result is rounded towards
    /// zero.
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    function diff(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            // TODO: Measure the gas costs of the following line after more test cases are added.
            // return ternary(a > b, a - b, b - a);
            return a > b ? a - b : b - a;
        }
    }
}
