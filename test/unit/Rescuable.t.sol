// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { ERC20Mock } from "test/utils/mocks/ERC20Mock.sol";
import { MockNonPayable } from "test/utils/mocks/MockNonPayable.sol";
import { MockRescuable } from "test/utils/mocks/MockRescuable.sol";

import { Rescuable } from "src/Rescuable.sol";

contract RescuableTest is BaseTest {
    MockRescuable public mockRescuable;

    // Addresses
    address public alice;
    address public shitcoin;
    address public nonPayable;

    function setUp() public override {
        super.setUp();

        alice = createUser("alice");
        shitcoin = address(new ERC20Mock());
        mockRescuable = new MockRescuable();
        nonPayable = address(new MockNonPayable());
    }

    function testFuzz_rescue_eth(uint256 amount) public {
        vm.assume(amount != 0);
        // createUser deals new addresses 100 ETH, so set to 0
        deal(alice, 0);
        deal(address(mockRescuable), amount);
        mockRescuable.rescue(IERC20(address(0)), alice, amount);
        assertEq(address(alice).balance, amount, "rescue failed");
    }

    function test_rescue_eth_zeroBalance() public {
        deal(address(mockRescuable), 1e18);
        mockRescuable.rescue(IERC20(address(0)), alice, 0);
        // createUser deals new addresses 100 ETH
        assertEq(address(alice).balance, 100 ether + 1e18, "rescue failed");
    }

    function test_rescue_eth_balanceExceedsTotalBalance() public {
        deal(address(mockRescuable), 1e18);
        mockRescuable.rescue(IERC20(address(0)), alice, 2e18);
        // createUser deals new addresses 100 ETH
        assertEq(address(alice).balance, 100 ether + 1e18, "rescue failed");
    }

    function test_rescue_eth_revertsOnZeroBalance() public {
        vm.expectRevert(abi.encodeWithSelector(Rescuable.ZeroEthTransfer.selector));
        mockRescuable.rescue(IERC20(address(0)), alice, 1e18);
    }

    function test_rescue_eth_revertsOnFailedTransfer() public {
        deal(address(mockRescuable), 1e18);
        vm.expectRevert(abi.encodeWithSelector(Rescuable.EthTransferFailed.selector));
        mockRescuable.rescue(IERC20(address(0)), nonPayable, 1e18);
    }

    function testFuzz_rescue_erc20(uint256 amount) public {
        vm.assume(amount != 0);
        airdrop(ERC20(shitcoin), address(mockRescuable), amount);
        mockRescuable.rescue(IERC20(shitcoin), alice, amount);
        assertEq(IERC20(shitcoin).balanceOf(alice), amount, "rescue failed");
    }

    function test_rescue_erc20_zeroBalance() public {
        airdrop(ERC20(shitcoin), address(mockRescuable), 1e18);
        mockRescuable.rescue(IERC20(shitcoin), alice, 0);
        assertEq(IERC20(shitcoin).balanceOf(alice), 1e18, "rescue failed");
    }

    function test_rescue_erc20_balanceExceedsTotalBalance() public {
        airdrop(ERC20(shitcoin), address(mockRescuable), 1e18);
        mockRescuable.rescue(IERC20(shitcoin), alice, 2e18);
        assertEq(IERC20(shitcoin).balanceOf(alice), 1e18, "rescue failed");
    }

    function test_rescue_erc20_revertsOnZeroBalance() public {
        vm.expectRevert(abi.encodeWithSelector(Rescuable.ZeroTokenTransfer.selector));
        mockRescuable.rescue(IERC20(shitcoin), alice, 1e18);
    }
}
