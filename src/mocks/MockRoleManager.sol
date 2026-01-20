// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title MockRoleManager
 * @notice Mock implementation of RoleManager for testing
 */
contract MockRoleManager {
    // Role constants
    uint256 public constant PROTOCOL_ADMIN = 1 << 0;
    uint256 public constant REGISTRY_ADMIN = 1 << 1;
    uint256 public constant STRATEGY_ADMIN = 1 << 2;
    uint256 public constant KYC_ADMIN = 1 << 3;
    uint256 public constant REPORTER_ADMIN = 1 << 4;
    uint256 public constant SUBSCRIPTION_ADMIN = 1 << 5;
    uint256 public constant WITHDRAWAL_ADMIN = 1 << 6;
    uint256 public constant STRATEGY_MANAGER = 1 << 7;
    uint256 public constant KYC_OPERATOR = 1 << 8;
    uint256 public constant DATA_PROVIDER = 1 << 9;

    // Owner address for testing permissions
    address public owner;
    mapping(address => mapping(uint256 => bool)) public roles;

    // Constructor
    constructor(address _owner) {
        owner = _owner;
        // Give all roles to owner
        roles[_owner][PROTOCOL_ADMIN] = true;
        roles[_owner][REGISTRY_ADMIN] = true;
        roles[_owner][STRATEGY_ADMIN] = true;
        roles[_owner][KYC_ADMIN] = true;
        roles[_owner][REPORTER_ADMIN] = true;
        roles[_owner][SUBSCRIPTION_ADMIN] = true;
        roles[_owner][WITHDRAWAL_ADMIN] = true;
        roles[_owner][STRATEGY_MANAGER] = true;
        roles[_owner][KYC_OPERATOR] = true;
        roles[_owner][DATA_PROVIDER] = true;
    }

    // Grant a role to a user
    function grantRole(address user, uint256 role) external {
        roles[user][role] = true;
    }

    // Revoke a role from a user
    function revokeRole(address user, uint256 role) external {
        roles[user][role] = false;
    }

    // Check if a user has a role
    function hasRole(address user, uint256 role) external view returns (bool) {
        return roles[user][role];
    }

    // Check if a user has any role bits (for compatibility with RoleManager)
    function hasAnyRole(address user, uint256 role) external view returns (bool) {
        // Check for any of the role bits
        for (uint256 i = 0; i < 256; i++) {
            uint256 roleBit = 1 << i;
            if ((role & roleBit) != 0 && roles[user][roleBit]) {
                return true;
            }
            // A reasonable limit for checking bits
            if (roleBit == 0 || i > 32) break;
        }
        return false;
    }

    // Check if a user has all role bits (for compatibility with RoleManager)
    function hasAllRoles(address user, uint256 role) external view returns (bool) {
        // Check for all of the role bits
        for (uint256 i = 0; i < 256; i++) {
            uint256 roleBit = 1 << i;
            if ((role & roleBit) != 0 && !roles[user][roleBit]) {
                return false;
            }
            // A reasonable limit for checking bits
            if (roleBit == 0 || i > 32) break;
        }
        return true;
    }

    // Check if a user has any of the specified roles (array version)
    function hasAnyOfRoles(address user, uint256[] calldata _roles) external view returns (bool) {
        for (uint256 i = 0; i < _roles.length; i++) {
            if (roles[user][_roles[i]]) {
                return true;
            }
        }
        return false;
    }

    // Check if a user has all of the specified roles (array version)
    function hasAllRolesArray(address user, uint256[] calldata _roles) external view returns (bool) {
        for (uint256 i = 0; i < _roles.length; i++) {
            if (!roles[user][_roles[i]]) {
                return false;
            }
        }
        return true;
    }

    // Let user renounce a role
    function renounceRole(uint256 role) external {
        roles[msg.sender][role] = false;
    }
}
