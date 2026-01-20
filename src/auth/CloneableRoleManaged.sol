// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {RoleManager} from "./RoleManager.sol";
import {LibRoleManaged} from "./LibRoleManaged.sol";

/**
 * @title CloneableRoleManaged
 * @notice Clone-compatible base contract for role-managed contracts in the Fountfi protocol
 * @dev Provides role checking functionality for contracts that will be deployed as clones
 */
abstract contract CloneableRoleManaged is LibRoleManaged {
    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidRoleManager();

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    event RoleManagerInitialized(address indexed roleManager);

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the role manager (for use with clones)
     * @param _roleManager Address of the role manager contract
     */
    function _initializeRoleManager(address _roleManager) internal {
        if (_roleManager == address(0)) revert InvalidRoleManager();
        roleManager = RoleManager(_roleManager);
        emit RoleManagerInitialized(_roleManager);
    }
}
