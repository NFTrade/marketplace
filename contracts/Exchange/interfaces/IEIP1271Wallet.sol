pragma solidity ^0.8.4;

import "../../Utils/LibEIP1271.sol";


abstract contract IEIP1271Wallet is
    LibEIP1271
{
    /// @dev Verifies that a signature is valid.
    /// @param data Arbitrary signed data.
    /// @param signature Proof that data has been signed.
    /// @return magicValue bytes4(0x20c13b0b) if the signature check succeeds.
    function isValidSignature(
        bytes calldata data,
        bytes calldata signature
    )
        virtual
        external
        view
        returns (bytes4 magicValue);
}
