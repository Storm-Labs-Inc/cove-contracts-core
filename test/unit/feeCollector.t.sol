// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { FeeCollector } from "src/FeeCollector.sol";

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { Constants } from "test/utils/Constants.t.sol";

contract FeeCollectorTest is BaseTest, Constants {
    using FixedPointMathLib for uint256;

    FeeCollector public feeCollector;
    address public admin;
    address public treasury;
    address public sponser;
    address public basketManager;
    address public basketToken;

    bytes32 private constant _BASKET_MANAGER_ROLE = keccak256("BASKET_MANAGER_ROLE");
    bytes32 private constant _PROTOCOL_TREASURY_ROLE = keccak256("PROTOCOL_TREASURY_ROLE");
    uint16 private constant _FEE_SPLIT_DECIMALS = 1e4;
    uint16 private constant _MAX_FEE = 1e4;

    function setUp() public override {
        super.setUp();
        admin = createUser("admin");
        treasury = createUser("treasury");
        sponser = createUser("sponser");
        basketToken = createUser("basketToken");
        basketManager = createUser("basketManager");
        feeCollector = new FeeCollector(admin, basketManager, treasury);
    }

    function test_constructor() public {
        assertEq(feeCollector.hasRole(DEFAULT_ADMIN_ROLE, admin), true);
        assertEq(feeCollector.hasRole(_BASKET_MANAGER_ROLE, basketManager), true);
        assertEq(feeCollector.hasRole(_PROTOCOL_TREASURY_ROLE, treasury), true);
    }

    function testFuzz_setProtocolTreasury(address newTreasury) public {
        vm.assume(newTreasury != address(0) && newTreasury != treasury);
        vm.prank(admin);
        feeCollector.setProtocolTreasury(newTreasury);
        assertEq(feeCollector.hasRole(_PROTOCOL_TREASURY_ROLE, newTreasury), true);
        assertEq(feeCollector.hasRole(_PROTOCOL_TREASURY_ROLE, treasury), false);
    }

    function testFuzz_setBasketManager(address newBasketManager) public {
        vm.assume(newBasketManager != address(0) && newBasketManager != basketManager);
        vm.prank(admin);
        feeCollector.setBasketManager(newBasketManager);
        assertEq(feeCollector.hasRole(_BASKET_MANAGER_ROLE, newBasketManager), true);
        assertEq(feeCollector.hasRole(_BASKET_MANAGER_ROLE, basketManager), false);
    }

    function testFuzz_setSponser(address newSponser) public {
        vm.assume(newSponser != address(0));
        vm.prank(admin);
        feeCollector.setSponser(address(basketToken), newSponser);
        assertEq(feeCollector.basketTokenSponsers(address(basketToken)), newSponser);
    }

    function testFuzz_setSponserSplit(uint16 sponserSplit) public {
        vm.assume(sponserSplit < _MAX_FEE);
        vm.prank(admin);
        feeCollector.setSponserSplit(address(basketToken), sponserSplit);
        assertEq(feeCollector.basketTokenSponserSplits(address(basketToken)), sponserSplit);
    }

    function testFuzz_notifyHarvestFee(uint256 shares, uint16 sponserSplit) public {
        vm.assume(shares > _FEE_SPLIT_DECIMALS && shares < type(uint256).max / shares);
        vm.assume(sponserSplit < _MAX_FEE);
        vm.prank(admin);
        feeCollector.setSponser(address(basketToken), sponser);
        vm.prank(admin);
        feeCollector.setSponserSplit(address(basketToken), sponserSplit);
        vm.prank(basketToken);
        feeCollector.notifyHarvestFee(shares);

        uint256 expectedSponserFee = shares.mulDiv(sponserSplit, _FEE_SPLIT_DECIMALS);
        uint256 expectedTreasuryFee = shares - expectedSponserFee;

        assertEq(feeCollector.sponserFeesCollected(address(basketToken)), expectedSponserFee);
        assertEq(feeCollector.treasuryFeesCollected(address(basketToken)), expectedTreasuryFee);
    }

    // TODO: function testFuzz_notifyHarvestFee_revertsWhenNotBasketToken()

    function testFuzz_withdrawSponserFee(uint256 shares, uint16 sponserSplit) public {
        vm.assume(sponserSplit < _MAX_FEE);
        testFuzz_notifyHarvestFee(shares, sponserSplit);

        uint256 sponserFee = feeCollector.sponserFeesCollected(address(basketToken));
        vm.mockCall(
            address(basketToken),
            abi.encodeCall(BasketToken.proRataRedeem, (sponserFee, sponser, address(feeCollector))),
            abi.encode(0)
        );

        vm.prank(sponser);
        feeCollector.withdrawSponserFee(address(basketToken));
        assertEq(feeCollector.sponserFeesCollected(address(basketToken)), 0);
    }

    function testFuzz_withdrawTreasuryFee(uint256 shares, uint16 sponserSplit) public {
        vm.assume(sponserSplit < _MAX_FEE);
        testFuzz_notifyHarvestFee(shares, sponserSplit);

        uint256 treasuryFee = feeCollector.treasuryFeesCollected(address(basketToken));
        vm.mockCall(
            address(basketToken),
            abi.encodeCall(BasketToken.proRataRedeem, (treasuryFee, treasury, address(feeCollector))),
            abi.encode(0)
        );

        vm.prank(treasury);
        feeCollector.withdrawTreasuryFee(address(basketToken));

        assertEq(feeCollector.treasuryFeesCollected(address(basketToken)), 0);
    }

    function testFuzz_setSponserSplit_revertsWhen_splitTooHigh(uint16 sponserSplit) public {
        vm.assume(sponserSplit >= _MAX_FEE);
        vm.prank(admin);
        vm.expectRevert(FeeCollector.SponserSplitTooHigh.selector);
        feeCollector.setSponserSplit(address(basketToken), sponserSplit);
    }

    function testFuzz_withdrawSponserFee_revertsWhen_notSponser(address caller) public {
        vm.assume(caller != address(0) && caller != sponser);
        vm.prank(admin);
        feeCollector.setSponser(address(basketToken), sponser);
        vm.prank(caller);
        vm.expectRevert(FeeCollector.NotSponser.selector);
        feeCollector.withdrawSponserFee(address(basketToken));
    }
}
