// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

/// @title StrategyRegistryMock
/// @notice A mock implementation of StrategyRegistry for testing purposes
/// @dev This mock allows testing without requiring actual weight strategy implementations
contract StrategyRegistryMock is AccessControlEnumerable {
    /// @dev Role identifier for weight strategies
    bytes32 private constant _WEIGHT_STRATEGY_ROLE = keccak256("WEIGHT_STRATEGY_ROLE");

    /// @notice Error thrown when an unsupported strategy is used
    error StrategyNotSupported();

    /// @notice Mapping to store mock support for bit flags by strategy
    mapping(address => mapping(uint256 => bool)) public mockBitFlagSupport;

    /// @notice Mapping to store registered strategies
    mapping(address => bool) public registeredStrategies;

    /// @notice Constructs the StrategyRegistryMock contract
    /// @param admin The address that will be granted the DEFAULT_ADMIN_ROLE
    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Mock function to register a strategy
    /// @param strategy The address of the strategy to register
    function registerStrategy(address strategy) external onlyRole(DEFAULT_ADMIN_ROLE) {
        registeredStrategies[strategy] = true;
        _grantRole(_WEIGHT_STRATEGY_ROLE, strategy);
    }

    /// @notice Mock function to unregister a strategy
    /// @param strategy The address of the strategy to unregister
    function unregisterStrategy(address strategy) external onlyRole(DEFAULT_ADMIN_ROLE) {
        registeredStrategies[strategy] = false;
        _revokeRole(_WEIGHT_STRATEGY_ROLE, strategy);
    }

    /// @notice Mock function to set bit flag support for a strategy
    /// @param strategy The address of the strategy
    /// @param bitFlag The bit flag to set support for
    /// @param supported Whether the strategy should support this bit flag
    function setBitFlagSupport(
        address strategy,
        uint256 bitFlag,
        bool supported
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        mockBitFlagSupport[strategy][bitFlag] = supported;
    }

    /// @notice Mock function to set bit flag support for multiple strategies
    /// @param strategies Array of strategy addresses
    /// @param bitFlags Array of bit flags
    /// @param supported Whether the strategies should support these bit flags
    function setBitFlagSupportBatch(
        address[] calldata strategies,
        uint256[] calldata bitFlags,
        bool supported
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(strategies.length == bitFlags.length, "Array lengths mismatch");
        for (uint256 i = 0; i < strategies.length; i++) {
            mockBitFlagSupport[strategies[i]][bitFlags[i]] = supported;
        }
    }

    /// @notice Checks if a given weight strategy supports a specific bit flag
    /// @param bitFlag The bit flag to check support for
    /// @param weightStrategy The address of the weight strategy to check
    /// @return bool True if the strategy supports the bit flag, false otherwise
    function supportsBitFlag(uint256 bitFlag, address weightStrategy) external view returns (bool) {
        if (!hasRole(_WEIGHT_STRATEGY_ROLE, weightStrategy)) {
            revert StrategyNotSupported();
        }
        return mockBitFlagSupport[weightStrategy][bitFlag];
    }

    /// @notice Mock function to check if a strategy is registered
    /// @param strategy The address of the strategy to check
    /// @return bool True if the strategy is registered, false otherwise
    function isStrategyRegistered(address strategy) external view returns (bool) {
        return registeredStrategies[strategy];
    }

    /// @notice Mock function to get all registered strategies (for testing)
    /// @return strategies Array of registered strategy addresses
    function getRegisteredStrategies() external view returns (address[] memory strategies) {
        // This is a simplified implementation for testing
        // In a real scenario, you might want to maintain a separate array
        return new address[](0);
    }

    /// @notice Mock function to clear all mock data
    function clearMockData() external onlyRole(DEFAULT_ADMIN_ROLE) {
        // This function can be used to reset the mock state for testing
    }
}
