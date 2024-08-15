// // SPDX-License-Identifier: BUSL-1.1
// pragma solidity 0.8.23;

// import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
// import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
// import { BaseTest } from "test/utils/BaseTest.t.sol";

// import { stdError } from "forge-std/StdError.sol";
// import { console } from "forge-std/console.sol";

// import { BasketManagerDelegate } from "src/BasketManagerDelegate.sol";
// import { Errors } from "src/libraries/Errors.sol";
// import { RebalancingUtils } from "src/libraries/RebalancingUtils.sol";

// contract BasketManagerDelegateTest is BaseTest {
//     RebalancingUtils public rebalancingUtils;
//     BasketManagerDelegate public basketManagerDelegate;
//     EulerRouter public eulerRouter;

//     address public alice;
//     address public admin;
//     address public manager;
//     address public rebalancer;
//     address public pauser;
//     address public rootAsset;
//     address public toAsset;
//     address public basketTokenImplementation;
//     address public strategyRegistry;

//     function setUp() public override {
//         super.setUp();
//         rebalancingUtils = new RebalancingUtils();
//         alice = createUser("alice");
//         admin = createUser("admin");
//         pauser = createUser("pauser");
//         manager = createUser("manager");
//         rebalancer = createUser("rebalancer");
//         rootAsset = address(new ERC20Mock());
//         toAsset = address(new ERC20Mock());
//         basketTokenImplementation = createUser("basketTokenImplementation");
//         eulerRouter = new EulerRouter(admin);
//         strategyRegistry = createUser("strategyRegistry");
//         basketManagerDelegate = new BasketManagerDelegate(
//             basketTokenImplementation, address(eulerRouter), strategyRegistry, address(rebalancingUtils), admin
//         );
//     }

//     function test_constructor() public {
//         assertEq(basketManagerDelegate.getBasketTokenImplementation(), basketTokenImplementation);
//     }
// }
