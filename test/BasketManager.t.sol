// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { BaseTest } from "./utils/BaseTest.t.sol";
import { BasketManager } from "src/BasketManager.sol";
import { ERC7540AsyncExample } from "src/ERC7540AsyncExample.sol";
import { DummyERC20 } from "./utils/mocks/DummyERC20.sol";
import { console2 as console } from "forge-std/console2.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BasketManagerTest is BaseTest {
    BasketManager public basketManager;
    ERC7540AsyncExample public basketToken;
    DummyERC20 public dummyAsset;
    address public alice;
    address public owner;

    function setUp() public override {
        super.setUp();
        alice = users["alice"];
        owner = users["owner"];
        dummyAsset = new DummyERC20("Dummy", "DUMB");
        vm.label(address(dummyAsset), "dummyAsset");
        // mint alice some dummy asset
        dummyAsset.mint(users["alice"], 1e22);
        vm.prank(owner);
        address vault = address(new ERC7540AsyncExample(ERC20(dummyAsset), "Test", "TEST"));
        vm.label(address(vault), "vault");
        vm.prank(owner);
        basketManager = new BasketManager();
        vm.label(address(basketManager), "basketManager");
        basketManager.initialize(vault, address(0)); // Assuming oracleRegistry is not used in this context
        basketToken = ERC7540AsyncExample(basketManager.createNewBasket("TestBasket", "TBKT", 1, address(0))); // Assuming
            // allocationResolver is not used in this context
        vm.label(address(basketToken), "basketToken");
        vm.prank(alice);
        dummyAsset.approve(address(basketManager), 1e22);
    }

    function test_requestDeposit() public {
        uint256 amount = 1e18;
        vm.prank(alice);
        basketManager.requestDeposit(address(basketToken), amount, alice);
        assertEq(dummyAsset.balanceOf(address(basketManager)), amount, "BasketManager should hold the deposited amount");
        assertEq(
            basketManager.getPendingDepositors(address(basketToken))[0],
            alice,
            "BasketManager should have a pending deposit request for the amount"
        );
        assertEq(
            basketToken.pendingDepositRequest(alice),
            amount,
            "BasketManager should have a pending deposit request for the amount"
        );
        assertEq(basketToken.maxDeposit(alice), 0, "BasketManager should not have a max deposit for the user");
        // TODO: why does totalAssets() cause an underflow?
        // assertEq(basketToken.totalAssets(), 0, "Basket should not report any assets yet");
        assertEq(basketToken.balanceOf(alice), 0, "Alice should not have any shares yet");
    }

    function test_rebalance_of_deposit() public {
        uint256 amount = 1e18;
        vm.prank(alice);
        basketManager.requestDeposit(address(basketToken), amount, alice);
        address[] memory baskets = new address[](1);
        baskets[0] = address(basketToken);
        // rebalance fulfills the pending deposit
        basketManager.rebalance(baskets);
        assertEq(basketToken.totalSupply(), amount, "Basket should report the new shares");
        assertEq(basketToken.balanceOf(alice), amount, "Alice should have the deposited amount of shares");
    }

    function test_requestRedeem() public {
        uint256 amount = 1e18;
        vm.prank(alice);
        basketManager.requestDeposit(address(basketToken), amount, alice);
        vm.prank(owner);
        address[] memory baskets = new address[](1);
        baskets[0] = address(basketToken);
        // rebalance fulfills the pending deposit
        basketManager.rebalance(baskets);
        console.log("alice balance of basketToken", basketToken.balanceOf(alice));
        vm.startPrank(alice);
        basketToken.approve(address(basketManager), amount);
        basketManager.requestRedeem(address(basketToken), amount, alice);
        assertEq(
            basketToken.pendingRedeemRequest(0),
            amount,
            "BasketManager should have a pending redeem request for the amount"
        );
        assertEq(
            basketManager.getPendingWithdrawers(address(basketToken))[0],
            alice,
            "BasketManager should have a pending withdraw request for the amount"
        );
    }

    function test_rebalance_of_withdraw() public {
        uint256 amount = 1e18;
        vm.prank(alice);
        basketManager.requestDeposit(address(basketToken), amount, alice);
        vm.prank(owner);
        address[] memory baskets = new address[](1);
        baskets[0] = address(basketToken);
        // rebalance fulfills the pending deposit
        basketManager.rebalance(baskets);
        vm.startPrank(alice);
        basketToken.approve(address(basketManager), amount);
        basketManager.requestRedeem(address(basketToken), amount, alice);
        uint256 balanceBefore = dummyAsset.balanceOf(address(alice));
        // rebalance fulfills the pending withdraw
        vm.warp(3 days + 1);
        basketManager.rebalance(baskets);
        assertEq(basketToken.totalSupply(), 0, "Basket should report the removal of shares");
        assertEq(basketToken.balanceOf(alice), 0, "Alice should no longer have shares");
        assertEq(
            dummyAsset.balanceOf(address(alice)),
            balanceBefore + amount,
            "Alice should have received the withdrawn amount"
        );
    }
}
