// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { BasketToken } from "src/BasketToken.sol";
import { FeeCollector } from "src/FeeCollector.sol";
import { Errors } from "src/libraries/Errors.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";
import { Constants } from "test/utils/Constants.t.sol";
import { MockBasketManager } from "test/utils/mocks/MockBasketManager.sol";

contract FeeCollectorTest is BaseTest, Constants {
    using FixedPointMathLib for uint256;

    FeeCollector public feeCollector;
    ERC20Mock public dummyAsset;
    address public admin;
    address public treasury;
    address public sponsor;
    address public basketManager;
    address public basketToken;

    bytes32 private constant _BASKET_MANAGER_ROLE = keccak256("BASKET_MANAGER_ROLE");
    bytes32 private constant _PROTOCOL_TREASURY_ROLE = keccak256("PROTOCOL_TREASURY_ROLE");
    bytes32 private constant _BASKET_TOKEN_ROLE = keccak256("BASKET_TOKEN_ROLE");
    bytes32 private constant _SPONSOR_ROLE = keccak256("SPONSOR_ROLE");
    uint16 private constant _FEE_SPLIT_DECIMALS = 1e4;
    uint16 private constant _MAX_FEE = 1e4;

    function setUp() public override {
        super.setUp();
        admin = createUser("admin");
        vm.label(admin, "admin");
        treasury = createUser("treasury");
        vm.label(treasury, "treasury");
        sponsor = createUser("sponsor");
        vm.label(sponsor, "sponsor");
        // create dummy asset
        dummyAsset = new ERC20Mock();
        vm.label(address(dummyAsset), "dummyAsset");
        address basketTokenImplementation = address(new BasketToken());
        vm.label(basketTokenImplementation, "basketTokenImplementation");
        basketManager = address(new MockBasketManager(basketTokenImplementation));
        vm.label(address(basketManager), "mockBasketManager");
        basketToken = address(
            MockBasketManager(basketManager).createNewBasket(ERC20(dummyAsset), "Test", "TEST", 1, address(1), admin)
        );
        feeCollector = new FeeCollector(admin, basketManager, treasury);
        vm.label(address(feeCollector), "feeCollector");
        vm.prank(admin);
        feeCollector.setSponser(address(basketToken), sponsor);
    }

    function test_constructor() public {
        assertEq(feeCollector.hasRole(DEFAULT_ADMIN_ROLE, admin), true);
        assertEq(feeCollector.hasRole(_BASKET_MANAGER_ROLE, basketManager), true);
        assertEq(feeCollector.hasRole(_PROTOCOL_TREASURY_ROLE, treasury), true);
    }

    function test_constructor_revertsWhen_zeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new FeeCollector(address(0), basketManager, treasury);
        vm.expectRevert(Errors.ZeroAddress.selector);
        new FeeCollector(admin, address(0), treasury);
        vm.expectRevert(Errors.ZeroAddress.selector);
        new FeeCollector(admin, basketManager, address(0));
    }

    function testFuzz_setProtocolTreasury(address newTreasury) public {
        vm.assume(newTreasury != address(0) && newTreasury != treasury);
        vm.prank(admin);
        feeCollector.setProtocolTreasury(newTreasury);
        assertEq(feeCollector.hasRole(_PROTOCOL_TREASURY_ROLE, newTreasury), true);
        assertEq(feeCollector.hasRole(_PROTOCOL_TREASURY_ROLE, treasury), false);
    }

    function test_setProtocolTreasury_revertsWhen_zeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        feeCollector.setProtocolTreasury(address(0));
    }

    function testFuzz_setBasketManager(address newBasketManager) public {
        vm.assume(newBasketManager != address(0) && newBasketManager != basketManager);
        vm.prank(admin);
        feeCollector.setBasketManager(newBasketManager);
        assertEq(feeCollector.hasRole(_BASKET_MANAGER_ROLE, newBasketManager), true);
        assertEq(feeCollector.hasRole(_BASKET_MANAGER_ROLE, basketManager), false);
    }

    function test_setBasketManager_revertsWhen_zeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        feeCollector.setBasketManager(address(0));
    }

    function testFuzz_setSponser(address oldSponser, address newSponser) public {
        vm.assume(newSponser != address(0) && oldSponser != address(0));
        vm.assume(oldSponser != newSponser);
        vm.startPrank(admin);
        feeCollector.setSponser(address(basketToken), oldSponser);
        assertEq(feeCollector.basketTokenSponsers(address(basketToken)), oldSponser);
        assert(feeCollector.hasRole(_SPONSOR_ROLE, oldSponser));
        feeCollector.setSponser(address(basketToken), newSponser);
        assertEq(feeCollector.basketTokenSponsers(address(basketToken)), newSponser);
        assert(!feeCollector.hasRole(_SPONSOR_ROLE, oldSponser));
        assert(feeCollector.hasRole(_SPONSOR_ROLE, newSponser));
    }

    function testFuzz_setSponser_revertsWhen_notBasketToken(address token) public {
        vm.assume(token != basketToken && token != address(0));
        vm.expectRevert(FeeCollector.NotBasketToken.selector);
        vm.prank(admin);
        feeCollector.setSponser(token, sponsor);
    }

    function testFuzz_setSponserSplit(uint16 sponsorSplit) public {
        vm.assume(sponsorSplit < _MAX_FEE);
        vm.prank(admin);
        feeCollector.setSponserSplit(address(basketToken), sponsorSplit);
        assertEq(feeCollector.basketTokenSponserSplits(address(basketToken)), sponsorSplit);
    }

    function testFuzz_setSponserSplit_revertsWhen_notBasketToken(address token) public {
        vm.assume(token != basketToken && token != address(0));
        vm.expectRevert(FeeCollector.NotBasketToken.selector);
        vm.prank(admin);
        feeCollector.setSponserSplit(token, 10);
    }

    function testFuzz_setSponserSplit_revertsWhen_splitTooHigh(uint16 sponsorSplit) public {
        vm.assume(sponsorSplit > _MAX_FEE);
        vm.prank(admin);
        vm.expectRevert(FeeCollector.SponserSplitTooHigh.selector);
        feeCollector.setSponserSplit(address(basketToken), sponsorSplit);
    }

    function testFuzz_setSponserSplit_revertsWhen_noSponser(uint16 sponsorSplit) public {
        vm.assume(sponsorSplit < _MAX_FEE);
        vm.startPrank(admin);
        feeCollector.setSponser(address(basketToken), address(0));
        vm.expectRevert(FeeCollector.NoSponser.selector);
        feeCollector.setSponserSplit(address(basketToken), sponsorSplit);
    }

    function testFuzz_notifyHarvestFee(uint256 shares, uint16 sponsorSplit) public {
        vm.assume(shares > _FEE_SPLIT_DECIMALS && shares < type(uint256).max / shares);
        vm.assume(sponsorSplit < _MAX_FEE);
        vm.prank(admin);
        feeCollector.setSponserSplit(address(basketToken), sponsorSplit);
        vm.prank(basketToken);
        feeCollector.notifyHarvestFee(shares);
        uint256 expectedSponserFee = shares.mulDiv(sponsorSplit, _FEE_SPLIT_DECIMALS);
        uint256 expectedTreasuryFee = shares - expectedSponserFee;
        assertEq(feeCollector.sponsorFeesCollected(address(basketToken)), expectedSponserFee);
        assertEq(feeCollector.treasuryFeesCollected(address(basketToken)), expectedTreasuryFee);
    }

    function testFuzz_notifyHarvestFee_revertsWhenNotBasketToken(address token) public {
        vm.assume(token != basketToken && token != address(0));
        vm.expectRevert(FeeCollector.NotBasketToken.selector);
        vm.prank(token);
        feeCollector.notifyHarvestFee(100);
    }

    function testFuzz_withdrawSponserFee(uint256 shares, uint16 sponsorSplit) public {
        vm.assume(sponsorSplit < _MAX_FEE);
        vm.prank(admin);
        feeCollector.setSponserSplit(address(basketToken), sponsorSplit);
        testFuzz_notifyHarvestFee(shares, sponsorSplit);
        uint256 sponsorFee = feeCollector.sponsorFeesCollected(address(basketToken));
        vm.mockCall(
            address(basketToken),
            abi.encodeCall(BasketToken.proRataRedeem, (sponsorFee, sponsor, address(feeCollector))),
            abi.encode(0)
        );
        vm.prank(sponsor);
        feeCollector.withdrawSponserFee(address(basketToken));
        assertEq(feeCollector.sponsorFeesCollected(address(basketToken)), 0);
    }

    function testFuzz_withdrawSponserFee_revertsWhen_notSponser(address caller) public {
        vm.assume(caller != address(0) && caller != sponsor);
        vm.startPrank(admin);
        feeCollector.setSponser(address(basketToken), sponsor);
        feeCollector.setSponserSplit(address(basketToken), 10);
        vm.stopPrank();
        vm.prank(caller);
        vm.expectRevert(_formatAccessControlError(caller, _SPONSOR_ROLE));
        feeCollector.withdrawSponserFee(address(basketToken));
    }

    function testFuzz_withdrawSponserFee_revertsWhen_notBasketToken(address token) public {
        vm.assume(token != basketToken && token != address(0));
        vm.expectRevert(FeeCollector.NotBasketToken.selector);
        vm.prank(sponsor);
        feeCollector.withdrawSponserFee(token);
    }

    function testFuzz_withdrawTreasuryFee(uint256 shares, uint16 sponsorSplit) public {
        vm.assume(sponsorSplit < _MAX_FEE);
        testFuzz_notifyHarvestFee(shares, sponsorSplit);

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

    function testFuzz_withdrawTreasuryFee_revertsWhen_notTreasury(address caller) public {
        vm.assume(caller != address(0) && caller != treasury);
        vm.startPrank(admin);
        feeCollector.setSponser(address(basketToken), sponsor);
        feeCollector.setSponserSplit(address(basketToken), 10);
        vm.stopPrank();
        vm.prank(caller);
        vm.expectRevert(_formatAccessControlError(caller, _PROTOCOL_TREASURY_ROLE));
        feeCollector.withdrawTreasuryFee(address(basketToken));
    }

    function testFuzz_withdrawTreasuryFee_revertsWhen_notBasketToken(address token) public {
        vm.assume(token != basketToken && token != address(0));
        vm.expectRevert(FeeCollector.NotBasketToken.selector);
        vm.prank(treasury);
        feeCollector.withdrawTreasuryFee(token);
    }
}
