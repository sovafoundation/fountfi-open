// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {IRoleManager} from "./IRoleManager.sol";

/**
 * @title RoleManager
 * @notice Central role management contract for the Fountfi protocol
 * @dev Uses hierarchical bitmasks for core roles. Owner/PROTOCOL_ADMIN have override.
 */
contract RoleManager is OwnableRoles, IRoleManager {
    /*//////////////////////////////////////////////////////////////
                            ROLE DEFINITIONS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant PROTOCOL_ADMIN = 1 << 1; // Bit 1 = Protocol Admin Authority
    uint256 public constant STRATEGY_ADMIN = 1 << 2; // Bit 2 = Strategy Admin Authority
    uint256 public constant RULES_ADMIN = 1 << 3; // Bit 3 = Rules Admin Authority

    uint256 public constant STRATEGY_OPERATOR = 1 << 4; // Bit 4 = Strategy Operator Authority
    uint256 public constant KYC_OPERATOR = 1 << 5; // Bit 5 = KYC Operator Authority

    /*//////////////////////////////////////////////////////////////
                               STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping from a target role to the specific (admin) role required to manage it.
    /// @dev If a role maps to 0, only owner or PROTOCOL_ADMIN can manage it.
    mapping(uint256 => uint256) public roleAdminRole;

    /// @notice The address of the registry contract, used as global reference
    address public registry;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructor that sets up the initial roles
     * @dev Initializes the owner and grants all roles to the deployer
     */
    constructor() {
        _initializeOwner(msg.sender);

        // Grant all roles to deployer
        uint256 rolesAll = PROTOCOL_ADMIN | STRATEGY_ADMIN | RULES_ADMIN;
        _grantRoles(msg.sender, rolesAll);

        // Emit event for easier off-chain tracking
        emit RoleGranted(msg.sender, rolesAll, address(0));

        // Set initial management hierarchy
        _setInitialAdminRole(STRATEGY_OPERATOR, STRATEGY_ADMIN);
        _setInitialAdminRole(KYC_OPERATOR, RULES_ADMIN);
        _setInitialAdminRole(STRATEGY_ADMIN, PROTOCOL_ADMIN);
        _setInitialAdminRole(RULES_ADMIN, PROTOCOL_ADMIN);
    }

    /**
     * @notice Initialize the role manager with the registry contract
     * @param _registry The address of the registry
     */
    function initializeRegistry(address _registry) external {
        if (msg.sender != owner()) revert Unauthorized();
        if (registry != address(0)) revert AlreadyInitialized();
        if (_registry == address(0)) revert ZeroAddress();

        registry = _registry;
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Grants a role to a user
     * @param user The address of the user to grant the role to
     * @param role The role to grant
     */
    function grantRole(address user, uint256 role) public virtual override {
        // Check authorization using the hierarchical logic
        if (!_canManageRole(msg.sender, role)) {
            revert Unauthorized();
        }

        if (role == 0) revert InvalidRole(); // Prevent granting role 0

        // Grant the role
        _grantRoles(user, role);

        // Emit event
        emit RoleGranted(user, role, msg.sender);
    }

    /**
     * @notice Revokes a role from a user
     * @param user The address of the user to revoke the role from
     * @param role The role to revoke
     */
    function revokeRole(address user, uint256 role) public virtual override {
        // Check authorization using the hierarchical logic
        if (!_canManageRole(msg.sender, role)) {
            revert Unauthorized();
        }

        if (role == 0) revert InvalidRole(); // Prevent revoking role 0

        // Revoke the role
        _removeRoles(user, role);

        // Emit event
        emit RoleRevoked(user, role, msg.sender);
    }

    /**
     * @notice Sets the specific role required to manage a target role
     * @dev Requires the caller to have the PROTOCOL_ADMIN role or be the owner
     * @param targetRole The role whose admin role is to be set
     * @param adminRole The role that will be required to manage the targetRole
     */
    function setRoleAdmin(uint256 targetRole, uint256 adminRole) external virtual {
        // Authorization: Only Owner or PROTOCOL_ADMIN
        // Use hasAllRoles for the strict check against the composite PROTOCOL_ADMIN role
        if (msg.sender != owner() && !hasAllRoles(msg.sender, PROTOCOL_ADMIN)) {
            revert Unauthorized();
        }

        // Prevent managing PROTOCOL_ADMIN itself via this mechanism or setting role 0
        if (targetRole == 0 || targetRole == PROTOCOL_ADMIN) revert InvalidRole();

        roleAdminRole[targetRole] = adminRole;

        emit RoleAdminSet(targetRole, adminRole, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal function to check if an address can manage a specific role
     * @dev Leverages hierarchical bitmasks. Manager must possess all target role bits plus additional bits.
     * @param manager The address to check for management permission
     * @param role The role being managed
     * @return True if the manager can grant/revoke the role
     */
    function _canManageRole(address manager, uint256 role) internal view virtual returns (bool) {
        // Owner can always manage any role.
        if (manager == owner()) {
            return true;
        }

        // PROTOCOL_ADMIN can manage any role *except* PROTOCOL_ADMIN itself.
        if (hasAllRoles(manager, PROTOCOL_ADMIN)) {
            return role != PROTOCOL_ADMIN;
        }

        // --- Check Explicit Mapping ---
        uint256 requiredAdminRole = roleAdminRole[role];

        return requiredAdminRole != 0 && hasAllRoles(manager, requiredAdminRole);
    }

    /**
     * @notice Internal helper to set initial admin roles during construction
     * @dev Does not perform authorization checks.
     * @param targetRole The role whose admin role is to be set
     * @param adminRole The role that will be required to manage the targetRole
     */
    function _setInitialAdminRole(uint256 targetRole, uint256 adminRole) internal {
        roleAdminRole[targetRole] = adminRole;

        // Emit event with contract address as sender for setup clarity
        emit RoleAdminSet(targetRole, adminRole, address(this));
    }
}
