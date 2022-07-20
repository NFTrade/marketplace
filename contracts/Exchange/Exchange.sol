pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Libs/LibEIP712ExchangeDomain.sol";
import "./MixinExchangeCore.sol";

// solhint-disable no-empty-blocks
// MixinAssetProxyDispatcher, MixinExchangeCore, MixinSignatureValidator,
// and MixinTransactions are all inherited via the other Mixins that are
// used.
/// @dev The 0x Exchange contract.
contract Exchange is
    Ownable,
    LibEIP712ExchangeDomain,
    MixinExchangeCore
{
    /// @dev Mixins are instantiated in the order they are inherited
    /// @param chainId Chain ID of the network this contract is deployed on.
    constructor (uint256 chainId) LibEIP712ExchangeDomain(chainId, address(0)) {}

    function returnAllETHToOwner() public payable onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function returnERC20ToOwner(address ERC20Token) public payable onlyOwner {
        IERC20 CustomToken = IERC20(ERC20Token);
        CustomToken.transferFrom(address(this), msg.sender, CustomToken.balanceOf(address(this)));
    }

    receive() external payable {}
}
