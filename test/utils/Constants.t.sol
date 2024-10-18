// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

contract Constants {
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant BASKET_MANAGER_ROLE = keccak256("BASKET_MANAGER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant BASKET_TOKEN_ROLE = keccak256("BASKET_TOKEN_ROLE");
    bytes32 public constant TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");

    // Interface IDs
    bytes4 public constant OPERATOR7540_INTERFACE = 0xe3bc4e65;
    bytes4 public constant ASYNCHRONOUS_DEPOSIT_INTERFACE = 0xce3bbe50;
    bytes4 public constant ASYNCHRONOUS_REDEMPTION_INTERFACE = 0x620ee8e4;

    // ERC1271 Magic Value
    bytes4 public constant ERC1271_MAGIC_VALUE = 0x1626ba7e;

    // Constants hardcoded in the contracts, replicated here for testing.
    uint16 public constant MAX_MANAGEMENT_FEE = 1e4;
    uint16 public constant MAX_SWAP_FEE = 30;
    uint8 public constant MAX_RETRIES = 3;

    // https://evc.wtf/docs/contracts/deployment-addresses/
    address public constant EVC = 0x0C9a3dd6b8F28529d72d7f9cE918D493519EE383;
}
