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

    bytes4 public constant OPERATOR7540_INTERFACE = 0xe3bc4e65;
    bytes4 public constant ASYNCHRONOUS_DEPOSIT_INTERFACE = 0xce3bbe50;
    bytes4 public constant ASYNCHRONOUS_REDEMPTION_INTERFACE = 0x620ee8e4;

    bytes4 public constant ERC1271_MAGIC_VALUE = 0x1626ba7e;
    uint16 public constant _MANAGEMENT_FEE_DECIMALS = 1e4;
    uint16 public constant _MAX_MANAGEMENT_FEE = 1e4;
    uint8 public constant _MAX_RETRIES = 3;
}
