pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Utils/LibBytes.sol";
import "../Authorize/Authorizable.sol";
import "./interfaces/IAssetProxy.sol";

contract ERC20Proxy is
    Authorizable,
    IAssetProxy
{
    using LibBytes for bytes;
    // Id of this proxy.
    bytes4 constant internal PROXY_ID = bytes4(keccak256("ERC20Token(address)"));

    function transferFrom(
        bytes calldata assetData,
        address from,
        address to,
        uint256 amount
    )
        override
        external
        onlyAuthorized
    {
        // Decode params from `assetData`
        // solhint-disable indent
        (
            address erc20TokenAddress
        ) = abi.decode( 
            assetData.sliceDestructive(4, assetData.length),
            (address)
        );
        // solhint-enable indent

        // Execute `safeBatchTransferFrom` call
        // Either succeeds or throws
        IERC20(erc20TokenAddress).transferFrom(
            from,
            to,
            amount
        );
    }

    /// @dev Gets the proxy id associated with the proxy address.
    /// @return Proxy id.
    function getProxyId()
        override
        external
        pure
        returns (bytes4)
    {
        return PROXY_ID;
    }
}
