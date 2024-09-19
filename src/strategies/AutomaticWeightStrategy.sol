// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { WeightStrategy } from "./WeightStrategy.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

/// @title AutomaticWeightStrategy
/// @notice A strategy that returns the target weights based on external market cap data. This could be used for
/// other purposes as well such as volume, liquidity, etc as long as the data is available on chain.
/// Setters should not be implemented in this contract as the data is expected to be external and read-only.
contract AutomaticWeightStrategy is WeightStrategy, AccessControlEnumerable {
    // slither-disable-next-line locked-ether
    constructor(address admin) payable {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function getTargetWeights(
        uint40 epoch,
        uint256 bitFlag
    )
        public
        view
        virtual
        override
        returns (uint64[] memory targetWeights)
    { }

    function supportsBitFlag(uint256 bitFlag) public view virtual override returns (bool) { }
}
