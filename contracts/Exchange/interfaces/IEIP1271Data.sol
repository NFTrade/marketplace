pragma solidity ^0.8.4;

import "../Libs/LibOrder.sol";
import "../Libs/LibTransaction.sol";


// solhint-disable
abstract contract IEIP1271Data {

    /// @dev This function's selector is used when ABI encoding the order
    ///      and hash into a byte array before calling `isValidSignature`.
    ///      This function serves no other purpose.
    function OrderWithHash(
        LibOrder.Order calldata order,
        bytes32 orderHash
    )
        virtual
        external
        pure;
    
    /// @dev This function's selector is used when ABI encoding the transaction
    ///      and hash into a byte array before calling `isValidSignature`.
    ///      This function serves no other purpose.
    function TransactionWithHash(
        LibTransaction.Transaction calldata transaction,
        bytes32 transactionHash
    )
        virtual
        external
        pure;
}
