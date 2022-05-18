pragma solidity ^0.8.4;

/* import "../Proxies/interfaces/IAssetData.sol";
import "../Utils/LibBytes.sol";
import "../Utils/LibSafeMath.sol";
 */import "./Libs/LibFillResults.sol";
import "./Libs/LibOrder.sol";
/* import "./MixinAssetProxyDispatcher.sol";
import "./interfaces/IExchangeCore.sol";
import "./interfaces/IAssetProxyDispatcher.sol"; */

interface IEtherToken
{
    function deposit()
        external
        payable;

    function approve(address guy, uint wad)
        external
        returns (bool);
}



contract Forwarder {

    // uint256 constant internal MAX_UINT256 = 2**256 - 1;

    // IExchangeCore internal EXCHANGE;
    IEtherToken internal WETH;

    using LibOrder for LibOrder.Order;
    /* using LibBytes for bytes;
    using LibSafeMath for uint256; */

    event Test(uint256 test);

    constructor (
        address _exchange,
        address _weth
    )
        public
    {
        // EXCHANGE = IExchangeCore(_exchange);
        WETH = IEtherToken(_weth);

        /* address proxyAddress = IAssetProxyDispatcher(_exchange).getAssetProxy(IAssetData(address(0)).ERC20Token.selector);

        WETH.approve(proxyAddress, MAX_UINT256); */
    }

    function fillOrder(
        LibOrder.Order memory order,
        uint256 takerAssetAmount,
        bytes memory signature
    )
        public
        payable
    {
        // WETH.deposit{value: msg.value}();

        // return EXCHANGE.fillOrder(order, takerAssetAmount, signature);
    }

}
