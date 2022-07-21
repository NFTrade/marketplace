pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";

contract MarketRegistry is Ownable {
    struct Market {
        uint256 feeMultiplier;
        address feeCollector;
        bool isActive;
    }

    mapping(bytes32 => Market) markets;

    function addMarket(bytes32 identifier, uint256 feeMultiplier, address feeCollector) external onlyOwner {
        markets[identifier] = Market(feeMultiplier, feeCollector, true);
    }

    function setMarketStatus(bytes32 identifier, bool newStatus)
        external
        onlyOwner
    {
        markets[identifier].isActive = newStatus;
    }

    function setMarketFees(
        bytes32 identifier,
        uint256 feeMultiplier,
        address feeCollector
    ) external onlyOwner {
        markets[identifier].feeMultiplier = feeMultiplier;
        markets[identifier].feeCollector = feeCollector;
    }
}