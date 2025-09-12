// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ClonesWithImmutableArgs } from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import { GPv2Order } from "src/deps/cowprotocol/GPv2Order.sol";

import { TokenSwapAdapter } from "src/swap_adapters/TokenSwapAdapter.sol";
import { CoWSwapCloneWith4626 } from "src/swap_adapters/experimental/CoWSwapCloneWith4626.sol";
import { ExternalTrade } from "src/types/Trades.sol";

/// @title CoWSwapAdapterWith4626
/// @notice Adapter for executing and completing token swaps using CoWSwap protocol with ERC4626 support.
contract CoWSwapAdapterWith4626 is TokenSwapAdapter {
    using GPv2Order for GPv2Order.Data;
    using SafeERC20 for IERC20;

    /// INTERNAL STRUCTS ///
    struct UnderlyingOptions {
        uint8 underlyingDepthSell;
        uint8 underlyingDepthBuy;
    }

    /// CONSTANTS ///
    /// @dev Storage slot for CoWSwapAdapter specific data.
    bytes32 internal constant _COWSWAP_ADAPTER_STORAGE =
        bytes32(uint256(keccak256("cove.basketmanager.cowswapadapter4626.storage")) - 1);

    /// @notice Address of the clone implementation used for creating CoWSwapClone contracts.
    address public immutable cloneImplementation;

    /// STRUCTS ///
    /// @dev Structure to store adapter-specific data.
    struct CoWSwapAdapterStorage {
        uint32 orderValidTo;
    }

    /// EVENTS ///
    /// @notice Emitted when a new order is created.
    /// @param sellToken The address of the token to be sold.
    /// @param buyToken The address of the token to be bought.
    /// @param sellAmount The amount of the sell token.
    /// @param buyAmount The amount of the buy token.
    /// @param validTo The timestamp until which the order is valid.
    /// @param swapContract The address of the swap contract.
    event OrderCreated(
        address indexed sellToken,
        address indexed buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint32 validTo,
        address swapContract
    );

    /// @notice Emitted when a token swap is completed.
    /// @param sellToken The address of the token sold.
    /// @param buyToken The address of the token bought.
    /// @param claimedSellAmount The amount of sell tokens claimed.
    /// @param claimedBuyAmount The amount of buy tokens claimed.
    /// @param swapContract The address of the swap contract.
    event TokenSwapCompleted(
        address indexed sellToken,
        address indexed buyToken,
        uint256 claimedSellAmount,
        uint256 claimedBuyAmount,
        address swapContract
    );

    /// ERRORS ///
    /// @notice Thrown when the address is zero.
    error ZeroAddress();
    /// @notice Thrown when the length of the options array does not match the length of the external trades array.
    error OptLengthMismatch();

    /// @notice Constructor to initialize the CoWSwapAdapter with the clone implementation address.
    /// @param cloneImplementation_ The address of the clone implementation contract.
    constructor(address cloneImplementation_) payable {
        if (cloneImplementation_ == address(0)) {
            revert ZeroAddress();
        }
        cloneImplementation = cloneImplementation_;
    }

    /// @notice Executes a series of token swaps by creating orders on the CoWSwap protocol.
    /// @param externalTrades The external trades to execute.
    /// @param extraData Additional data for handling underlying tokens and depth.
    function executeTokenSwap(
        ExternalTrade[] calldata externalTrades,
        bytes calldata extraData
    )
        external
        payable
        override
    {
        uint32 validTo = uint32(block.timestamp + 60 minutes);
        _cowswapAdapterStorage().orderValidTo = validTo;

        // Decode extra data if present
        UnderlyingOptions[] calldata opts;
        // slither-disable-next-line assembly
        assembly {
            opts.offset := add(add(extraData.offset, calldataload(extraData.offset)), 0x20)
            opts.length := calldataload(add(extraData.offset, calldataload(extraData.offset)))
        }
        if (opts.length != externalTrades.length) {
            revert OptLengthMismatch();
        }
        for (uint256 i = 0; i < externalTrades.length;) {
            unchecked {
                ++i;
            }
        }
        for (uint256 i = 0; i < externalTrades.length;) {
            UnderlyingOptions calldata opt = opts[i];

            (address finalSellToken, uint256 finalSellAmount, uint8 depthSell, address outerSellToken) =
                _handleSellToken(externalTrades[i], opt);

            (address finalBuyToken, uint256 finalBuyAmount, uint8 depthBuy, address outerBuyToken) =
                _handleBuyToken(externalTrades[i], opt);

            _createOrder(
                finalSellToken,
                finalBuyToken,
                finalSellAmount,
                finalBuyAmount,
                validTo,
                depthSell,
                depthBuy,
                outerSellToken,
                outerBuyToken,
                externalTrades[i].sellAmount,
                externalTrades[i].minAmount
            );
            unchecked {
                // Overflow not possible: i is bounded by externalTrades.length
                ++i;
            }
        }
    }

    /// @notice Completes the token swaps by claiming the tokens from the CoWSwapClone contracts.
    /// @param externalTrades The external trades that were executed and need to be settled.
    /// @return claimedAmounts A 2D array containing the claimed amounts of sell and buy tokens for each trade.
    function completeTokenSwap(ExternalTrade[] calldata externalTrades)
        external
        payable
        override
        returns (uint256[2][] memory claimedAmounts)
    {
        uint256 length = externalTrades.length;
        claimedAmounts = new uint256[2][](length);
        uint32 validTo = _cowswapAdapterStorage().orderValidTo;

        for (uint256 i = 0; i < length;) {
            bytes32 salt = keccak256(
                abi.encodePacked(
                    externalTrades[i].sellToken,
                    externalTrades[i].buyToken,
                    externalTrades[i].sellAmount,
                    externalTrades[i].minAmount,
                    validTo
                )
            );
            address swapContract = ClonesWithImmutableArgs.addressOfClone3(salt);
            // Expect the clone to return the originally requested token's amounts
            // slither-disable-next-line calls-loop
            (uint256 claimedSellAmount, uint256 claimedBuyAmount) = CoWSwapCloneWith4626(swapContract).claim();
            claimedAmounts[i] = [claimedSellAmount, claimedBuyAmount];
            // slither-disable-next-line reentrancy-events
            emit TokenSwapCompleted(
                externalTrades[i].sellToken,
                externalTrades[i].buyToken,
                claimedSellAmount,
                claimedBuyAmount,
                swapContract
            );
            unchecked {
                // Overflow not possible: i is bounded by externalTrades.length
                ++i;
            }
        }
    }

    /// @dev Internal function to create an order on the CoWSwap protocol.
    /// @param sellTokenFinal The final address of the token to sell.
    /// @param buyTokenFinal The final address of the token to buy.
    /// @param sellAmountFinal The final amount of the sell token.
    /// @param buyAmountFinal The final amount of the buy token.
    /// @param validTo The timestamp until which the order is valid.
    /// @param depthSell The depth of the sell token.
    /// @param depthBuy The depth of the buy token.
    /// @param outerSellToken The original address of the sell token.
    /// @param outerBuyToken The original address of the buy token.
    function _createOrder(
        address sellTokenFinal,
        address buyTokenFinal,
        uint256 sellAmountFinal,
        uint256 buyAmountFinal,
        uint32 validTo,
        uint8 depthSell,
        uint8 depthBuy,
        address outerSellToken,
        address outerBuyToken,
        uint256 outerSellAmount,
        uint256 outerBuyAmount
    )
        internal
    {
        // Deterministic salt based on trade parameters (outer tokens & amounts).
        bytes32 salt =
            keccak256(abi.encodePacked(outerSellToken, outerBuyToken, outerSellAmount, outerBuyAmount, validTo));

        address swapContract = ClonesWithImmutableArgs.clone3(
            cloneImplementation,
            abi.encodePacked(
                sellTokenFinal,
                buyTokenFinal,
                sellAmountFinal,
                buyAmountFinal,
                uint64(validTo),
                address(this),
                address(this),
                outerSellToken,
                outerBuyToken,
                depthSell,
                depthBuy
            ),
            salt
        );

        emit OrderCreated(outerSellToken, outerBuyToken, outerSellAmount, outerBuyAmount, validTo, swapContract);
        // slither-disable-start calls-loop
        IERC20(sellTokenFinal).safeTransfer(swapContract, sellAmountFinal);
        CoWSwapCloneWith4626(swapContract).initialize();
        // slither-disable-end calls-loop
    }

    /// @dev Handles token redemption for the sell side according to the provided options.
    function _handleSellToken(
        ExternalTrade calldata trade,
        UnderlyingOptions calldata opt
    )
        internal
        returns (address finalSellToken, uint256 finalSellAmount, uint8 depth, address outerToken)
    {
        outerToken = trade.sellToken;
        finalSellToken = trade.sellToken;
        finalSellAmount = trade.sellAmount;
        depth = opt.underlyingDepthSell;

        if (depth > 0) {
            for (uint8 i = 0; i < depth; ++i) {
                IERC4626 vault = IERC4626(finalSellToken);
                IERC20(finalSellToken).forceApprove(address(vault), finalSellAmount);
                finalSellAmount = vault.redeem(finalSellAmount, address(this), address(this));
                finalSellToken = vault.asset();
            }
        }
    }

    /// @dev Handles token conversion for the buy side to ensure we quote in underlying assets.
    function _handleBuyToken(
        ExternalTrade calldata trade,
        UnderlyingOptions calldata opt
    )
        internal
        view
        returns (address finalBuyToken, uint256 finalBuyAmount, uint8 depth, address outerToken)
    {
        outerToken = trade.buyToken;
        finalBuyToken = trade.buyToken;
        finalBuyAmount = trade.minAmount;
        depth = opt.underlyingDepthBuy;

        if (depth > 0) {
            for (uint8 i = 0; i < depth; ++i) {
                IERC4626 vault = IERC4626(finalBuyToken);
                finalBuyAmount = vault.convertToAssets(finalBuyAmount);
                finalBuyToken = vault.asset();
            }
        }
    }

    /// @dev Internal function to retrieve the storage for the CoWSwapAdapter.
    /// @return s The storage struct for the CoWSwapAdapter.
    function _cowswapAdapterStorage() internal pure returns (CoWSwapAdapterStorage storage s) {
        bytes32 slot = _COWSWAP_ADAPTER_STORAGE;
        // slither-disable-start assembly
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := slot
        }
        // slither-disable-end assembly
    }
}
