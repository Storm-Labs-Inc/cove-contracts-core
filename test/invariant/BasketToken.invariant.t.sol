// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { StdInvariant } from "lib/forge-std/src/StdInvariant.sol";
import { Clones } from "lib/openzeppelin-contracts/contracts/proxy/Clones.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { BasketToken } from "src/BasketToken.sol";
import { InvariantHandler } from "test/invariant/InvariantHandler.t.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract BasketToken_InvariantTest is StdInvariant, BaseTest {
    BasketTokenHandler public basketTokenHandler;

    function setUp() public override {
        super.setUp();
        basketTokenHandler = new BasketTokenHandler(new BasketToken());
        vm.label(address(basketTokenHandler), "basketTokenHandler");
        targetContract(address(basketTokenHandler));
    }

    function invariant_basketManagerIsImmutableContractCreator() public {
        if (!basketTokenHandler.initialized()) {
            assertEq(basketTokenHandler.basketToken(), address(0), "BasketToken should not be initialized");
            return;
        }
        address basketManager = basketTokenHandler.basketToken().basketManager();
        assertEq(basketManager, address(basketTokenHandler), "BasketManager is not the contract creator");
    }
}

contract BasketTokenHandler is InvariantHandler {
    BasketToken public basketTokenImpl;
    BasketToken public basketToken;
    bool public initialized = false;

    constructor(BasketToken basketTokenImpl_) {
        basketTokenImpl = basketTokenImpl_;
    }

    function initialize(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        uint256 bitFlag_,
        address strategy_,
        address admin_
    )
        public
    {
        if (initialized) {
            return;
        }
        initialized = true;
        basketToken = BasketToken(Clones.clone(address(basketTokenImpl)));
        basketToken.initialize(asset_, name_, symbol_, bitFlag_, strategy_, admin_);
    }
}
