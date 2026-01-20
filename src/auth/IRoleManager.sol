// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

/**
 * @title IRoleManager
 * @notice Interface for the RoleManager contract
 */
interface IRoleManager {
    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted for 0 role in arguments
    error InvalidRole();

    /// @notice Emitted for 0 address in arguments
    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a role is granted to a user
     * @param user The address of the user
     * @param role The role that was granted
     * @param sender The address that granted the role
     */
    event RoleGranted(address indexed user, uint256 indexed role, address indexed sender);

    /**
     * @notice Emitted when a role is revoked from a user
     * @param user The address of the user
     * @param role The role that was revoked
     * @param sender The address that revoked the role
     */
    event RoleRevoked(address indexed user, uint256 indexed role, address indexed sender);

    /**
     * @notice Emitted when the admin role for a target role is updated.
     * @param targetRole The role whose admin is being changed.
     * @param adminRole The new role required to manage the targetRole (0 means revert to owner/PROTOCOL_ADMIN).
     * @param sender The address that performed the change.
     */
    event RoleAdminSet(uint256 indexed targetRole, uint256 indexed adminRole, address indexed sender);

    /*//////////////////////////////////////////////////////////////
                            FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Grants a role to a user
    /// @param user The address of the user to grant the role to
    /// @param role The role to grant
    function grantRole(address user, uint256 role) external;

    /// @notice Revokes a role from a user
    /// @param user The address of the user to revoke the role from
    /// @param role The role to revoke
    function revokeRole(address user, uint256 role) external;

    /// @notice Sets the specific role required to manage a target role.
    /// @dev Requires the caller to have the PROTOCOL_ADMIN role or be the owner.
    /// @param targetRole The role whose admin role is to be set. Cannot be PROTOCOL_ADMIN.
    /// @param adminRole The role that will be required to manage the targetRole. Set to 0 to require owner/PROTOCOL_ADMIN.
    function setRoleAdmin(uint256 targetRole, uint256 adminRole) external;
}
