// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {RoleManager} from "./RoleManager.sol";
import {LibRoleManaged} from "./LibRoleManaged.sol";

/**
 * @title RoleManaged
 * @notice Base contract for role-managed contracts in the Fountfi protocol
 * @dev Provides role checking functionality for contracts
 */
abstract contract RoleManaged is LibRoleManaged {
    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidRoleManager();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructor
     * @param _roleManager Address of the role manager contract
     */
    constructor(address _roleManager) {
        if (_roleManager == address(0)) revert InvalidRoleManager();

        roleManager = RoleManager(_roleManager);
    }
}
