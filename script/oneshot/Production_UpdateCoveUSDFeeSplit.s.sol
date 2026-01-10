// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { UpdateCoveUSDFeeSplitBase } from "./UpdateCoveUSDFeeSplitBase.s.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IMilkman } from "src/interfaces/deps/milkman/IMilkman.sol";

/// @title Production_UpdateCoveUSDFeeSplit
/// @notice Updates coveUSD fee split for ETH production via community multisig.
contract ProductionUpdateCoveUSDFeeSplit is UpdateCoveUSDFeeSplitBase {
    address internal constant _CHAINLINK_DYNAMIC_SLIPPAGE_CHECKER = 0xe80a1C615F75AFF7Ed8F08c9F21f9d00982D666c;
    address internal constant _CHAINLINK_USDC_ETH_FEED = 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4;
    uint256 internal constant _SLIPPAGE_BPS = 50;

    function _safe() internal view override returns (address) {
        return COVE_COMMUNITY_MULTISIG;
    }

    function _maybeQueueEthTransfer() internal override {
        uint256 ethBalance = address(_safe()).balance;
        if (ethBalance > 0) {
            addToBatch(ETH_WETH, ethBalance, abi.encodeWithSignature("deposit()"));
            addToBatch(ETH_WETH, 0, abi.encodeCall(IERC20.approve, (TOKEMAK_MILKMAN, ethBalance)));

            address[] memory priceFeeds = new address[](1);
            priceFeeds[0] = _CHAINLINK_USDC_ETH_FEED;
            bool[] memory reverses = new bool[](1);
            reverses[0] = true;
            bytes memory expectedOutData = abi.encode(priceFeeds, reverses);
            bytes memory priceCheckerData = abi.encode(_SLIPPAGE_BPS, expectedOutData);

            addToBatch(
                TOKEMAK_MILKMAN,
                0,
                abi.encodeCall(
                    IMilkman.requestSwapExactTokensForTokens,
                    (
                        ethBalance,
                        IERC20(ETH_WETH),
                        IERC20(ETH_USDC),
                        COVE_OPS_MULTISIG,
                        bytes32(0),
                        _CHAINLINK_DYNAMIC_SLIPPAGE_CHECKER,
                        priceCheckerData
                    )
                )
            );
        }
    }
}
