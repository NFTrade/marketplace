pragma solidity ^0.8.4;

import "../Utils/LibBytes.sol";
import "../Utils/LibEIP1271.sol";
import "./Libs/LibOrder.sol";
import "./Libs/LibEIP712ExchangeDomain.sol";
import "./interfaces/ISignatureValidator.sol";

abstract contract SignatureValidator is
    LibEIP712ExchangeDomain,
    LibEIP1271,
    ISignatureValidator
{
    using LibBytes for bytes;
    using LibOrder for LibOrder.Order;

    // event logSignature(SignatureType log);

    /// @dev Verifies that a hash has been signed by the given signer.
    /// @param hash Any 32-byte hash.
    /// @param signerAddress Address that should have signed the given hash.
    /// @param signature Proof that the hash has been signed by signer.
    /// @return isValid `true` if the signature is valid for the given hash and signer.
    function isValidHashSignature(
        bytes32 hash,
        address signerAddress,
        bytes memory signature
    ) public pure override returns (bool isValid) {
        //view
        SignatureType signatureType = _readValidSignatureType(
            signerAddress,
            signature
        );

        // emit logSignature(signatureType);
        // Only hash-compatible signature types can be handled by this
        // function.
        if (signatureType == SignatureType.EIP1271Wallet) {
            revert("SIGNATURE: inappropriate type");
        }
        isValid = _validateHashSignatureTypes(
            signatureType,
            hash,
            signerAddress,
            signature
        );
        return isValid;
    }

    /// @dev Verifies that an order, with provided order hash, has been signed
    ///      by the given signer.
    /// @param order The order.
    /// @param orderHash The hash of the order.
    /// @param signature Proof that the hash has been signed by signer.
    /// @return isValid True if the signature is valid for the given order and signer.
    function _isValidOrderWithHashSignature(
        LibOrder.Order memory order,
        bytes32 orderHash,
        bytes memory signature
    ) internal pure returns (bool isValid) {
        address signerAddress = order.makerAddress;
        SignatureType signatureType = _readValidSignatureType(
            signerAddress,
            signature
        );

        isValid = _validateHashSignatureTypes(
            signatureType,
            orderHash,
            signerAddress,
            signature
        );
        // }
        return isValid;
    }

    /// Validates a hash-only signature type
    /// (anything but `EIP1271Wallet`).
    function _validateHashSignatureTypes(
        SignatureType signatureType,
        bytes32 hash,
        address signerAddress,
        bytes memory signature
    ) private pure returns (bool isValid) {
        // Always invalid signature.
        // Like Illegal, this is always implicitly available and therefore
        // offered explicitly. It can be implicitly created by providing
        // a correctly formatted but incorrect signature.
        if (signatureType == SignatureType.Invalid) {
            if (signature.length != 1) {
                revert("SIGNATURE: invalid length");
            }
            isValid = false;

            // Signature using EIP712
        } else if (signatureType == SignatureType.EIP712) {
            if (signature.length != 66) {
                revert("SIGNATURE: invalid length");
            }
            uint8 v = uint8(signature[0]);
            bytes32 r = signature.readBytes32(1);
            bytes32 s = signature.readBytes32(33);
            address recovered = ecrecover(hash, v, r, s);
            isValid = signerAddress == recovered;
        }

        return isValid;
    }

    /// @dev Reads the `SignatureType` from a signature with minimal validation.
    function _readSignatureType(bytes memory signature)
        private
        pure
        returns (SignatureType)
    {
        if (signature.length == 0) {
            revert("SIGNATURE: invalid length");
        }
        return SignatureType(uint8(signature[signature.length - 1]));
    }

    /// @dev Reads the `SignatureType` from the end of a signature and validates it.
    function _readValidSignatureType(
        address signerAddress,
        bytes memory signature
    ) private pure returns (SignatureType signatureType) {
        // Read the signatureType from the signature
        signatureType = _readSignatureType(signature);

        // Disallow address zero because ecrecover() returns zero on failure.
        if (signerAddress == address(0)) {
            revert("SIGNATURE: signerAddress cannot be null");
        }

        // Ensure signature is supported
        if (uint8(signatureType) >= uint8(SignatureType.NSignatureTypes)) {
            revert("SIGNATURE: signature not supported");
        }

        // Always illegal signature.
        // This is always an implicit option since a signer can create a
        // signature array with invalid type or length. We may as well make
        // it an explicit option. This aids testing and analysis. It is
        // also the initialization value for the enum type.
        if (signatureType == SignatureType.Illegal) {
            revert("SIGNATURE: illegal signature");
        }

        return signatureType;
    }
}
