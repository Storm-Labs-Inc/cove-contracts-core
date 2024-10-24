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
    bytes32 public constant _WEIGHT_STRATEGY_ROLE = keccak256("WEIGHT_STRATEGY_ROLE");

    // Interface IDs
    bytes4 public constant OPERATOR7540_INTERFACE = 0xe3bc4e65;
    bytes4 public constant ASYNCHRONOUS_DEPOSIT_INTERFACE = 0xce3bbe50;
    bytes4 public constant ASYNCHRONOUS_REDEMPTION_INTERFACE = 0x620ee8e4;

    // ERC1271 Magic Value
    bytes4 public constant ERC1271_MAGIC_VALUE = 0x1626ba7e;

    address public constant CREATE3_FACTORY = 0x93FEC2C00BfE902F733B57c5a6CeeD7CD1384AE1;
    // Ref: https://github.com/euler-xyz/euler-price-oracle/blob/experiments/test/adapter/pyth/PythFeeds.sol
    address public constant PYTH = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant USD = address(840); // USD ISO 4217 currency code

    // EXTERNAL WEGHT STRATEGISTS
    // TODO: Update this address
    address public constant GAUNTLET_STRATEGIST = 0x00000000000000000000000000000000DeaDBeef;

    // ASSET ADDRESSES
    address public constant ETH_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant ETH_SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;

    // PRICE FEEDS
    // ETH/USD
    bytes32 public constant PYTH_ETH_USD_FEED = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    address public constant ETH_CHAINLINK_ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    // SUSDE/USD
    bytes32 public constant PYTH_SUSE_USD_FEED = 0xca3ba9a619a4b3755c10ac7d5e760275aa95e9823d38a84fedd416856cdba37c;
    address public constant ETH_CHAINLINK_SUSDE_USD_FEED = 0xFF3BC18cCBd5999CE63E788A1c250a88626aD099;

    // COVE
    address public constant COVE_DEPLOYER_ADDRESS = 0x8842fe65A7Db9BB5De6d50e49aF19496da09F9b5;
    address public constant COVE_OPS_MULTISIG = 0x71BDC5F3AbA49538C76d58Bc2ab4E3A1118dAe4c;
    address public constant COVE_COMMUNITY_MULTISIG = 0x7Bd578354b0B2f02E656f1bDC0e41a80f860534b;

    // Constants hardcoded in the contracts, replicated here for testing.
    uint16 public constant MAX_MANAGEMENT_FEE = 1e4;
    uint16 public constant MAX_SWAP_FEE = 30;
    uint8 public constant MAX_RETRIES = 3;

    // https://evc.wtf/docs/contracts/deployment-addresses/
    address public constant EVC = 0x0C9a3dd6b8F28529d72d7f9cE918D493519EE383;
}
