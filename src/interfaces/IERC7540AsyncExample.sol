// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC7540AsyncExample {
    // Events
    event DepositRequest(address indexed sender, address indexed operator, uint256 assets);
    event RedeemRequest(address indexed sender, address indexed operator, address indexed owner, uint256 shares);

    // Functions
    function totalAssets() external view returns (uint256);

    function requestDeposit(uint256 assets, address operator) external;
    function requestDepositFromManager(uint256 assets, address operator) external;
    function pendingDepositRequest(address operator) external view returns (uint256 assets);

    function requestRedeem(uint256 shares, address operator, address requestOwner) external returns (uint256 id);
    function pendingRedeemRequest(uint256 id) external view returns (uint256 shares);
    function ownerOf(uint256 rid) external view returns (address);
    function transferRequest(uint256 rid, address to) external returns (address);
    function claimRequest(uint256 rid, address to) external returns (address);

    function fulfillDeposit(address operator) external returns (uint256 shares);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
    function withdraw(uint256 assets, address receiver, address operator) external returns (uint256 shares);
    function withdrawFromManager(
        uint256 assets,
        address receiver,
        address operator
    )
        external
        returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address operator) external returns (uint256 assets);

    function maxWithdraw(address operator) external view returns (uint256);
    function maxRedeem(address operator) external view returns (uint256);
    function maxDeposit(address operator) external view returns (uint256);
    function maxMint(address operator) external view returns (uint256);

    function previewDeposit(uint256 assets) external pure returns (uint256);
    function previewMint(uint256 shares) external pure returns (uint256);
    function asset() external view returns (address);
}
