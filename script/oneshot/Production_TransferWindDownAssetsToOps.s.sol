// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { VmSafe } from "forge-std/Vm.sol";

import { BuildDeploymentJsonNames } from "script/utils/BuildDeploymentJsonNames.sol";

/// @title Production_TransferWindDownAssetsToOps
/// @notice One-shot Safe batch to transfer wind-down assets from community multisig to ops multisig.
/// @dev Actions queued by this script:
/// 1. Transfer full community Safe balances of USDC, ysUSDC, sUSDe, sfrxUSD, ysyG-yvUSDS-1, coveYFI, YFI, and dYFI.
/// 2. Skip any token with zero balance at execution time.
/// 3. Do not redeem ERC4626 shares, trade assets, or transfer ETH.
contract ProductionTransferWindDownAssetsToOps is DeployScript, BatchScript, BuildDeploymentJsonNames {
    address internal constant _USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant _YSUSDC = 0xF7DE3c70F2db39a188A81052d2f3C8e3e217822a;
    address internal constant _SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address internal constant _SFRXUSD = 0xcf62F905562626CfcDD2261162a51fd02Fc9c5b6;
    address internal constant _YSYG_YVUSDS_1 = 0x81f78DeF7a3a8B0F6aABa69925efC69E70239D95;
    address internal constant _COVEYFI = 0xFf71841EeFca78a64421db28060855036765c248;
    address internal constant _YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address internal constant _DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;

    function _buildPrefix() internal pure override returns (string memory) {
        return "Production_";
    }

    function _safe() internal pure returns (address) {
        return COVE_COMMUNITY_MULTISIG;
    }

    function _opsSafe() internal pure returns (address) {
        return COVE_OPS_MULTISIG;
    }

    /// @notice Build and execute the one-shot Safe batch.
    /// @dev Transfers full balances of the curated token set from community Safe to ops Safe.
    function deploy() public isBatch(_safe()) {
        deployer.setAutoBroadcast(true);

        address safe = _safe();
        address opsSafe = _opsSafe();
        require(opsSafe != address(0), "ops safe missing");
        require(opsSafe != safe, "ops equals community");

        address[] memory tokens = _tokens();
        bool queuedTransfer;

        for (uint256 i; i < tokens.length; ++i) {
            address token = tokens[i];
            uint256 balance = IERC20(token).balanceOf(safe);
            if (balance == 0) {
                continue;
            }

            bytes memory ret = addToBatch(token, 0, abi.encodeCall(IERC20.transfer, (opsSafe, balance)));
            if (ret.length > 0) {
                require(abi.decode(ret, (bool)), "transfer failed");
            }
            queuedTransfer = true;
        }

        if (!queuedTransfer) {
            return;
        }

        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            executeBatch(true);
        } else {
            executeBatch(false);
        }
    }

    function _tokens() internal pure returns (address[] memory tokens) {
        tokens = new address[](8);
        tokens[0] = _USDC;
        tokens[1] = _YSUSDC;
        tokens[2] = _SUSDE;
        tokens[3] = _SFRXUSD;
        tokens[4] = _YSYG_YVUSDS_1;
        tokens[5] = _COVEYFI;
        tokens[6] = _YFI;
        tokens[7] = _DYFI;
    }
}
