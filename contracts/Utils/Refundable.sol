pragma solidity ^0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


contract Refundable is
    ReentrancyGuard
{

    // This bool is used by the refund modifier to allow for lazily evaluated refunds.
    bool internal _shouldNotRefund;

    modifier refundFinalBalance {
        _;
        _refundNonZeroBalanceIfEnabled();
    }

    modifier refundFinalBalanceNoReentry {
        _;
        _refundNonZeroBalanceIfEnabled();
    }

    modifier disableRefundUntilEnd {
        if (_areRefundsDisabled()) {
            _;
        } else {
            _disableRefund();
            _;
            _enableAndRefundNonZeroBalance();
        }
    }

    function _refundNonZeroBalanceIfEnabled()
        internal
    {
        if (!_areRefundsDisabled()) {
            _refundNonZeroBalance();
        }
    }

    function _refundNonZeroBalance()
        internal
    {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            payable(msg.sender).transfer(balance);
        }
    }

    function _disableRefund()
        internal
    {
        _shouldNotRefund = true;
    }

    function _enableAndRefundNonZeroBalance()
        internal
    {
        _shouldNotRefund = false;
        _refundNonZeroBalance();
    }

    function _areRefundsDisabled()
        internal
        view
        returns (bool)
    {
        return _shouldNotRefund;
    }
}
