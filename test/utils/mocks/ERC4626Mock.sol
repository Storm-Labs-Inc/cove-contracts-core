// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC4626Mock is IERC4626, ERC20 {
    IERC20 private immutable _asset;
    uint8 private immutable _decimals;

    constructor(IERC20 asset_, string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _asset = asset_;
        _decimals = decimals_;
    }

    function asset() external view returns (address) {
        return address(_asset);
    }

    function totalAssets() external view returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public pure returns (uint256) {
        return assets; // 1:1 conversion for testing
    }

    function convertToAssets(uint256 shares) public pure returns (uint256) {
        return shares; // 1:1 conversion for testing
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function previewDeposit(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256) {
        uint256 shares = convertToShares(assets);
        _asset.transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        return shares;
    }

    function maxMint(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function previewMint(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    function mint(uint256 shares, address receiver) external returns (uint256) {
        uint256 assets = convertToAssets(shares);
        _asset.transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        return assets;
    }

    function maxWithdraw(address owner) external view returns (uint256) {
        return convertToAssets(balanceOf(owner));
    }

    function previewWithdraw(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256) {
        uint256 shares = convertToShares(assets);
        _burn(owner, shares);
        _asset.transfer(receiver, assets);
        return shares;
    }

    function maxRedeem(address owner) external view returns (uint256) {
        return balanceOf(owner);
    }

    function previewRedeem(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256) {
        uint256 assets = convertToAssets(shares);
        _burn(owner, shares);
        _asset.transfer(receiver, assets);
        return assets;
    }

    function decimals() public view override(ERC20, IERC20Metadata) returns (uint8) {
        return _decimals;
    }
}
