pragma solidity ^0.8.4;

import "../Utils/LibBytes.sol";
import "../Utils/LibSafeMath.sol";
import "./interfaces/IExchangeCore.sol";
import "./AssetProxyDispatcher.sol";
import "./ProtocolFees.sol";
import "./SignatureValidator.sol";
import "./MarketRegistry.sol";
import "../Proxies/interfaces/IAssetData.sol";

abstract contract ExchangeCore is
    IExchangeCore,
    AssetProxyDispatcher,
    ProtocolFees,
    SignatureValidator,
    MarketRegistry
{
    using LibSafeMath for uint256;
    using LibBytes for bytes;

    /// @dev Mapping of orderHash => amount of takerAsset already bought by maker
    /// @return boolean the order has been filled
    mapping (bytes32 => bool) public filled;

    /// @dev Mapping of orderHash => cancelled
    /// @return 0 Whether the order was cancelled.
    mapping (bytes32 => bool) public cancelled;

    /// @dev Mapping of makerAddress => lowest salt an order can have in order to be fillable
    ///      Orders with a salt less than their epoch are considered cancelled
    mapping (address => uint256) public orderEpoch;

    /// @dev Fills the input order.
    /// @param order Order struct containing order specifications.
    /// @param signature Proof that order has been created by maker.
    /// @param takerAddress orider fill for the taker.
    /// @return fulfilled boolean
    function _fillOrder(
        LibOrder.Order memory order,
        bytes memory signature,
        address takerAddress,
        bytes32 marketIdentifier
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
            takerAddress,
            marketIdentifier
        );

        _notifyOrderFulfilled(order, orderHash, takerAddress, protocolFee);

        return filled[orderHash];
    }

    function _notifyOrderFulfilled(
        LibOrder.Order memory order,
        bytes32 orderHash,
        address takerAddress,
        uint256 protocolFee
    ) internal {
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
        _assertValidCancel(order);

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
    function _assertValidCancel(
        LibOrder.Order memory order
    )
        internal
        view
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
        address takerAddress,
        bytes32 marketIdentifier
    )
        internal
        returns (uint256 protocolFee)
    {
        address payerAddress = msg.sender;
        Market memory market = markets[marketIdentifier];

        if (orderInfo.orderType == LibOrder.OrderType.LIST) {
            uint256 buyerPayment = order.takerAssetAmount;

            // pay protocol fees
            if (protocolFeeCollector != address(0) && protocolFeeMultiplier > 0) {
                protocolFee = buyerPayment.safeMul(protocolFeeMultiplier).safeDiv(100);
                buyerPayment = buyerPayment.safeSub(protocolFee);
                if (market.isActive && market.feeCollector != address(0) && market.feeMultiplier > 0) {
                    uint256 marketplaceFee = protocolFee.safeMul(market.feeMultiplier).safeDiv(100);
                    protocolFee = protocolFee.safeSub(marketplaceFee);
                    _dispatchTransferFrom(
                        order.takerAssetData,
                        payerAddress,
                        market.feeCollector,
                        marketplaceFee
                    );
                }
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