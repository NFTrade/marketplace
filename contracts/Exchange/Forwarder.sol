pragma solidity ^0.8.4;

import "../Proxies/interfaces/IAssetData.sol";
import "../Utils/LibBytes.sol";
import "../Utils/LibSafeMath.sol";
import "./Libs/LibFillResults.sol";
import "./Libs/LibOrder.sol";
import "./MixinAssetProxyDispatcher.sol";
import "./interfaces/IExchangeCore.sol";

abstract contract IEtherToken
{
    function deposit()
        public
        payable
        virtual;
}



contract Forwarder is MixinAssetProxyDispatcher {

    IExchangeCore internal EXCHANGE;
    IEtherToken internal WETH;

    using LibOrder for LibOrder.Order;
    using LibBytes for bytes;
    using LibSafeMath for uint256;

    constructor (
        address _exchange,
        address _weth
    )
        public
    {
        EXCHANGE = IExchangeCore(_exchange);
        WETH = IEtherToken(_weth);
    }

    /// @dev Executes a single call of fillOrder according to the makerAssetBuyAmount and
    ///      the amount already bought.
    /// @param order A single order specification.
    /// @param signature Signature for the given order.
    /// @param remainingMakerAssetFillAmount Remaining amount of maker asset to buy.
    /// @return wethSpentAmount Amount of WETH spent on the given order.
    /// @return makerAssetAcquiredAmount Amount of maker asset acquired from the given order.
    function _marketBuySingleOrder(
        LibOrder.Order memory order,
        bytes memory signature,
        uint256 remainingMakerAssetFillAmount
    )
        internal
        returns (
            uint256 wethSpentAmount,
            uint256 makerAssetAcquiredAmount
        )
    {
        // No taker fee or WETH fee
        if (
            order.takerFee == 0 ||
            _areUnderlyingAssetsEqual(order.takerFeeAssetData, order.takerAssetData)
        ) {
            // Calculate the remaining amount of takerAsset to sell
            uint256 remainingTakerAssetFillAmount = LibMath.getPartialAmountCeil(
                order.takerAssetAmount,
                order.makerAssetAmount,
                remainingMakerAssetFillAmount
            );

            // Attempt to sell the remaining amount of takerAsset
            LibFillResults.FillResults memory singleFillResults = _fillOrder(
                order,
                remainingTakerAssetFillAmount,
                signature
            );

            // WETH is also spent on the protocol and taker fees, so we add it here.
            wethSpentAmount = singleFillResults.takerAssetFilledAmount
                .safeAdd(singleFillResults.takerFeePaid)
                .safeAdd(singleFillResults.takerProtocolFeePaid);

            makerAssetAcquiredAmount = singleFillResults.makerAssetFilledAmount;

        // Percentage fee
        } else if (_areUnderlyingAssetsEqual(order.takerFeeAssetData, order.makerAssetData)) {
            // Calculate the remaining amount of takerAsset to sell
            uint256 remainingTakerAssetFillAmount = LibMath.getPartialAmountCeil(
                order.takerAssetAmount,
                order.makerAssetAmount.safeSub(order.takerFee),
                remainingMakerAssetFillAmount
            );

            // Attempt to sell the remaining amount of takerAsset
            LibFillResults.FillResults memory singleFillResults = _fillOrder(
                order,
                remainingTakerAssetFillAmount,
                signature
            );

            wethSpentAmount = singleFillResults.takerAssetFilledAmount
                .safeAdd(singleFillResults.takerProtocolFeePaid);

            // Subtract fee from makerAssetFilledAmount for the net amount acquired.
            makerAssetAcquiredAmount = singleFillResults.makerAssetFilledAmount
                .safeSub(singleFillResults.takerFeePaid);

        // Unsupported fee
        } else {
            revert('FORWARDER: Unsupported fee');
        }

        return (wethSpentAmount, makerAssetAcquiredAmount);
    }

    event Test(uint256 test, uint256 test2);

    /// @dev Synchronously executes multiple fill orders in a single transaction until total amount is acquired.
    ///      Note that the Forwarder may fill more than the makerAssetBuyAmount so that, after percentage fees
    ///      are paid, the net amount acquired after fees is equal to makerAssetBuyAmount (modulo rounding).
    ///      The asset being sold by taker must always be WETH.
    /// @param orders Array of order specifications.
    /// @param makerAssetBuyAmount Desired amount of makerAsset to fill.
    /// @param signatures Proofs that orders have been signed by makers.
    /// @return totalWethSpentAmount Total amount of WETH spent on the given orders.
    /// @return totalMakerAssetAcquiredAmount Total amount of maker asset acquired from the given orders.
    function _marketBuyFillOrKill(
        LibOrder.Order[] memory orders,
        uint256 makerAssetBuyAmount,
        bytes[] memory signatures
    )
        internal
        returns (
            uint256 totalWethSpentAmount,
            uint256 totalMakerAssetAcquiredAmount
        )
    {
        uint256 ordersLength = orders.length;
        for (uint256 i = 0; i != ordersLength; i++) {
            // Preemptively skip to avoid division by zero in _marketBuySingleOrder
            if (orders[i].makerAssetAmount == 0 || orders[i].takerAssetAmount == 0) {
                continue;
            }

            uint256 remainingMakerAssetFillAmount = makerAssetBuyAmount
                .safeSub(totalMakerAssetAcquiredAmount);

            (
                uint256 wethSpentAmount,
                uint256 makerAssetAcquiredAmount
            ) = _marketBuySingleOrder(
                orders[i],
                signatures[i],
                remainingMakerAssetFillAmount
            );

            emit Test(remainingMakerAssetFillAmount, makerAssetAcquiredAmount);

            _dispatchTransferFrom(
                '',
                orders[i].makerAssetData,
                address(this),
                msg.sender,
                makerAssetAcquiredAmount
            );

            totalWethSpentAmount = totalWethSpentAmount
                .safeAdd(wethSpentAmount);
            totalMakerAssetAcquiredAmount = totalMakerAssetAcquiredAmount
                .safeAdd(makerAssetAcquiredAmount);

                emit Test(0, totalMakerAssetAcquiredAmount);

            // Stop execution if the entire amount of makerAsset has been bought
            if (totalMakerAssetAcquiredAmount >= makerAssetBuyAmount) {
                break;
            }
        }

        if (totalMakerAssetAcquiredAmount < makerAssetBuyAmount) {
            emit Test(totalMakerAssetAcquiredAmount, ordersLength);
            //revert("FORWARDER: Complete buy fail");
        }
    }

    /// @dev Fills the input ExchangeV3 order.
    ///      Returns false if the transaction would otherwise revert.
    /// @param order Order struct containing order specifications.
    /// @param takerAssetFillAmount Desired amount of takerAsset to sell.
    /// @param signature Proof that order has been created by maker.
    /// @return fillResults filled and fees paid by maker and taker.
    function _fillOrder(
        LibOrder.Order memory order,
        uint256 takerAssetFillAmount,
        bytes memory signature
    )
        internal
        returns (LibFillResults.FillResults memory fillResults)
    {
        // ABI encode calldata for `fillOrder`
        bytes memory fillOrderCalldata = abi.encodeWithSelector(
            IExchangeCore(address(0)).fillOrder.selector,
            order,
            takerAssetFillAmount,
            signature
        );

        address exchange = address(EXCHANGE);
        (bool didSucceed, bytes memory returnData) = exchange.call(fillOrderCalldata);
        if (didSucceed) {
            assert(returnData.length == 160);
            fillResults = abi.decode(returnData, (LibFillResults.FillResults));
        }

        // fillResults values will be 0 by default if call was unsuccessful
        return fillResults;
    }

    function marketBuyOrdersWithEth(
        LibOrder.Order[] memory orders,
        uint256 makerAssetBuyAmount,
        bytes[] memory signatures
    )
        public
        payable
        returns (
            uint256 wethSpentAmount,
            uint256 makerAssetAcquiredAmount
        )
    {
        WETH.deposit{value: msg.value};

        // Attempts to fill the desired amount of makerAsset and trasnfer purchased assets to msg.sender.
        (
            wethSpentAmount,
            makerAssetAcquiredAmount
        ) = _marketBuyFillOrKill(
            orders,
            makerAssetBuyAmount,
            signatures
        );
    }

    /// @dev Checks whether one asset is effectively equal to another asset.
    ///      This is the case if they have the same ERC20Proxy/ERC20BridgeProxy asset data, or if
    ///      one is the ERC20Bridge equivalent of the other.
    /// @param assetData1 Byte array encoded for the takerFee asset proxy.
    /// @param assetData2 Byte array encoded for the maker asset proxy.
    /// @return areEqual Whether or not the underlying assets are equal.
    function _areUnderlyingAssetsEqual(
        bytes memory assetData1,
        bytes memory assetData2
    )
        internal
        pure
        returns (bool)
    {
        bytes4 assetProxyId1 = assetData1.readBytes4(0);
        bytes4 assetProxyId2 = assetData2.readBytes4(0);
        bytes4 erc20ProxyId = IAssetData(address(0)).ERC20Token.selector;

        if (
            (assetProxyId1 == erc20ProxyId) &&
            (assetProxyId2 == erc20ProxyId)
        ) {
            // Compare the underlying token addresses.
            address token1 = assetData1.readAddress(16);
            address token2 = assetData2.readAddress(16);
            return (token1 == token2);
        } else {
            return assetData1.equals(assetData2);
        }
    }

}
