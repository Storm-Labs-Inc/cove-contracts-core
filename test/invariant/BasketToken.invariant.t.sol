// SPDX-License-Identifier: BUSL-1.1
// solhint-disable one-contract-per-file
pragma solidity 0.8.28;

import { StdInvariant } from "forge-std/StdInvariant.sol";

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { InvariantHandler } from "test/invariant/InvariantHandler.t.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";
import { ERC20Mock } from "test/utils/mocks/ERC20Mock.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketToken } from "src/BasketToken.sol";

/// @notice Invariant test suite for the BasketToken contract.
/// @dev This suite checks the contract's invariants by fuzzing its state and call sequences.
///
/// Each invariant function must start with the `invariant_` prefix.
/// No `vm.assume` calls are allowed in invariant functions.
/// The goal is to explore all possible contract states and ensure invariants hold.
/// Fuzzing is used to test various contract states.
/// Functions must start with `invariant_` to be recognized as invariant tests.
contract BasketToken_InvariantTest is StdInvariant, BaseTest {
    BasketTokenHandler public basketTokenHandler;

    // Setup function to initialize the test environment.
    // It creates mock ERC20 assets and deploys a BasketTokenHandler to interact with the BasketToken.
    function setUp() public override {
        super.setUp();
        IERC20[] memory assets = new IERC20[](3);
        assets[0] = IERC20(new ERC20Mock());
        assets[1] = IERC20(new ERC20Mock());
        // Uncomment the following lines if you want to mock USDT behavior.
        // vm.etch(address(assets[1]), USDT_BYTECODE);
        // vm.label(address(assets[1]), "USDT");
        assets[2] = IERC20(new ERC20Mock());
        vm.etch(address(assets[2]), WETH_BYTECODE);
        vm.label(address(assets[2]), "WETH");

        basketTokenHandler = new BasketTokenHandler(new BasketToken(), assets);
        vm.label(address(basketTokenHandler), "basketTokenHandler");
        targetContract(address(basketTokenHandler));
    }

    // Invariant: If the BasketToken is initialized, the BasketManager must be the contract creator.
    function invariant_basketManagerIsImmutableContractCreator() public {
        if (!basketTokenHandler.initialized()) {
            assertEq(address(basketTokenHandler.basketToken()), address(0), "BasketToken should not be initialized");
            return;
        }
        address basketManager = basketTokenHandler.basketToken().basketManager();
        assertEq(basketManager, address(basketTokenHandler), "BasketManager is not the contract creator");
    }

    // Invariant: totalPendingDeposits must equal the total deposits requested but not yet fulfilled.
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

/// @title BasketTokenHandler for Invariant Tests
/// @notice This contract interacts with the BasketToken and tests state changes after each function call.
/// @dev Public/external functions in this contract are called randomly by the invariant test contract.
/// It is responsible for ensuring the BasketToken behaves as expected under various conditions.
contract BasketTokenHandler is InvariantHandler {
    using SafeERC20 for IERC20;

    BasketToken public basketTokenImpl;
    BasketToken public basketToken;
    bool public initialized = false;

    uint256 public depositsPendingRebalance;
    uint256 private depositsPendingFulfill;
    uint256 public redeemsPendingRebalance;
    uint256 private redeemsPendingFulfill;

    uint256 private constant ACTOR_COUNT = 5;

    IERC20[] private assets;

    // Constructor to initialize the handler with a BasketToken implementation and a list of assets.
    constructor(BasketToken basketTokenImpl_, IERC20[] memory assets_) InvariantHandler(ACTOR_COUNT) {
        basketTokenImpl = basketTokenImpl_;
        assets = assets_;
    }

    // Function to initialize the BasketToken with the specified parameters.
    // It assumes the contract is not already initialized and that valid addresses are provided.
    function initialize(
        uint256 assetIndex,
        string memory name_,
        string memory symbol_,
        uint256 bitFlag_,
        address strategy_,
        address assetRegistry_
    )
        public
    {
        vm.assume(!initialized);
        vm.assume(address(strategy_) != address(0));
        vm.assume(address(assetRegistry_) != address(0));

        // Ensure the assetIndex is within bounds of the assets array.
        assetIndex = bound(assetIndex, 0, assets.length - 1);
        IERC20 asset = assets[assetIndex];

        initialized = true;
        basketToken = BasketToken(Clones.clone(address(basketTokenImpl)));
        vm.label(address(basketToken), "basketToken");

        basketToken.initialize(asset, name_, symbol_, bitFlag_, strategy_, assetRegistry_);

        // Mock the AssetRegistry to simulate that no assets are paused.
        vm.mockCall(
            address(assetRegistry_),
            abi.encodeWithSelector(AssetRegistry.hasPausedAssets.selector, bitFlag_),
            abi.encode(false)
        );
    }

    // Function to fulfill a deposit request.
    // It assumes the contract is initialized and there are pending deposits to fulfill.
    function fulfillDeposit(uint256 shares) public {
        vm.assume(initialized);
        vm.assume(depositsPendingFulfill > 0);
        vm.assume(shares > 0 && shares < type(uint256).max / 1e18);
        basketToken.fulfillDeposit(shares);
        depositsPendingFulfill = 0;
    }

    // Function to request a deposit for a specific user.
    // It assumes the contract is initialized and the user has no pending deposit requests.
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

    // Function to prepare the BasketToken for a rebalance.
    // It assumes there are no pending deposits or redeems to fulfill.
    // The function resets the pending deposit and redeem counters after the rebalance.
    function prepareForRebalance() public {
        vm.assume(initialized);
        vm.assume(depositsPendingFulfill == 0 && redeemsPendingFulfill == 0);
        uint256 nextDepositId = basketToken.nextDepositRequestId();
        uint256 nextRedeemId = basketToken.nextRedeemRequestId();
        uint256 pendingRedemptions = basketToken.totalPendingRedemptions();

        // Call prepareForRebalance and check the return value.
        // TODO: verify this is correct change to prepareForRebalance / fix parameters
        (, uint256 redeems) = basketToken.prepareForRebalance(0, address(0));
        assertEq(redeems, pendingRedemptions, "prepareForRebalance should return totalPendingRedemptions");
        assertEq(
            pendingRedemptions,
            redeemsPendingRebalance,
            "totalPendingRedemptions should match counter redeemsPendingRebalance"
        );

        // Check state changes after rebalance.
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

        // Reset counters after rebalance.
        depositsPendingFulfill = depositsPendingRebalance;
        redeemsPendingFulfill = redeemsPendingRebalance;
        depositsPendingRebalance = 0;
        redeemsPendingRebalance = 0;
    }
}
