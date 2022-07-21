pragma solidity ^0.8.4;

import "../Utils/LibBytes.sol";
import "../Utils/LibSafeMath.sol";
import "../Utils/Refundable.sol";
import "./Libs/LibMath.sol";
import "./Libs/LibOrder.sol";
import "./Libs/LibEIP712ExchangeDomain.sol";
import "./interfaces/IExchangeCore.sol";
import "./MixinAssetProxyDispatcher.sol";
import "./MixinProtocolFees.sol";
import "./MixinSignatureValidator.sol";
import "../Proxies/interfaces/IAssetData.sol";

abstract contract MixinExchangeCore is
    IExchangeCore,
    LibEIP712ExchangeDomain,
    MixinAssetProxyDispatcher,
    MixinProtocolFees,
    MixinSignatureValidator
{
    using LibOrder for LibOrder.Order;
    using LibSafeMath for uint256;
    using LibBytes for bytes;

    /// @dev Mapping of orderHash => amount of takerAsset already bought by maker
    /// @return 0 The amount of taker asset filled.
    mapping (bytes32 => bool) public filled;

    /// @dev Mapping of orderHash => cancelled
    /// @return 0 Whether the order was cancelled.
    mapping (bytes32 => bool) public cancelled;

    /// @dev Mapping of makerAddress => senderAddress => lowest salt an order can have in order to be fillable
    ///      Orders with specified senderAddress and with a salt less than their epoch are considered cancelled
    mapping (address => mapping (address => uint256)) public orderEpoch;

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
        // If this function is called via `executeTransaction`, we only update the orderEpoch for the makerAddress/msg.sender combination.
        // This allows external filter contracts to add rules to how orders are cancelled via this function.
        address orderSenderAddress = makerAddress == msg.sender ? address(0) : msg.sender;

        // orderEpoch is initialized to 0, so to cancelUpTo we need salt + 1
        uint256 newOrderEpoch = targetOrderEpoch + 1;
        uint256 oldOrderEpoch = orderEpoch[makerAddress][orderSenderAddress];

        // Ensure orderEpoch is monotonically increasing
        if (newOrderEpoch <= oldOrderEpoch) {
            revert('EXCHANGE: order epoch error');
        }

        // Update orderEpoch
        orderEpoch[makerAddress][orderSenderAddress] = newOrderEpoch;
        emit CancelUpTo(
            makerAddress,
            orderSenderAddress,
            newOrderEpoch
        );
    }

    /// @dev Fills the input order.
    /// @param order Order struct containing order specifications.
    /// @param signature Proof that order has been created by maker.
    /// @return fulfilled boolean
    function fillOrder(
        LibOrder.Order memory order,
        bytes memory signature
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
            msg.sender
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
        address takerAddress
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
            takerAddress
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

     function isERC20Proxy(bytes memory assetData) internal pure returns (bool) {
        bytes4 assetProxyId = assetData.readBytes4(0);
        bytes4 erc20ProxyId = IAssetData(address(0)).ERC20Token.selector;

        return assetProxyId == erc20ProxyId;
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

        if (isERC20Proxy(order.takerAssetData) && !isERC20Proxy(order.makerAssetData)) {
            orderInfo.orderType = LibOrder.OrderType.LIST;
        } else if (isERC20Proxy(order.makerAssetData) && !isERC20Proxy(order.takerAssetData)) {
            orderInfo.orderType = LibOrder.OrderType.OFFER;
        } else if (!isERC20Proxy(order.makerAssetData) && !isERC20Proxy(order.takerAssetData)) {
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

        if (orderEpoch[order.makerAddress][order.senderAddress] > order.salt) {
            orderInfo.orderStatus = LibOrder.OrderStatus.CANCELLED;
            return orderInfo;
        }

        // All other statuses are ruled out: order is Fillable
        orderInfo.orderStatus = LibOrder.OrderStatus.FILLABLE;
        return orderInfo;
    }

    /// @dev Fills the input order.
    /// @param order Order struct containing order specifications.
    /// @param signature Proof that order has been created by maker.
    /// @param takerAddress orider fill for the taker.
    /// @return fulfilled boolean
    function _fillOrder(
        LibOrder.Order memory order,
        bytes memory signature,
        address takerAddress
    )
        internal
        returns (bool fulfilled)
    {
        // Fetch order info
        LibOrder.OrderInfo memory orderInfo = getOrderInfo(order);

        // Assert that the order is fillable by taker
        _assertFillableOrder(
            order,
            orderInfo,
            takerAddress,
            signature
        );

        bytes32 orderHash = orderInfo.orderHash;

        // Update state
        filled[orderHash] = true;

        // Settle order
        uint256 protocolFee = _settleOrder(
            orderInfo,
            order,
            takerAddress
        );

        notifyOrderFulfilled(order, orderHash, takerAddress, protocolFee);

        return filled[orderHash];
    }

    function notifyOrderFulfilled(LibOrder.Order memory order, bytes32 orderHash, address takerAddress, uint256 protocolFee) internal {
        emit Fill(
            order.makerAddress,
            order.royaltiesAddress,
            order.makerAssetData,
            order.takerAssetData,
            orderHash,
            takerAddress,
            msg.sender,
            order.makerAssetAmount,
            order.takerAssetAmount,
            order.royaltiesAmount,
            protocolFee
        );
    }

    /// @dev After calling, the order can not be filled anymore.
    ///      Throws if order is invalid or sender does not have permission to cancel.
    /// @param order Order to cancel. Order must be OrderStatus.FILLABLE.
    function _cancelOrder(LibOrder.Order memory order)
        internal
    {
        // Fetch current order status
        LibOrder.OrderInfo memory orderInfo = getOrderInfo(order);

        // Validate context
        _assertValidCancel(order, orderInfo);

        // Noop if order is already unfillable
        if (orderInfo.orderStatus != LibOrder.OrderStatus.FILLABLE) {
            return;
        }

        // Perform cancel
        _updateCancelledState(order, orderInfo.orderHash);
    }

    /// @dev Updates state with results of cancelling an order.
    ///      State is only updated if the order is currently fillable.
    ///      Otherwise, updating state would have no effect.
    /// @param order that was cancelled.
    /// @param orderHash Hash of order that was cancelled.
    function _updateCancelledState(
        LibOrder.Order memory order,
        bytes32 orderHash
    )
        internal
    {
        // Perform cancel
        cancelled[orderHash] = true;

        // Log cancel
        emit Cancel(
            order.makerAddress,
            order.makerAssetData,
            order.takerAssetData,
            msg.sender,
            orderHash
        );
    }

    event Test(bytes ad, address t);

    /// @dev Validates context for fillOrder. Succeeds or throws.
    /// @param order to be filled.
    /// @param orderInfo OrderStatus, orderHash, and amount already filled of order.
    /// @param takerAddress Address of order taker.
    /// @param signature Proof that the orders was created by its maker.
    function _assertFillableOrder(
        LibOrder.Order memory order,
        LibOrder.OrderInfo memory orderInfo,
        address takerAddress,
        bytes memory signature
    )
        internal
    {
        if (orderInfo.orderType == LibOrder.OrderType.INVALID) {
            revert('EXCHANGE: type illegal');
        }

        if (orderInfo.orderType == LibOrder.OrderType.LIST) {
            address erc20TokenAddress = order.takerAssetData.readAddress(4);
            if (erc20TokenAddress == address(0) && msg.value != order.takerAssetAmount) {
                revert('EXCHANGE: wrong value sent');
            }
        }

        if (orderInfo.orderType == LibOrder.OrderType.SWAP) {
            if (msg.value != protocolFixedFee) {
                revert('EXCHANGE: wrong value sent');
            }
        }

        // An order can only be filled if its status is FILLABLE.
        if (orderInfo.orderStatus != LibOrder.OrderStatus.FILLABLE) {
            revert('EXCHANGE: status not fillable');
        }

        // Validate sender is allowed to fill this order
        if (order.senderAddress != address(0)) {
            if (order.senderAddress != msg.sender) {
                revert('EXCHANGE: invalid sender');
            }
        }

        // Validate taker is allowed to fill this order
        if (order.takerAddress != address(0)) {
            if (order.takerAddress != takerAddress) {
                revert('EXCHANGE: invalid taker');
            }
        }

        // Validate signature
        if (!_isValidOrderWithHashSignature(
                order,
                orderInfo.orderHash,
                signature
            )
        ) {
            revert('EXCHANGE: invalid signature');
        }
    }

    /// @dev Validates context for cancelOrder. Succeeds or throws.
    /// @param order to be cancelled.
    /// @param orderInfo OrderStatus, orderHash, and amount already filled of order.
    function _assertValidCancel(
        LibOrder.Order memory order,
        LibOrder.OrderInfo memory orderInfo
    )
        internal
        view
        returns (uint256 protocolFee)
    {
        // Validate sender is allowed to cancel this order
        if (order.senderAddress != address(0)) {
            if (order.senderAddress != msg.sender) {
                revert('EXCHANGE: invalid sender');
            }
        }

        // Validate transaction signed by maker
        address makerAddress = msg.sender;
        if (order.makerAddress != makerAddress) {
            revert('EXCHANGE: invalid maker');
        }
    }


    /// @dev Settles an order by transferring assets between counterparties.
    /// @param orderInfo The order info struct.
    /// @param order Order struct containing order specifications.
    /// @param takerAddress Address selling takerAsset and buying makerAsset.
    function _settleOrder(
        LibOrder.OrderInfo memory orderInfo,
        LibOrder.Order memory order,
        address takerAddress
    )
        internal
        returns (uint256 protocolFee)
    {
        address payerAddress = msg.sender;

        if (orderInfo.orderType == LibOrder.OrderType.LIST) {
            uint256 buyerPayment = order.takerAssetAmount;

            // pay protocol fees
            if (protocolFeeCollector != address(0) && protocolFeeMultiplier > 0) {
                protocolFee = buyerPayment.safeMul(protocolFeeMultiplier).safeDiv(100);
                buyerPayment = buyerPayment.safeSub(protocolFee);
                _dispatchTransferFrom(
                    order.takerAssetData,
                    payerAddress,
                    protocolFeeCollector,
                    protocolFee
                );
            }

            // pay royalties
            if (order.royaltiesAddress != address(0) && order.royaltiesAmount > 0 ) {
                buyerPayment = buyerPayment.safeSub(order.royaltiesAmount);
                _dispatchTransferFrom(
                    order.takerAssetData,
                    payerAddress,
                    order.royaltiesAddress,
                    order.royaltiesAmount
                );
            }

            // pay seller
            _dispatchTransferFrom(
                order.takerAssetData,
                payerAddress,
                order.makerAddress,
                buyerPayment
            );

            // Transfer buyer -> seller (nft / bundle)
            _dispatchTransferFrom(
                order.makerAssetData,
                order.makerAddress,
                takerAddress,
                order.makerAssetAmount
            );
        }

        if (orderInfo.orderType == LibOrder.OrderType.OFFER) {
            uint256 buyerPayment = order.makerAssetAmount;

            // pay protocol fees
            if (protocolFeeCollector != address(0) && protocolFeeMultiplier > 0) {
                protocolFee = buyerPayment.safeMul(protocolFeeMultiplier).safeDiv(100);
                buyerPayment = buyerPayment.safeSub(protocolFee);
                _dispatchTransferFrom(
                    order.makerAssetData,
                    order.makerAddress,
                    protocolFeeCollector,
                    protocolFee
                );
            }

            // pay royalties
            if (order.royaltiesAddress != address(0) && order.royaltiesAmount > 0 ) {
                buyerPayment = buyerPayment.safeSub(order.royaltiesAmount);
                _dispatchTransferFrom(
                    order.makerAssetData,
                    order.makerAddress,
                    order.royaltiesAddress,
                    order.royaltiesAmount
                );
            }

            // pay seller // erc20
            _dispatchTransferFrom(
                order.makerAssetData,
                order.makerAddress,
                msg.sender,
                buyerPayment
            );

            // Transfer buyer -> seller (nft / bundle)
            _dispatchTransferFrom(
                order.takerAssetData,
                msg.sender,
                order.makerAddress,
                order.takerAssetAmount
            );
        }

        if (orderInfo.orderType == LibOrder.OrderType.SWAP) {
            // pay protocol fees
            if (protocolFeeCollector != address(0) && protocolFixedFee > 0) {
                protocolFee = protocolFixedFee;
                payable(protocolFeeCollector).transfer(protocolFee);
            }

            // Transfer seller -> buyer (nft / bundle)
            _dispatchTransferFrom(
                order.makerAssetData,
                order.makerAddress,
                msg.sender,
                order.makerAssetAmount
            );

            // Transfer buyer -> seller (nft / bundle)
            _dispatchTransferFrom(
                order.takerAssetData,
                msg.sender,
                order.makerAddress,
                order.takerAssetAmount
            );
        }

        return protocolFee;
      
    }
}