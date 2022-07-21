pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Libs/LibEIP712ExchangeDomain.sol";
import "./Libs/LibOrder.sol";
import "../Utils/Refundable.sol";
import "./ExchangeCore.sol";

contract Exchange is
    Ownable,
    LibEIP712ExchangeDomain,
    Refundable,
    ExchangeCore
{
    using LibOrder for LibOrder.Order;

    /// @param chainId Chain ID of the network this contract is deployed on.
    constructor (uint256 chainId) LibEIP712ExchangeDomain(chainId) {}

    /// @dev Fills the input order.
    /// @param order Order struct containing order specifications.
    /// @param signature Proof that order has been created by maker.
    /// @return fulfilled boolean
    function fillOrder(
        LibOrder.Order memory order,
        bytes memory signature,
        bytes32 marketIdentifier
    )
        override
        public
        payable
        refundFinalBalanceNoReentry
        returns (bool fulfilled)
    {
        fulfilled = _fillOrder(
            order,
            signature,
            msg.sender,
            marketIdentifier
        );
        return fulfilled;
    }

    /// @dev Fills the input order.
    /// @param order Order struct containing order specifications.
    /// @param signature Proof that order has been created by maker.
    /// @param takerAddress address to fulfill the order for / gift.
    /// @return fulfilled boolean
    function fillOrderFor(
        LibOrder.Order memory order,
        bytes memory signature,
        address takerAddress,
        bytes32 marketIdentifier
    )
        override
        public
        payable
        refundFinalBalanceNoReentry
        returns (bool fulfilled)
    {
        fulfilled = _fillOrder(
            order,
            signature,
            takerAddress,
            marketIdentifier
        );
        return fulfilled;
    }

    /// @dev After calling, the order can not be filled anymore.
    /// @param order Order struct containing order specifications.
    function cancelOrder(LibOrder.Order memory order)
        override
        public
        payable
        refundFinalBalanceNoReentry
    {
        _cancelOrder(order);
    }

    /// @dev Cancels all orders created by makerAddress with a salt less than or equal to the targetOrderEpoch
    ///      and senderAddress equal to msg.sender (or null address if msg.sender == makerAddress).
    /// @param targetOrderEpoch Orders created with a salt less or equal to this value will be cancelled.
    function cancelOrdersUpTo(uint256 targetOrderEpoch)
        override
        external
        payable
        refundFinalBalanceNoReentry
    {
        address makerAddress = msg.sender;
        // orderEpoch is initialized to 0, so to cancelUpTo we need salt + 1
        uint256 newOrderEpoch = targetOrderEpoch + 1;
        uint256 oldOrderEpoch = orderEpoch[makerAddress];

        // Ensure orderEpoch is monotonically increasing
        if (newOrderEpoch <= oldOrderEpoch) {
            revert('EXCHANGE: order epoch error');
        }

        // Update orderEpoch
        orderEpoch[makerAddress] = newOrderEpoch;
        emit CancelUpTo(
            makerAddress,
            newOrderEpoch
        );
    }

    /// @dev Gets information about an order: status, hash, and amount filled.
    /// @param order Order to gather information on.
    /// @return orderInfo Information about the order and its state.
    ///         See LibOrder.OrderInfo for a complete description.
    function getOrderInfo(LibOrder.Order memory order)
        override
        public
        view
        returns (LibOrder.OrderInfo memory orderInfo)
    {
        // Compute the order hash
        orderInfo.orderHash = order.getTypedDataHash(EIP712_EXCHANGE_DOMAIN_HASH);

        bool isTakerAssetDataERC20 = _isERC20Proxy(order.takerAssetData);
        bool isMakerAssetDataERC20 = _isERC20Proxy(order.makerAssetData);

        if (isTakerAssetDataERC20 && !isMakerAssetDataERC20) {
            orderInfo.orderType = LibOrder.OrderType.LIST;
        } else if (!isTakerAssetDataERC20 && isMakerAssetDataERC20) {
            orderInfo.orderType = LibOrder.OrderType.OFFER;
        } else if (!isTakerAssetDataERC20 && !isMakerAssetDataERC20) {
            orderInfo.orderType = LibOrder.OrderType.SWAP;
        } else {
            orderInfo.orderType = LibOrder.OrderType.INVALID;
        }

        // If order.makerAssetAmount is zero, we also reject the order.
        // While the Exchange contract handles them correctly, they create
        // edge cases in the supporting infrastructure because they have
        // an 'infinite' price when computed by a simple division.
        if (order.makerAssetAmount == 0) {
            orderInfo.orderStatus = LibOrder.OrderStatus.INVALID_MAKER_ASSET_AMOUNT;
            return orderInfo;
        }

        // If order.takerAssetAmount is zero, then the order will always
        // be considered filled because 0 == takerAssetAmount == orderTakerAssetFilledAmount
        // Instead of distinguishing between unfilled and filled zero taker
        // amount orders, we choose not to support them.
        if (order.takerAssetAmount == 0) {
            orderInfo.orderStatus = LibOrder.OrderStatus.INVALID_TAKER_ASSET_AMOUNT;
            return orderInfo;
        }

        // Validate order expiration
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp >= order.expirationTimeSeconds) {
            orderInfo.orderStatus = LibOrder.OrderStatus.EXPIRED;
            return orderInfo;
        }

        // Check if order has been cancelled
        if (cancelled[orderInfo.orderHash]) {
            orderInfo.orderStatus = LibOrder.OrderStatus.CANCELLED;
            return orderInfo;
        }

        // Check if order has been filled
        if (filled[orderInfo.orderHash]) {
            orderInfo.orderStatus = LibOrder.OrderStatus.FILLED;
            return orderInfo;
        }

        if (orderEpoch[order.makerAddress] > order.salt) {
            orderInfo.orderStatus = LibOrder.OrderStatus.CANCELLED;
            return orderInfo;
        }

        // All other statuses are ruled out: order is Fillable
        orderInfo.orderStatus = LibOrder.OrderStatus.FILLABLE;
        return orderInfo;
    }

    function returnAllETHToOwner() public payable onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function returnERC20ToOwner(address ERC20Token) public payable onlyOwner {
        IERC20 CustomToken = IERC20(ERC20Token);
        CustomToken.transferFrom(address(this), msg.sender, CustomToken.balanceOf(address(this)));
    }

    receive() external payable {}
}
