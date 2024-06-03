// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { BaseTest } from "./utils/BaseTest.t.sol";
import { ERC7540AsyncExample } from "src/ERC7540AsyncExample.sol";
// import { Errors } from "src/libraries/Errors.sol";

import { DummyERC20 } from "./utils/mocks/DummyERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC7540AsyncExample_Test is BaseTest {
    ERC7540AsyncExample public vault;
    DummyERC20 public dummyAsset;
    address public alice;
    address public owner;

    function setUp() public override {
        super.setUp();
        alice = createUser("alice");
        owner = createUser("owner");
        // create dummy asset
        dummyAsset = new DummyERC20("Dummy", "DUMB");
        vm.label(address(dummyAsset), "dummyAsset");
        // mint alice some dummy asset
        dummyAsset.mint(users["alice"], 1e22);
        vm.prank(owner);
        vault = new ERC7540AsyncExample(ERC20(dummyAsset), "Test", "TEST");
        vm.label(address(vault), "vault");
        // approve alice for spending asset in vault
        vm.prank(users["alice"]);
        dummyAsset.approve(address(vault), 1e22);
    }

    function test_requestDeposit() public {
        uint256 amount = 1e18;
        vm.prank(alice);
        vault.requestDeposit(amount, alice);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.pendingDepositRequest(alice), amount);
        assertEq(vault.maxDeposit(alice), 0);
    }

    function test_deposit() public {
        uint256 amount = 1e18;
        vm.prank(alice);
        vault.requestDeposit(amount, alice);
        vm.prank(owner);
        vault.fulfillDeposit(alice);
        vm.prank(alice);
        vault.deposit(amount, alice);
        assertEq(vault.totalAssets(), amount);
        assertEq(vault.balanceOf(alice), amount);
        assertEq(vault.pendingDepositRequest(alice), 0);
    }

    function test_requestRedeem() public {
        uint256 amount = 1e18;
        vm.prank(alice);
        vault.requestDeposit(amount, alice);
        vm.prank(owner);
        vault.fulfillDeposit(alice);
        uint256 shares = vault.maxMint(alice);
        vm.prank(alice);
        vault.deposit(amount, alice);
        assertEq(vault.totalAssets(), amount);
        assertEq(vault.balanceOf(alice), amount);
        assertEq(vault.pendingDepositRequest(alice), 0);
        vm.prank(alice);
        uint256 id = vault.requestRedeem(shares, alice, alice);
        assertEq(vault.pendingRedeemRequest(id), shares);
    }

    function test_withdraw() public {
        uint256 amount = 1e18;
        vm.prank(alice);
        vault.requestDeposit(amount, alice);
        vm.prank(owner);
        vault.fulfillDeposit(alice);
        uint256 shares = vault.maxMint(alice);
        vm.prank(alice);
        vault.deposit(amount, alice);
        assertEq(vault.totalAssets(), amount);
        assertEq(vault.balanceOf(alice), amount);
        assertEq(vault.pendingDepositRequest(alice), 0);
        vm.prank(alice);
        uint256 id = vault.requestRedeem(shares, alice, alice);
        assertEq(vault.pendingRedeemRequest(id), shares);
        vm.warp(3 days + 2);
        uint256 maxWithdraw = vault.maxWithdraw(alice);
        uint256 aliceBalanceBefore = dummyAsset.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(maxWithdraw, alice, alice);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.pendingRedeemRequest(id), 0);
        assertEq(dummyAsset.balanceOf(alice), aliceBalanceBefore + amount);
    }
}
