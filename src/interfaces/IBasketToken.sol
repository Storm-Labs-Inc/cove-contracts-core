// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC7540Deposit, IERC7540Operator, IERC7540Redeem } from "src/interfaces/IERC7540.sol";

/// @title IBasketToken
/// @notice Interface for the BasketToken contract.
interface IBasketToken is IERC20, IERC4626, IERC7540Operator, IERC7540Deposit, IERC7540Redeem, IERC165 {
    /// @notice Returns the total amount of assets pending deposit.
    /// @return The total pending deposit amount.
    function totalPendingDeposits() external view returns (uint256);

    /// @notice Returns the total number of shares pending redemption.
    /// @return The total pending redeem amount.
    function totalPendingRedemptions() external view returns (uint256);

    /// @notice Requests a deposit of assets.
    /// @param assets The amount of assets to deposit.
    /// @param controller The address of the controller.
    /// @param owner The address of the owner of the assets.
    /// @return requestId The ID of the deposit request.
    function requestDeposit(uint256 assets, address controller, address owner) external returns (uint256 requestId);

    /// @notice Requests a redemption of shares.
    /// @param shares The amount of shares to redeem.
    /// @param controller The address of the controller.
    /// @param owner The address of the owner of the shares.
    /// @return requestId The ID of the redeem request.
    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256 requestId);

    /// @notice Cancels a pending deposit request.
    function cancelDepositRequest() external;

    /// @notice Cancels a pending redeem request.
    function cancelRedeemRequest() external;

    /// @notice Returns the current epoch's target weights for the basket.
    /// @return The target weights for the basket.
    function getCurrentTargetWeights() external view returns (uint64[] memory);

    /// @notice Returns the target weights for a given epoch.
    /// @param epoch The epoch to get the target weights for.
    /// @return The target weights for the basket.
    function getTargetWeights(uint40 epoch) external view returns (uint64[] memory);

    /// @notice Returns the value of the basket in assets.
    /// @return The total value of the basket in assets.
    function totalAssets() external view returns (uint256);

    /// @notice Returns the address of the share token.
    /// @return The address of the share token.
    function share() external view returns (address);

    /// @notice Triggers a fallback redeem in case of a failed redemption fulfillment.
    function fallbackRedeemTrigger() external;

    /// @notice Returns true if the fallback has been triggered for a redemption request.
    /// @param requestId The ID of the redemption request.
    /// @return True if the fallback has been triggered, false otherwise.
    function fallbackTriggered(uint256 requestId) external view returns (bool);
}
