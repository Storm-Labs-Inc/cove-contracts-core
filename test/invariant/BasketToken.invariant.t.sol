// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { console } from "forge-std/console.sol";

import { StdInvariant } from "lib/forge-std/src/StdInvariant.sol";
import { Clones } from "lib/openzeppelin-contracts/contracts/proxy/Clones.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketToken } from "src/BasketToken.sol";
import { InvariantHandler } from "test/invariant/InvariantHandler.t.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract BasketToken_InvariantTest is StdInvariant, BaseTest {
    BasketTokenHandler public basketTokenHandler;

    function setUp() public override {
        super.setUp();
        IERC20[] memory assets = new IERC20[](3);
        assets[0] = IERC20(new ERC20Mock());
        assets[1] = IERC20(new ERC20Mock());
        // vm.etch(address(assets[1]), USDT_BYTECODE);
        // vm.label(address(assets[1]), "USDT");
        assets[2] = IERC20(new ERC20Mock());
        vm.etch(address(assets[2]), WETH_BYTECODE);
        vm.label(address(assets[2]), "WETH");

        basketTokenHandler = new BasketTokenHandler(new BasketToken(), assets);
        vm.label(address(basketTokenHandler), "basketTokenHandler");
        targetContract(address(basketTokenHandler));
    }

    function invariant_basketManagerIsImmutableContractCreator() public {
        if (!basketTokenHandler.initialized()) {
            assertEq(address(basketTokenHandler.basketToken()), address(0), "BasketToken should not be initialized");
            return;
        }
        address basketManager = basketTokenHandler.basketToken().basketManager();
        assertEq(basketManager, address(basketTokenHandler), "BasketManager is not the contract creator");
    }

    function invariant_totalPendingDeposits() public {
        if (!basketTokenHandler.initialized()) {
            return;
        }
        assertEq(
            basketTokenHandler.depositsPendingRebalance(),
            basketTokenHandler.basketToken().totalPendingDeposits(),
            "depositsPendingRebalance should match totalPendingDeposits"
        );
    }
}

contract BasketTokenHandler is InvariantHandler {
    using SafeERC20 for IERC20;

    BasketToken public basketTokenImpl;
    BasketToken public basketToken;
    bool public initialized = false;

    uint256 public depositsPendingRebalance;
    uint256 private depositsPendingFulfill;
    uint256 public redeemsPendingRebalance;
    uint256 private redeemsPendingFulfill;

    uint256 constant ACTOR_COUNT = 5;

    IERC20[] private assets;

    constructor(BasketToken basketTokenImpl_, IERC20[] memory assets_) InvariantHandler(ACTOR_COUNT) {
        basketTokenImpl = basketTokenImpl_;
        assets = assets_;
    }

    function initialize(
        uint256 assetIndex,
        string memory name_,
        string memory symbol_,
        uint256 bitFlag_,
        address strategy_,
        address assetRegistry_,
        address admin_
    )
        public
    {
        vm.assume(!initialized);
        vm.assume(address(strategy_) != address(0));
        vm.assume(address(admin_) != address(0));
        vm.assume(address(assetRegistry_) != address(0));

        // bound assetIndex to assets array
        assetIndex = bound(assetIndex, 0, assets.length - 1);
        IERC20 asset = assets[assetIndex];

        initialized = true;
        basketToken = BasketToken(Clones.clone(address(basketTokenImpl)));
        vm.label(address(basketToken), "basketToken");

        basketToken.initialize(asset, name_, symbol_, bitFlag_, strategy_, assetRegistry_, admin_);

        vm.mockCall(
            address(assetRegistry_),
            abi.encodeWithSelector(AssetRegistry.hasPausedAssets.selector, bitFlag_),
            abi.encode(false)
        );
    }

    function fulfillDeposit(uint256 shares) public {
        vm.assume(initialized);
        vm.assume(depositsPendingFulfill > 0);
        vm.assume(shares > 0);
        basketToken.fulfillDeposit(shares);
        depositsPendingFulfill = 0;
    }

    function requestDeposit(uint256 userIdx, uint256 depositAmount) public useActor(userIdx) {
        vm.assume(initialized);
        uint256 nextRequestId = basketToken.nextDepositRequestId();
        vm.assume(basketToken.pendingDepositRequest(nextRequestId - 2, currentActor) == 0);
        vm.assume(basketToken.maxDeposit(currentActor) == 0);
        depositAmount = bound(depositAmount, 1, type(uint256).max / 1e18);

        uint256 before = basketToken.totalPendingDeposits();
        uint256 userRequestBefore = basketToken.pendingDepositRequest(nextRequestId, currentActor);

        address asset = address(basketToken.asset());
        deal(asset, currentActor, depositAmount);
        IERC20(asset).forceApprove(address(basketToken), type(uint256).max);

        uint256 requestId = basketToken.requestDeposit(depositAmount, currentActor, currentActor);
        assertEq(requestId, nextRequestId, "requestId should match nextRequestId");

        assertEq(
            basketToken.totalPendingDeposits(),
            before + depositAmount,
            "totalPendingDeposits should increase by depositAmount"
        );
        assertEq(
            basketToken.lastDepositRequestId(currentActor), requestId, "lastDepositRequestId should match requestId"
        );
        assertEq(
            basketToken.pendingDepositRequest(requestId, currentActor),
            userRequestBefore + depositAmount,
            "pendingDepositRequest should increase by depositAmount"
        );

        depositsPendingRebalance += depositAmount;
    }

    function prepareForRebalance() public {
        vm.assume(initialized);
        uint256 nextDepositId = basketToken.nextDepositRequestId();
        uint256 nextRedeemId = basketToken.nextRedeemRequestId();
        uint256 pendingRedemptions = basketToken.totalPendingRedemptions();
        // Call prepareForRebalance
        uint256 ret = basketToken.prepareForRebalance();
        // Check return value
        assertEq(ret, pendingRedemptions, "prepareForRebalance should return totalPendingRedemptions");
        assertEq(
            pendingRedemptions,
            redeemsPendingRebalance,
            "totalPendingRedemptions should match counter redeemsPendingRebalance"
        );
        // Check state changes
        assertEq(basketToken.totalPendingRedemptions(), 0, "totalPendingRedemptions should be 0");
        if (depositsPendingRebalance > 0) {
            assertEq(
                basketToken.nextDepositRequestId(), nextDepositId + 2, "nextDepositRequestId should increment by 2"
            );
        } else {
            assertEq(basketToken.nextDepositRequestId(), nextDepositId, "nextDepositRequestId should not change");
        }
        if (redeemsPendingRebalance > 0) {
            assertEq(basketToken.nextRedeemRequestId(), nextRedeemId + 2, "nextRedeemRequestId should increment by 2");
        } else {
            assertEq(basketToken.nextRedeemRequestId(), nextRedeemId, "nextRedeemRequestId should not change");
        }
        // Reset counters
        depositsPendingFulfill = depositsPendingRebalance;
        redeemsPendingFulfill = redeemsPendingRebalance;
        depositsPendingRebalance = 0;
        redeemsPendingRebalance = 0;
    }
}
