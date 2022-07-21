pragma solidity ^0.8.4;

import "../../Utils/LibEIP712.sol";


contract LibEIP712ExchangeDomain {

    // EIP712 Exchange Domain Name value
    string constant internal _EIP712_EXCHANGE_DOMAIN_NAME = "Nifty Exchange";

    // EIP712 Exchange Domain Version value
    string constant internal _EIP712_EXCHANGE_DOMAIN_VERSION = "2.0";

    // solhint-disable var-name-mixedcase
    /// @dev Hash of the EIP712 Domain Separator data
    /// @return 0 Domain hash.
    bytes32 public EIP712_EXCHANGE_DOMAIN_HASH;
    // solhint-enable var-name-mixedcase

    /// @param chainId Chain ID of the network this contract is deployed on.
    constructor (
        uint256 chainId
    )
    {
        EIP712_EXCHANGE_DOMAIN_HASH = LibEIP712.hashEIP712Domain(
            _EIP712_EXCHANGE_DOMAIN_NAME,
            _EIP712_EXCHANGE_DOMAIN_VERSION,
            chainId,
            address(this)
        );
    }
}
