// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { AllocationResolver } from "./AllocationResolver.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

/// @title AggregatedResolver
/// @notice An aggregated resolver that acts as a registry of supported resolvers.
/// @dev Inherits from AccessControlEnumerable for role-based access control.
/// Roles:
/// - DEFAULT_ADMIN_ROLE: The default role for the contract creator. Can grant and revoke roles.
/// - ALLOCATION_RESOLVER_ROLE: Role for approved allocation resolvers.
contract AggregatedResolver is AccessControlEnumerable {
    /// @dev Role identifier for allocation resolvers
    bytes32 private constant _ALLOCATION_RESOLVER_ROLE = keccak256("ALLOCATION_RESOLVER");

    /// @dev Error thrown when an unsupported resolver is used
    error ResolverNotSupported();

    /// @notice Constructs the AggregatedResolver contract
    /// @param admin The address that will be granted the DEFAULT_ADMIN_ROLE
    // slither-disable-next-line locked-ether
    constructor(address admin) payable {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Checks if a given allocation resolver supports a specific bit flag
    /// @param bitFlag The bit flag to check support for
    /// @param allocationResolver The address of the allocation resolver to check
    /// @return bool True if the resolver supports the bit flag, false otherwise
    function supportsBitFlag(uint256 bitFlag, address allocationResolver) external view returns (bool) {
        if (!hasRole(_ALLOCATION_RESOLVER_ROLE, allocationResolver)) {
            revert ResolverNotSupported();
        }
        return AllocationResolver(allocationResolver).supportsBitFlag(bitFlag);
    }

    /// @dev TODO: remove this after BasketManager is refactored to use AssetRegistry.getAssets(bitFlag)
    function getAssets(uint256) external view returns (address[] memory) {
        return new address[](0);
    }
}
