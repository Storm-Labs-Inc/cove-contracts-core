pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { Constants } from "test/utils/Constants.t.sol";

// Asets
import { ERC20DecimalsMock } from "test/utils/mocks/ERC20DecimalsMock.sol";

// Core contracts
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { FeeCollector } from "src/FeeCollector.sol";
import { ManagedWeightStrategy } from "src/strategies/ManagedWeightStrategy.sol";

// Mocked core contracts
import { AssetRegistryMock } from "test/utils/mocks/AssetRegistryMock.sol";

import { MockPriceOracle } from "test/utils/mocks/MockPriceOracle.sol";
import { StrategyRegistryMock } from "test/utils/mocks/StrategyRegistryMock.sol";
import { TokenSwapAdapterMock } from "test/utils/mocks/TokenSwapAdapterMock.sol";

import { ControllerOnlyUserHandler } from "test/invariant/handler/user/ControllerOnlyUserHandler.sol";
import { UserHandlerBase } from "test/invariant/handler/user/UserBaseHandler.sol";
import { UserHandler } from "test/invariant/handler/user/UserHandler.sol";

import { FakeBasketManagerForFeeCollector } from "test/invariant/handler/FakeBasketManagerForFeeCollector.sol";
import { BasketManagerAdminHandler } from "test/invariant/handler/admin/BasketManagerAdminHandler.sol";
import { FeeCollectorHandler } from "test/invariant/handler/feecollector/FeeCollectorHandler.sol";
import { OracleHandler } from "test/invariant/handler/oracle/OracleHandler.sol";

import { RebalancerHandler } from "test/invariant/handler/rebalancer/RebalancerHandler.sol";
import { TokenSwapHandler } from "test/invariant/handler/tokenswap/TokenSwapHandler.sol";

import { GlobalState } from "test/invariant/handler/GlobalState.sol";

/**
 * @title BasketManagerHandlers
 * @notice Main deployment contract for the fuzzing harness. Sets up all core contracts,
 *         handlers, and test infrastructure for invariant testing.
 * @dev This contract provides a complete local testing environment without external dependencies.
 */
contract BasketManagerHandlers is Test, Constants {
    // ERC20 tokens
    ERC20DecimalsMock[] public assets;

    // Actor addresses
    address public admin;
    address public manager;
    address public pauser;
    address public timelock;

    address public protocolTreasury;

    // Handlers
    UserHandlerBase[] public users;

    TokenSwapHandler public tokenSwap;
    RebalancerHandler public rebalancer;
    OracleHandler public oracleHandler;
    FeeCollectorHandler public feeCollectorHandler;
    BasketManagerAdminHandler public basketManagerAdminHandler;

    // Core contracts
    BasketManager public basketManager;
    BasketToken public basketToken;
    AssetRegistryMock public assetRegistry;
    StrategyRegistryMock public strategyRegistry;
    ManagedWeightStrategy public managedStrategy;
    MockPriceOracle public priceOracle;
    FeeCollector public feeCollector;

    GlobalState globalState;

    // Basket parameters
    uint256 public constant BASKET_BITFLAG = 7; // USDC + WETH + DAI
    uint64[] public initialWeights;

    /**
     * @notice Creates test actor addresses for admin, manager, pauser, and timelock
     */
    function _create_users() internal virtual {
        admin = makeAddr("admin");
        manager = makeAddr("manager");
        pauser = makeAddr("pauser");
        timelock = makeAddr("timelock");
    }

    /**
     * @notice Deploys all core contracts including BasketManager, FeeCollector, and mocks
     */
    function _create_core_contracts() internal virtual {
        // Deploy core contracts
        assetRegistry = new AssetRegistryMock();
        strategyRegistry = new StrategyRegistryMock(admin);
        priceOracle = new MockPriceOracle();

        // Deploy BasketToken implementation
        BasketToken basketTokenImplementation = new BasketToken();

        // Deploy FeeCollector first with a temporary basketManager address
        // We use a fake manager here. The real deployment use create3
        FakeBasketManagerForFeeCollector fakeManager = new FakeBasketManagerForFeeCollector();

        protocolTreasury = makeAddr("protocolTreasury");

        feeCollector = new FeeCollector(admin, address(fakeManager), protocolTreasury); // admin as treasury for testing

        // Deploy BasketManager with the FeeCollector address
        basketManager = new BasketManager(
            address(basketTokenImplementation),
            address(priceOracle),
            address(strategyRegistry),
            address(assetRegistry),
            admin,
            address(feeCollector)
        );

        fakeManager.setManager(basketManager);
    }

    /**
     * @notice Creates and configures test assets (USDC, WETH, DAI) with proper bit flags
     */
    function _create_assets() internal virtual {
        ERC20DecimalsMock usdc = new ERC20DecimalsMock(6, "USDC", "usdc");
        ERC20DecimalsMock weth = new ERC20DecimalsMock(18, "WETH", "weth");
        ERC20DecimalsMock dai = new ERC20DecimalsMock(16, "DAI", "dai");

        assets.push(usdc);
        assets.push(weth);
        assets.push(dai);

        vm.label(address(usdc), "USDC");
        vm.label(address(weth), "WETH");
        vm.label(address(dai), "DAI");
        vm.label(address(USD), "USD");

        // Add assets to registry
        vm.prank(admin);
        assetRegistry.addAsset(address(usdc), 1, "USDC", 6);
        vm.prank(admin);
        assetRegistry.addAsset(address(weth), 2, "WETH", 18);
        vm.prank(admin);
        assetRegistry.addAsset(address(dai), 4, "DAI", 18);

        address[] memory assets_addr = new address[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            assets_addr[i] = address(assets[i]);
        }
        // Set up assets for the bit flag (7 = 1 + 2 + 4)
        vm.prank(admin);
        assetRegistry.setMockAssets(BASKET_BITFLAG, assets_addr);
    }

    /**
     * @notice Sets up initial basket weights: 40% USDC, 30% WETH, 30% DAI
     */
    function _setup_weights() internal virtual {
        // Set up initial weights: 40% USDC, 30% WETH, 30% DAI
        initialWeights = new uint64[](3);
        initialWeights[0] = 4 * 10 ** 17; // 40% USDC
        initialWeights[1] = 3 * 10 ** 17; // 30% WETH
        initialWeights[2] = 3 * 10 ** 17; // 30% DAI
    }

    /**
     * @notice Grants necessary roles to test actors
     */
    function _grant_roles() internal virtual {
        // Grant roles
        vm.startPrank(admin);
        basketManager.grantRole(MANAGER_ROLE, manager);
        basketManager.grantRole(PAUSER_ROLE, pauser);
        basketManager.grantRole(TIMELOCK_ROLE, timelock);
        vm.stopPrank();
    }

    /**
     * @notice Deploys and configures the ManagedWeightStrategy with initial weights
     */
    function _create_strategy() internal virtual {
        // Deploy ManagedWeightStrategy
        managedStrategy = new ManagedWeightStrategy(admin, address(basketManager));

        // Grant manager role to the managed strategy
        vm.prank(admin);
        managedStrategy.grantRole(MANAGER_ROLE, manager);

        // Register strategy
        vm.prank(admin);
        strategyRegistry.registerStrategy(address(managedStrategy));

        vm.prank(admin);
        strategyRegistry.setBitFlagSupport(address(managedStrategy), BASKET_BITFLAG, true);

        vm.prank(address(manager));
        managedStrategy.setTargetWeights(BASKET_BITFLAG, initialWeights);
    }

    /**
     * @notice Sets initial prices to 1:1 for all asset pairs
     */
    function _set_initial_prices() internal virtual {
        // Default price, everything is 1

        for (uint256 i = 0; i < assets.length; i++) {
            ERC20DecimalsMock asset = assets[i];
            //uint decimals = asset.decimals();
            //priceOracle.setPrice(address(asset), address(0), 10**18);
            priceOracle.setPrice(address(asset), USD, 10 ** 18);
            priceOracle.setPrice(USD, address(asset), 10 ** 18);

            // Better handling of ASSET -> basettoken asset
            if (i >= 1) {
                priceOracle.setPrice(address(asset), address(assets[0]), 10 ** 18);
            }
        }
    }

    /**
     * @notice Deploys and configures the token swap adapter
     */
    function _create_swap_adapter() internal virtual {
        TokenSwapAdapterMock swap = new TokenSwapAdapterMock();
        vm.prank(timelock);
        basketManager.setTokenSwapAdapter(address(swap));
    }

    /**
     * @notice Creates the initial basket token with configured assets and strategy
     */
    function _create_basket() internal virtual {
        vm.prank(manager);
        address basketAddress = basketManager.createNewBasket(
            "DeFi Basket",
            "DEFI",
            address(assets[0]), // baseAsset is usdc
            BASKET_BITFLAG,
            address(managedStrategy)
        );
        basketToken = BasketToken(basketAddress);
    }

    /**
     * @notice Deploys and configures all handler contracts with appropriate roles
     */
    function _create_handlers() internal virtual {
        globalState = new GlobalState();

        _create_user_handler();

        rebalancer = new RebalancerHandler(basketManager);
        tokenSwap = new TokenSwapHandler(basketManager, rebalancer, globalState);

        vm.startPrank(admin);
        basketManager.grantRole(REBALANCE_PROPOSER_ROLE, address(rebalancer));

        basketManager.grantRole(TOKENSWAP_PROPOSER_ROLE, address(tokenSwap));
        basketManager.grantRole(TOKENSWAP_EXECUTOR_ROLE, address(tokenSwap));
        vm.stopPrank();

        oracleHandler = new OracleHandler(basketManager, priceOracle, globalState);

        feeCollectorHandler = new FeeCollectorHandler(feeCollector, basketManager);

        vm.prank(admin);
        feeCollector.grantRole(DEFAULT_ADMIN_ROLE, address(feeCollectorHandler));

        basketManagerAdminHandler = new BasketManagerAdminHandler(basketManager);
        vm.startPrank(admin);
        basketManager.grantRole(DEFAULT_ADMIN_ROLE, address(basketManagerAdminHandler));
        basketManager.grantRole(MANAGER_ROLE, address(basketManagerAdminHandler));
        basketManager.grantRole(TIMELOCK_ROLE, address(basketManagerAdminHandler));
        vm.stopPrank();
    }

    /**
     * @notice Creates user handlers (Alice and AliceController) with funded balances
     */
    function _create_user_handler() internal virtual {
        UserHandler alice = new UserHandler(basketManager, globalState, address(0x0), address(0x0), false);

        for (uint256 i = 0; i < assets.length; i++) {
            ERC20DecimalsMock asset = assets[i];
            uint256 decimals = asset.decimals();

            asset.mint(address(alice), 100_000 * 10 ** decimals);
        }
        vm.label(address(alice), "Alice");
        users.push(alice);

        ControllerOnlyUserHandler aliceController =
            new ControllerOnlyUserHandler(basketManager, globalState, address(alice), address(0x0), false);

        for (uint256 i = 0; i < assets.length; i++) {
            ERC20DecimalsMock asset = assets[i];
            uint256 decimals = asset.decimals();

            asset.mint(address(aliceController), 100_000 * 10 ** decimals);
        }

        vm.label(address(aliceController), "AliceController");
        users.push(aliceController);

        // Use prank so that we don't have to add the logic to call setOperator
        // In the handler. So that the function is not fuzzed
        vm.prank(address(alice));
        basketToken.setOperator(address(aliceController), true);

        // Eve will have alice as owner/controller when calling the different functions
        // However she is not an operator of alice
        UserHandler eve = new UserHandler(basketManager, globalState, address(alice), address(alice), true);
        vm.label(address(eve), "Eve");
        users.push(eve);
    }

    /**
     * @notice Complete setup of the fuzzing harness environment
     */
    function setUp() public virtual {
        vm.warp(300 days);

        console.log("Create users");
        _create_users();

        console.log("Create core contracts");
        _create_core_contracts();

        console.log("Create assets");
        _create_assets();

        console.log("Setup weights");
        _setup_weights();

        console.log("Grant roles");
        _grant_roles();

        console.log("Create swap adapter (mock)");
        _create_swap_adapter();

        console.log("Create strategy");
        _create_strategy();

        console.log("Set initial prices");
        _set_initial_prices();

        console.log("Create one basket");
        _create_basket();

        console.log("Create handlers");
        _create_handlers();
    }
}
