pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Libs/LibEIP712ExchangeDomain.sol";
import "./ExchangeCore.sol";

contract Exchange is
    Ownable,
    LibEIP712ExchangeDomain,
    ExchangeCore
{
    /// @dev Mixins are instantiated in the order they are inherited
    /// @param chainId Chain ID of the network this contract is deployed on.
    constructor (uint256 chainId) LibEIP712ExchangeDomain(chainId) {}

    function returnAllETHToOwner() public payable onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function returnERC20ToOwner(address ERC20Token) public payable onlyOwner {
        IERC20 CustomToken = IERC20(ERC20Token);
        CustomToken.transferFrom(address(this), msg.sender, CustomToken.balanceOf(address(this)));
    }

    receive() external payable {}
}
