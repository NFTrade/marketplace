pragma solidity ^0.8.4;

import './IWETH.sol';

contract Test {
    IWETH internal WETH;

    constructor (
        address _weth
    )
        public
    {
        WETH = IWETH(_weth);
    }

    function test()
        public
        payable
    {
        WETH.deposit{value: msg.value}();
    }

}
