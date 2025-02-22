// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { CommonBase } from "forge-std/Base.sol";

contract Constants is CommonBase {
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant BASKET_MANAGER_ROLE = keccak256("BASKET_MANAGER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant REBALANCE_PROPOSER_ROLE = keccak256("REBALANCE_PROPOSER_ROLE");
    bytes32 public constant TOKENSWAP_PROPOSER_ROLE = keccak256("TOKENSWAP_PROPOSER_ROLE");
    bytes32 public constant TOKENSWAP_EXECUTOR_ROLE = keccak256("TOKENSWAP_EXECUTOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant BASKET_TOKEN_ROLE = keccak256("BASKET_TOKEN_ROLE");
    bytes32 public constant TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");
    bytes32 public constant _WEIGHT_STRATEGY_ROLE = keccak256("WEIGHT_STRATEGY_ROLE");

    // Interface IDs
    bytes4 public constant OPERATOR7540_INTERFACE = 0xe3bc4e65;
    bytes4 public constant ASYNCHRONOUS_DEPOSIT_INTERFACE = 0xce3bbe50;
    bytes4 public constant ASYNCHRONOUS_REDEMPTION_INTERFACE = 0x620ee8e4;

    // PERMIT (ERC-2612)
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    // PERMIT 2
    /// @dev The address of the Permit2 contract the library will use.
    address internal constant ETH_PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // ERC1271 Magic Value
    bytes4 public constant ERC1271_MAGIC_VALUE = 0x1626ba7e;

    address public constant CREATE3_FACTORY = 0x93FEC2C00BfE902F733B57c5a6CeeD7CD1384AE1;
    // Ref: https://github.com/euler-xyz/euler-price-oracle/blob/experiments/test/adapter/pyth/PythFeeds.sol
    address public constant PYTH = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant USD = address(840); // USD ISO 4217 currency code
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    // EXTERNAL WEIGHT STRATEGISTS
    address public constant GAUNTLET_STRATEGIST = 0x581678F6D676dbD0ba57251324613aB48E9E28Db;

    // ASSET ADDRESSES
    address public constant ETH_CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address public constant ETH_EZETH = 0xbf5495Efe5DB9ce00f80364C8B423567e58d2110;
    address public constant ETH_GHO = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
    address public constant ETH_RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address public constant ETH_RSETH = 0xA1290d69c65A6Fe4DF752f95823fae25cB99e5A7;
    address public constant ETH_SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address public constant ETH_TBTC = 0x18084fbA666a33d37592fA2633fD49a74DD93a88;
    address public constant ETH_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant ETH_WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant ETH_WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address public constant ETH_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant ETH_SDAI = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    address public constant ETH_SFRAX = 0xA663B02CF0a4b149d2aD41910CB81e23e1c41c32;
    address public constant ETH_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant ETH_DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant ETH_FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address public constant ETH_USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    // PRICE FEEDS
    // USDC/USD
    bytes32 public constant PYTH_USDC_USD_FEED = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
    address public constant ETH_CHAINLINK_USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    // DAI/USD
    bytes32 public constant PYTH_DAI_USD_FEED = 0xb0948a5e5313200c632b51bb5ca32f6de0d36e9950a942d19751e833f70dabfd;
    address public constant ETH_CHAINLINK_DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;

    // FRAX/USD
    bytes32 public constant PYTH_FRAX_USD_FEED = 0xc3d5d8d6d17081b3d0bbca6e2fa3a6704bb9a9561d9f9e1dc52db47629f862ad;
    address public constant ETH_CHAINLINK_FRAX_USD_FEED = 0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD;

    // USDE/USD
    bytes32 public constant PYTH_USDE_USD_FEED = 0x6ec879b1e9963de5ee97e9c8710b742d6228252a5e2ca12d4ae81d7fe5ee8c5d;
    address public constant ETH_CHAINLINK_USDE_USD_FEED = 0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961;

    // ETH/USD
    bytes32 public constant PYTH_ETH_USD_FEED = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    address public constant ETH_CHAINLINK_ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    // SUSDE/USD
    bytes32 public constant PYTH_SUSDE_USD_FEED = 0xca3ba9a619a4b3755c10ac7d5e760275aa95e9823d38a84fedd416856cdba37c;
    address public constant ETH_CHAINLINK_SUSDE_USD_FEED = 0xFF3BC18cCBd5999CE63E788A1c250a88626aD099;

    // weETH/ETH
    bytes32 public constant PYTH_WEETH_USD_FEED = 0x9ee4e7c60b940440a261eb54b6d8149c23b580ed7da3139f7f08f4ea29dad395;
    address public constant ETH_CHAINLINK_WEETH_ETH_FEED = 0x5c9C449BbC9a6075A2c061dF312a35fd1E05fF22;

    // ezETH/ETH
    // TODO: pyth price feed not found
    bytes32 public constant PYTH_EZETH_USD_FEED = 0x06c217a791f5c4f988b36629af4cb88fad827b2485400a358f3b02886b54de92;
    address public constant ETH_CHAINLINK_EZETH_ETH_FEED = 0x636A000262F6aA9e1F094ABF0aD8f645C44f641C;

    // rsETH/ETH
    // TODO: pyth price feed not found
    bytes32 public constant PYTH_RSETH_USD_FEED = 0x0caec284d34d836ca325cf7b3256c078c597bc052fbd3c0283d52b581d68d71f;
    address public constant ETH_CHAINLINK_RSETH_ETH_FEED = 0x03c68933f7a3F76875C0bc670a58e69294cDFD01;

    // rETH/ETH
    bytes32 public constant PYTH_RETH_USD_FEED = 0xa0255134973f4fdf2f8f7808354274a3b1ebc6ee438be898d045e8b56ba1fe13;
    address public constant ETH_CHAINLINK_RETH_ETH_FEED = 0x536218f9E9Eb48863970252233c8F271f554C2d0;

    // wBTC/BTC
    bytes32 public constant PYTH_WBTC_USD_FEED = 0xc9d8b075a5c69303365ae23633d4e085199bf5c520a3b90fed1322a0342ffc33;
    address public constant ETH_CHAINLINK_WBTC_BTC_FEED = 0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23;

    // tBTC/BTC
    bytes32 public constant PYTH_TBTC_USD_FEED = 0x56a3121958b01f99fdc4e1fd01e81050602c7ace3a571918bb55c6a96657cca9;
    address public constant ETH_CHAINLINK_TBTC_BTC_FEED = 0x8350b7De6a6a2C1368E7D4Bd968190e13E354297;

    // GHO/USD
    // TODO: pyth price feed not found
    bytes32 public constant PYTH_GHO_USD_FEED = 0x2a0e948f637a8c251d9f06055e72eb4b3880dd57848bbdb02993c8165d7df4ee;
    address public constant ETH_CHAINLINK_GHO_USD_FEED = 0x3f12643D3f6f874d39C2a4c9f2Cd6f2DbAC877FC;

    // cbBTC/USD
    // TODO: pyth price feed not found
    bytes32 public constant PYTH_CBBTC_USD_FEED = 0x2817d7bfe5c64b8ea956e9a26f573ef64e72e4d7891f2d6af9bcc93f7aff9a97;
    address public constant ETH_CHAINLINK_CBBTC_USD_FEED = 0x2665701293fCbEB223D11A08D826563EDcCE423A;

    // COVE
    address public constant COVE_DEPLOYER_ADDRESS = 0x8842fe65A7Db9BB5De6d50e49aF19496da09F9b5;
    address public constant COVE_OPS_MULTISIG = 0x71BDC5F3AbA49538C76d58Bc2ab4E3A1118dAe4c;
    address public constant COVE_COMMUNITY_MULTISIG = 0x7Bd578354b0B2f02E656f1bDC0e41a80f860534b;
    address public constant COVE_MASTER_REGISTRY = 0x91cf20C03bEC656BC008fB2a2177bC3caA34f772;
    address public constant COVE_SILVERBACK_AWS_ACCOUNT = 0xd31336617fC8B5Ee3b162d88e75B9236a9be3d6D;

    // STAGING
    // 1 out of 5 addresses, ops multisig signers + deployer
    // https://app.safe.global/settings/setup?safe=eth:0xaAc26aee89DeEFf5D0BE246391FABDfa547dc70C
    address public constant COVE_STAGING_OPS_MULTISIG = 0xaAc26aee89DeEFf5D0BE246391FABDfa547dc70C;
    // 1 out of 5 addresses, ops multisig signers + deployer
    // https://app.safe.global/settings/setup?safe=eth:0xC8edE693E4B8cdf4F3C42bf141D9054050E5a728
    address public constant COVE_STAGING_COMMUNITY_MULTISIG = 0xC8edE693E4B8cdf4F3C42bf141D9054050E5a728;
    address public constant COVE_STAGING_MASTER_REGISTRY = 0x44bB20e5A3CC2cBdfB7520Aa76281019723382Cb;

    // Constants hardcoded in the contracts, replicated here for testing.
    uint16 public constant MAX_MANAGEMENT_FEE = 3000;
    uint16 public constant MAX_SWAP_FEE = 500;
    uint8 public constant MAX_RETRIES = 3;
    uint256 public constant REBALANCE_COOLDOWN_SEC = 1 hours;

    // https://evc.wtf/docs/contracts/deployment-addresses/
    address public constant EVC = 0x0C9a3dd6b8F28529d72d7f9cE918D493519EE383;

    // This block number includes all pyth oracle updates
    // https://etherscan.io/tx/0xdb4a012e6c07cc6417c6c2fd020e110ea40fd1207221bbbc5e346045b9b26ecd
    uint256 public constant BLOCK_NUMBER_MAINNET_FORK = 21_792_603;

    function labelKnownAddresses() public {
        // Cove addresses
        vm.label(COVE_DEPLOYER_ADDRESS, "COVE DEPLOYER");
        vm.label(COVE_OPS_MULTISIG, "COVE OPS MULTISIG");
        vm.label(COVE_COMMUNITY_MULTISIG, "COVE COMMUNITY MULTISIG");
        vm.label(COVE_MASTER_REGISTRY, "COVE MASTER REGISTRY");
        vm.label(COVE_SILVERBACK_AWS_ACCOUNT, "COVE SILVERBACK AWS ACCOUNT");
        vm.label(COVE_STAGING_OPS_MULTISIG, "COVE STAGING OPS MULTISIG");
        vm.label(COVE_STAGING_COMMUNITY_MULTISIG, "COVE STAGING COMMUNITY MULTISIG");

        // Infrastructure addresses
        vm.label(CREATE3_FACTORY, "CREATE3 FACTORY");
        vm.label(PYTH, "PYTH ORACLE");
        vm.label(ETH_PERMIT2, "PERMIT2");
        vm.label(EVC, "EVC");

        // Base tokens
        vm.label(ETH, "ETH");
        vm.label(USD, "USD");
        vm.label(WBTC, "WBTC");

        // Asset addresses
        vm.label(ETH_CBBTC, "cbBTC");
        vm.label(ETH_EZETH, "ezETH");
        vm.label(ETH_GHO, "GHO");
        vm.label(ETH_RETH, "rETH");
        vm.label(ETH_RSETH, "rsETH");
        vm.label(ETH_SUSDE, "sUSDe");
        vm.label(ETH_TBTC, "tBTC");
        vm.label(ETH_USDT, "USDT");
        vm.label(ETH_WBTC, "WBTC");
        vm.label(ETH_WEETH, "weETH");
        vm.label(ETH_WETH, "WETH");
        vm.label(ETH_SDAI, "sDAI");
        vm.label(ETH_SFRAX, "sFRAX");
        vm.label(ETH_USDC, "USDC");
        vm.label(ETH_DAI, "DAI");
        vm.label(ETH_FRAX, "FRAX");
        vm.label(ETH_USDE, "USDe");

        // Price feeds
        vm.label(ETH_CHAINLINK_USDC_USD_FEED, "CHAINLINK USDC/USD");
        vm.label(ETH_CHAINLINK_DAI_USD_FEED, "CHAINLINK DAI/USD");
        vm.label(ETH_CHAINLINK_FRAX_USD_FEED, "CHAINLINK FRAX/USD");
        vm.label(ETH_CHAINLINK_USDE_USD_FEED, "CHAINLINK USDe/USD");
        vm.label(ETH_CHAINLINK_ETH_USD_FEED, "CHAINLINK ETH/USD");
        vm.label(ETH_CHAINLINK_SUSDE_USD_FEED, "CHAINLINK sUSDe/USD");
        vm.label(ETH_CHAINLINK_WEETH_ETH_FEED, "CHAINLINK weETH/ETH");
        vm.label(ETH_CHAINLINK_EZETH_ETH_FEED, "CHAINLINK ezETH/ETH");
        vm.label(ETH_CHAINLINK_RSETH_ETH_FEED, "CHAINLINK rsETH/ETH");
        vm.label(ETH_CHAINLINK_RETH_ETH_FEED, "CHAINLINK rETH/ETH");
        vm.label(ETH_CHAINLINK_WBTC_BTC_FEED, "CHAINLINK WBTC/BTC");
        vm.label(ETH_CHAINLINK_TBTC_BTC_FEED, "CHAINLINK tBTC/BTC");
        vm.label(ETH_CHAINLINK_GHO_USD_FEED, "CHAINLINK GHO/USD");
        vm.label(ETH_CHAINLINK_CBBTC_USD_FEED, "CHAINLINK cbBTC/USD");

        // External addresses
        vm.label(GAUNTLET_STRATEGIST, "GAUNTLET STRATEGIST");
    }
}
