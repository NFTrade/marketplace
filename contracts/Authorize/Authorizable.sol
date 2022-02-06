pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";


contract Authorizable is
    Ownable,
    AccessControl
{
    bytes32 public constant AUTHORIZED_ROLE = keccak256("AUTHORIZED_ROLE");
    /// @dev Only authorized addresses can invoke functions with this modifier.
    modifier onlyAuthorized {
        _checkRole(AUTHORIZED_ROLE, _msgSender());
        _;
    }

    /// @dev Authorizes an address.
    /// @param target Address to authorize.
    function addAuthorizedAddress(address target)
        external
        onlyOwner
    {
        _setupRole(AUTHORIZED_ROLE, target);
    }

    /// @dev Removes authorizion of an address.
    /// @param target Address to remove authorization from.
    function removeAuthorizedAddress(address target)
        external
        onlyOwner
    {
        revokeRole(AUTHORIZED_ROLE, target);
    }
}
