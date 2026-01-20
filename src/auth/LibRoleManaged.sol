// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {RoleManager} from "./RoleManager.sol";

/**
 * @title LibRoleManaged
 * @notice Logical library for role-managed contracts. Can be inherited by
 *          both deployable and cloneable versions of RoleManaged.
 */
abstract contract LibRoleManaged {
    /*//////////////////////////////////////////////////////////////
                              ERRORS
    //////////////////////////////////////////////////////////////*/

    error UnauthorizedRole(address caller, uint256 roleRequired);

    /*//////////////////////////////////////////////////////////////
                              STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice The role manager contract
    RoleManager public roleManager;

    /*//////////////////////////////////////////////////////////////
                        ROLE MANAGED LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the registry contract
     * @return The address of the registry contract
     */
    function registry() public view returns (address) {
        return roleManager.registry();
    }

    /**
     * @notice Modifier to restrict access to addresses with a specific role
     * @param role The role required to access the function
     */
    modifier onlyRoles(uint256 role) {
        if (!roleManager.hasAnyRole(msg.sender, role)) {
            revert UnauthorizedRole(msg.sender, role);
        }

        _;
    }
}
