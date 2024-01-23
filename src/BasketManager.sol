// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { ERC7540AsyncExample } from "src/ERC7540AsyncExample.sol";
import { IERC7540AsyncExample } from "src/interfaces/IERC7540AsyncExample.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BasketManager {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_NUM_OF_VAULTS = 256;
    address[] public vaults;
    address[] public basketTokens;
    mapping(uint256 => address) public bitFlagToVault;
    mapping(address => uint256) public vaultToIndexPlusOne;
    mapping(address => address) public basketToAllocationResolver;

    address public basketImplementation;
    address public rootAsset;
    address public oracleRegistry;
    uint8 public rootAssetDecimals;
    uint256 public lastUpdateTimestamp;

    // TODO: why do I have to use internal here?
    mapping(address => RebalanceInfo) internal _rebalanceInfos;

    struct RebalanceInfo {
        address[] pendingDepositors;
        address[] pendingWithdrawers;
    }

    constructor() { }

    function initialize(address _basketImplementation, address _oracleRegistry) public {
        basketImplementation = _basketImplementation;
        rootAsset = IERC7540AsyncExample(basketImplementation).asset();
        // rootAssetDecimals = IERC20(rootAsset).decimals();
        rootAssetDecimals = 18;
        oracleRegistry = _oracleRegistry;
    }

    // Creates basket with given selection bitFlag and type
    function createNewBasket(
        string memory basketName,
        string memory symbol,
        uint256 bitFlag,
        address allocationResolver
    )
        public
        returns (address basket)
    {
        basket = address(new ERC7540AsyncExample(IERC20(rootAsset), basketName, symbol));
        basketTokens.push(basket);
        bitFlagToVault[bitFlag] = basket;
        basketToAllocationResolver[basket] = allocationResolver;
    }

    // solhint-disable-next-line no-unused-vars
    function requestDeposit(address basket, uint256 assetAmount, address to) external {
        IERC20(rootAsset).safeTransferFrom(msg.sender, address(this), assetAmount);
        IERC7540AsyncExample(basket).requestDepositFromManager(assetAmount, msg.sender);
        _rebalanceInfos[basket].pendingDepositors.push(msg.sender);
    }

    // TODO: only for testing remove later
    function fulfillDeposit(address basket, address operator) external {
        IERC7540AsyncExample(basket).fulfillDeposit(operator);
    }

    function _fulfillDeposit(address basket, address operator) internal {
        IERC7540AsyncExample(basket).fulfillDeposit(operator);
    }

    // solhint-disable-next-line no-unused-vars
    function requestRedeem(address basket, uint256 basketTokenAmount, address to) public {
        IERC7540AsyncExample(basket).requestRedeem(basketTokenAmount, msg.sender, msg.sender);
        _rebalanceInfos[basket].pendingWithdrawers.push(msg.sender);
    }

    function rebalance(address[] memory baskets) public {
        for (uint256 basketIndex = 0; basketIndex < baskets.length; basketIndex++) {
            address basket = baskets[basketIndex];
            // Call fulfill deposit for all pending depositors
            for (uint256 i = 0; i < _rebalanceInfos[basket].pendingDepositors.length; i++) {
                _fulfillDeposit(basket, _rebalanceInfos[basket].pendingDepositors[i]);
            }
            delete _rebalanceInfos[basket].pendingDepositors;

            // Call withdraw for all pending withdrawers
            for (uint256 i = 0; i < _rebalanceInfos[basket].pendingWithdrawers.length; i++) {
                uint256 amount = IERC7540AsyncExample(basket).maxWithdraw(_rebalanceInfos[basket].pendingWithdrawers[i]);
                IERC7540AsyncExample(basket).withdrawFromManager(
                    amount, _rebalanceInfos[basket].pendingWithdrawers[i], _rebalanceInfos[basket].pendingWithdrawers[i]
                );
                // TODO: batch these transfers in the future
                require(
                    IERC20(rootAsset).transfer(_rebalanceInfos[basket].pendingWithdrawers[i], amount), "Transfer failed"
                );
            }
            delete _rebalanceInfos[basket].pendingWithdrawers;
        }
    }

    function getPendingDepositors(address basket) public view returns (address[] memory) {
        return _rebalanceInfos[basket].pendingDepositors;
    }

    function getPendingWithdrawers(address basket) public view returns (address[] memory) {
        return _rebalanceInfos[basket].pendingWithdrawers;
    }
}
