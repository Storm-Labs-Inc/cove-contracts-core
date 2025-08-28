// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IAutopool } from "src/interfaces/deps/tokemak/IAutopool.sol";

contract MockAutopool is ERC4626, IAutopool {
    address public immutable baseAsset;
    bool public isShutdown;
    bool public paused;
    
    constructor(
        address _baseAsset,
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) ERC4626(IERC20(_baseAsset)) {
        baseAsset = _baseAsset;
    }
    
    function getDebt() external pure returns (uint256) {
        return 0;
    }
    
    function getIdle() external view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }
    
    function pause() external {
        paused = true;
    }
    
    function unpause() external {
        paused = false;
    }
    
    function shutdown() external {
        isShutdown = true;
    }
    
    // ERC20Permit functions (stub implementation)
    function permit(
        address,
        address,
        uint256,
        uint256,
        uint8,
        bytes32,
        bytes32
    ) external pure {
        // Stub implementation
    }
    
    function nonces(address) external pure returns (uint256) {
        return 0;
    }
    
    function DOMAIN_SEPARATOR() external pure returns (bytes32) {
        return bytes32(0);
    }
}