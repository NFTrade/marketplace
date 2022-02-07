pragma solidity ^0.8.4;

import "../../Utils/LibSafeMath.sol";
import "../../Utils/LibBytes.sol";
import "../../Proxies/interfaces/IAssetData.sol";
import "./LibMath.sol";
import "./LibOrder.sol";


library LibFillResults {

    using LibSafeMath for uint256;
    using LibBytes for bytes;

    struct FillResults {
        uint256 makerAssetFilledAmount;  // Total amount of makerAsset(s) filled.
        uint256 takerAssetFilledAmount;  // Total amount of takerAsset(s) filled.
        uint256 makerFeePaid;            // Total amount of fees paid by maker(s) to feeRecipient(s).
        uint256 takerFeePaid;            // Total amount of fees paid by taker to feeRecipients(s).
        uint256 takerProtocolFeePaid;    // Total amount of fees paid by taker to the fee collector.
        uint256 makerProtocolFeePaid;    // Total amount of fees paid by maker to the fee collector.
    }

    /// @dev Calculates amounts filled and fees paid by maker and taker.
    /// @param order to be filled.
    /// @param takerAssetFilledAmount Amount of takerAsset that will be filled.
    /// @param protocolFeeMultiplier The current protocol fee of the exchange contract.
    ///        to be pure rather than view.
    /// @return fillResults Amounts filled and fees paid by maker and taker.
    function calculateFillResults(
        LibOrder.Order memory order,
        uint256 takerAssetFilledAmount,
        uint256 protocolFeeMultiplier
    )
        internal
        pure
        returns (FillResults memory fillResults)
    {

        // Compute proportional transfer amounts
        fillResults.makerAssetFilledAmount = LibMath.safeGetPartialAmountFloor(
            takerAssetFilledAmount,
            order.takerAssetAmount,
            order.makerAssetAmount
        );
        fillResults.makerFeePaid = LibMath.safeGetPartialAmountFloor(
            takerAssetFilledAmount,
            order.takerAssetAmount,
            order.makerFee
        );
        fillResults.takerFeePaid = LibMath.safeGetPartialAmountFloor(
            takerAssetFilledAmount,
            order.takerAssetAmount,
            order.takerFee
        );

        fillResults.takerAssetFilledAmount = takerAssetFilledAmount;

        // calculate fees
        // Compute the protocol fee that should be paid for a single fill.

        bytes4 takerAssetProxyId = order.takerAssetData.readBytes4(0);
        bytes4 makerAssetProxyId = order.makerAssetData.readBytes4(0);

        bytes4 erc20ProxyId = IAssetData(address(0)).ERC20Token.selector;

        if (takerAssetProxyId == erc20ProxyId) {
            fillResults.takerProtocolFeePaid = fillResults.takerAssetFilledAmount.safeMul(protocolFeeMultiplier).safeDiv(100);
            fillResults.takerAssetFilledAmount = fillResults.takerAssetFilledAmount.safeSub(fillResults.takerProtocolFeePaid);
        }

        if (makerAssetProxyId == erc20ProxyId) {
            fillResults.makerProtocolFeePaid = fillResults.makerAssetFilledAmount.safeMul(protocolFeeMultiplier).safeDiv(100);
            fillResults.makerAssetFilledAmount = fillResults.makerAssetFilledAmount.safeSub(fillResults.makerProtocolFeePaid);
        }

        return fillResults;
    }
}
