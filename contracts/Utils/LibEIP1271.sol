pragma solidity ^0.8.4;


contract LibEIP1271 {

    /// @dev Magic bytes returned by EIP1271 wallets on success.
    /// @return 0 Magic bytes.
    bytes4 constant public EIP1271_MAGIC_VALUE = 0x20c13b0b;
}
