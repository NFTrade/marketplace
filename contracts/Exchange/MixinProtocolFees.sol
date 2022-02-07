pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../Utils/LibRichErrors.sol";
import "./Libs/LibExchangeRichErrors.sol";
import "./interfaces/IProtocolFees.sol";


contract MixinProtocolFees is
    IProtocolFees,
    Ownable
{
    /// @dev The protocol fee multiplier -- the owner can update this field.
    /// @return 0 Gas multplier.
    uint256 public override protocolFeeMultiplier;

    /// @dev The address of the registered protocolFeeCollector contract -- the owner can update this field.
    /// @return 0 Contract to forward protocol fees to.
    address public override protocolFeeCollector;

    /// @dev Allows the owner to update the protocol fee multiplier.
    /// @param updatedProtocolFeeMultiplier The updated protocol fee multiplier.
    function setProtocolFeeMultiplier(uint256 updatedProtocolFeeMultiplier)
        override
        external
        onlyOwner
    {
        emit ProtocolFeeMultiplier(protocolFeeMultiplier, updatedProtocolFeeMultiplier);
        protocolFeeMultiplier = updatedProtocolFeeMultiplier;
    }

    /// @dev Allows the owner to update the protocolFeeCollector address.
    /// @param updatedProtocolFeeCollector The updated protocolFeeCollector contract address.
    function setProtocolFeeCollectorAddress(address updatedProtocolFeeCollector)
        override
        external
        onlyOwner
    {
        _setProtocolFeeCollectorAddress(updatedProtocolFeeCollector);
    }

    /// @dev Sets the protocolFeeCollector contract address to 0.
    ///      Only callable by owner.
    function detachProtocolFeeCollector()
        external
        onlyOwner
    {
        _setProtocolFeeCollectorAddress(address(0));
    }

    /// @dev Sets the protocolFeeCollector address and emits an event.
    /// @param updatedProtocolFeeCollector The updated protocolFeeCollector contract address.
    function _setProtocolFeeCollectorAddress(address updatedProtocolFeeCollector)
        internal
    {
        emit ProtocolFeeCollectorAddress(protocolFeeCollector, updatedProtocolFeeCollector);
        protocolFeeCollector = updatedProtocolFeeCollector;
    }
}