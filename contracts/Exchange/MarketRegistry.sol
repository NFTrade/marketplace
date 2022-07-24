pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";

contract MarketRegistry is Ownable {
    struct Market {
        uint256 feeMultiplier;
        address feeCollector;
        bool isActive;
    }

    event MarketAdd(bytes32 identifier, uint256 feeMultiplier, address feeCollector);
    event MarketUpdateStatus(bytes32 identifier, bool status);
    event MarketSetFees(bytes32 identifier, uint256 feeMultiplier, address feeCollector);

    bool public distributeMarketFees = true;

    mapping(bytes32 => Market) markets;

    function marketDistribution(bool _distributeMarketFees)
        external
        onlyOwner
    {
        distributeMarketFees = _distributeMarketFees;
    }

    function addMarket(bytes32 identifier, uint256 feeMultiplier, address feeCollector) external onlyOwner {
        require(feeMultiplier >= 0 && feeMultiplier <= 100, "fee multiplier must be betwen 0 to 100");
        markets[identifier] = Market(feeMultiplier, feeCollector, true);
        emit MarketAdd(identifier, feeMultiplier, feeCollector);
    }

    function setMarketStatus(bytes32 identifier, bool isActive)
        external
        onlyOwner
    {
        markets[identifier].isActive = isActive;
        emit MarketUpdateStatus(identifier, isActive);
    }

    function setMarketFees(
        bytes32 identifier,
        uint256 feeMultiplier,
        address feeCollector
    ) external onlyOwner {
        require(feeMultiplier >= 0 && feeMultiplier <= 100, "fee multiplier must be betwen 0 to 100");
        markets[identifier].feeMultiplier = feeMultiplier;
        markets[identifier].feeCollector = feeCollector;
        emit MarketSetFees(identifier, feeMultiplier, feeCollector);
    }
}