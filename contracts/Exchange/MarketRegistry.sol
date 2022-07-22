pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";

contract MarketRegistry is Ownable {
    struct Market {
        uint256 feeMultiplier;
        address feeCollector;
        bool isActive;
    }

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