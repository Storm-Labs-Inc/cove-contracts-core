// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { AllocationResolver } from "./AllocationResolver.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

contract AggregatedResolver is AllocationResolver, AccessControlEnumerable {
    // slither-disable-next-line locked-ether
    constructor() payable {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function getTargetWeights(address basket) public view override returns (uint256[] memory) { }

    function supportsAssets(address[] memory assets) public view override returns (bool) { }
}
