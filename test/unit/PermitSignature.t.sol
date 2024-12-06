// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import { console } from "forge-std/console.sol";
import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

import { BasketToken } from "src/BasketToken.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

contract PermitSignature_Test is BaseTest {
    address testAccount;
    uint256 testAccountPK;
    address basketToken;
    string public constant TEST_MNEMONIC = "test test test test test test test test test test test junk";

    function setUp() public override {
        forkNetworkAt("mainnet", 21_238_272);
        super.setUp();
        basketToken = address(new BasketToken());
        // (0) 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 (10000.000000000000000000 ETH)
        (testAccount, testAccountPK) = deriveRememberKey({ mnemonic: TEST_MNEMONIC, index: 0 });
    }

    function _generatePermitSignatureAndLog(
        address token,
        address owner,
        uint256 ownerPrivateKey,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    )
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        string memory typeHashInput =
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)";
        console.log("");
        console.log("Generating permit signature for token: ", token);
        console.log("EIP 712 input:");
        console.log("  DOMAIN_SEPARATOR: ", vm.toString(IERC20Permit(basketToken).DOMAIN_SEPARATOR()));
        console.log("  TYPEHASH input: ", typeHashInput);
        console.log("  TYPEHASH: ", vm.toString(keccak256(bytes(typeHashInput))));
        console.log("Signature parameters:");
        console.log("  Private Key: ", vm.toString(bytes32(ownerPrivateKey)));
        console.log("  Owner: ", owner);
        console.log("  Spender: ", address(0xbeef));
        console.log("  Value: ", uint256(1000 ether));
        console.log("  Nonce: ", nonce);
        console.log("  Deadline: ", _MAX_UINT256);
        (v, r, s) = _generatePermitSignature(token, owner, ownerPrivateKey, spender, value, nonce, deadline);
        console.log("");
        console.log("Generated signature: ");
        console.log("  v: ", v);
        console.log("  r: ", vm.toString(r));
        console.log("  s: ", vm.toString(s));
    }

    //// TESTS ////

    function test_permitSignature() public {
        // First permit
        address spender = address(0xbeef);
        uint256 value = 1000 ether;

        (uint8 v, bytes32 r, bytes32 s) = _generatePermitSignatureAndLog(
            basketToken,
            testAccount,
            testAccountPK,
            spender,
            value,
            IERC20Permit(basketToken).nonces(testAccount),
            _MAX_UINT256
        );

        IERC20Permit(basketToken).permit(testAccount, spender, value, _MAX_UINT256, v, r, s);
        assertEq(IERC20(basketToken).allowance(testAccount, spender), value);

        // Second permit
        spender = address(0xbeef);
        value = 2000 ether;

        (v, r, s) = _generatePermitSignatureAndLog(
            basketToken,
            testAccount,
            testAccountPK,
            spender,
            value,
            IERC20Permit(basketToken).nonces(testAccount),
            _MAX_UINT256
        );

        IERC20Permit(basketToken).permit(testAccount, spender, value, _MAX_UINT256, v, r, s);
        assertEq(IERC20(basketToken).allowance(testAccount, spender), value);
    }
}
