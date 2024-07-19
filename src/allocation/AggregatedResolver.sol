// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { AssetRegistry } from "./../AssetRegistry.sol";
import { AllocationResolver } from "./AllocationResolver.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

/// @title AggregatedResolver
/// @notice An aggregated resolver that stores baskets preferred AllocationResolver contracts.
/// Roles
/// DEFAULT_ADMIN_ROLE: The default role for the contract creator. Can grant and revoke roles.
contract AggregatedResolver is AccessControlEnumerable {
    address public immutable assetRegistry;

    bytes32 private constant _ALLOCATION_RESOLVER_ROLE = keccak256("ALLOCATION_RESOLVER");

    mapping(address resolver => bool) public supportedResolvers;

    error ResolverNotSupported();

    // slither-disable-next-line locked-ether
    constructor(address assetRegistry_) payable {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        assetRegistry = assetRegistry_;
    }

    function addAllocationResolver(address allocationResolver) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "AggregatedResolver: must have admin role to add allocation resolver"
        );
        require(
            AllocationResolver(allocationResolver).assetRegistry() == assetRegistry,
            "AggregatedResolver: asset registry mismatch"
        );
        _grantRole(_ALLOCATION_RESOLVER_ROLE, allocationResolver);
    }

    function supportsBitFlag(address allocationResolver, uint256 bitFlag) public view returns (bool) {
        if (!supportedResolvers[allocationResolver]) {
            revert ResolverNotSupported();
        }
        return AllocationResolver(allocationResolver).supportsBitFlag(bitFlag);
    }

    function getTargetWeights(address basket) public view returns (uint256[] memory) {
        return AllocationResolver(BasketToken(basket).allocationResolver()).getTargetWeights(basket);
    }
}
