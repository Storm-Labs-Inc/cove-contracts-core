// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ClonesWithImmutableArgs } from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";

import { CoWSwapCloneWithAppData } from "src/swap_adapters/CoWSwapCloneWithAppData.sol";
import { TokenSwapAdapter } from "src/swap_adapters/TokenSwapAdapter.sol";
import { ExternalTrade } from "src/types/Trades.sol";

/// @title CoWSwapAdapterWithAppData
/// @notice Adapter variant that enforces a non-zero CoW Protocol appData hash for every clone.
contract CoWSwapAdapterWithAppData is TokenSwapAdapter {
    using SafeERC20 for IERC20;

    /// @dev Storage slot for CoWSwapAdapter specific data.
    bytes32 internal constant _COWSWAP_ADAPTER_STORAGE =
        bytes32(uint256(keccak256("cove.basketmanager.cowswapadapter.storage")) - 1);

    /// @notice Address of the clone implementation used for creating CoWSwapClone contracts.
    address public immutable cloneImplementation;

    /// @notice AppData hash that must be supplied to every CoW order.
    bytes32 public immutable appDataHash;

    /// @dev Structure to store adapter-specific data.
    struct CoWSwapAdapterStorage {
        uint32 orderValidTo;
    }

    /// EVENTS ///
    event OrderCreated(
        address indexed sellToken,
        address indexed buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint32 validTo,
        address swapContract
    );

    event TokenSwapCompleted(
        address indexed sellToken,
        address indexed buyToken,
        uint256 claimedSellAmount,
        uint256 claimedBuyAmount,
        address swapContract
    );

    /// ERRORS ///
    error ZeroAddress();
    error InvalidAppDataHash();

    constructor(address cloneImplementation_, bytes32 appDataHash_) payable {
        if (cloneImplementation_ == address(0)) {
            revert ZeroAddress();
        }
        if (appDataHash_ == bytes32(0)) {
            revert InvalidAppDataHash();
        }
        cloneImplementation = cloneImplementation_;
        appDataHash = appDataHash_;
    }

    /// @notice Executes a series of token swaps by creating orders on the CoWSwap protocol.
    function executeTokenSwap(ExternalTrade[] calldata externalTrades, bytes calldata) external payable override {
        uint32 validTo = uint32(block.timestamp + 60 minutes);
        _cowswapAdapterStorage().orderValidTo = validTo;
        for (uint256 i = 0; i < externalTrades.length;) {
            _createOrder(
                externalTrades[i].sellToken,
                externalTrades[i].buyToken,
                externalTrades[i].sellAmount,
                externalTrades[i].minAmount,
                validTo
            );
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Completes the token swaps by claiming the tokens from the CoWSwapClone contracts.
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
            (uint256 claimedSellAmount, uint256 claimedBuyAmount) = CoWSwapCloneWithAppData(swapContract).claim();
            claimedAmounts[i] = [claimedSellAmount, claimedBuyAmount];
            emit TokenSwapCompleted(
                externalTrades[i].sellToken,
                externalTrades[i].buyToken,
                claimedSellAmount,
                claimedBuyAmount,
                swapContract
            );
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Internal function to create an order on the CoWSwap protocol.
    function _createOrder(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint32 validTo
    )
        internal
    {
        bytes32 salt = keccak256(abi.encodePacked(sellToken, buyToken, sellAmount, buyAmount, validTo));
        address swapContract = ClonesWithImmutableArgs.clone3(
            cloneImplementation,
            abi.encodePacked(
                sellToken, buyToken, sellAmount, buyAmount, uint64(validTo), address(this), address(this), appDataHash
            ),
            salt
        );
        emit OrderCreated(sellToken, buyToken, sellAmount, buyAmount, validTo, swapContract);
        IERC20(sellToken).safeTransfer(swapContract, sellAmount);
        CoWSwapCloneWithAppData(swapContract).initialize();
    }

    function _cowswapAdapterStorage() internal pure returns (CoWSwapAdapterStorage storage s) {
        bytes32 slot = _COWSWAP_ADAPTER_STORAGE;
        assembly {
            s.slot := slot
        }
    }
}
