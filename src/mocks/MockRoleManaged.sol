// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RoleManaged} from "../auth/RoleManaged.sol";
import {IRoleManager} from "../auth/IRoleManager.sol";

/// @title MockRoleManaged
/// @notice Mock contract for testing role-based access control
contract MockRoleManaged is RoleManaged {
    uint256 public counter;

    event CounterIncremented(address operator, uint256 newValue);

    constructor(address _roleManager) RoleManaged(_roleManager) {}

    /// @notice Function that can only be called by PROTOCOL_ADMIN
    function incrementAsProtocolAdmin() external onlyRoles(roleManager.PROTOCOL_ADMIN()) {
        counter++;
        emit CounterIncremented(msg.sender, counter);
    }

    /// @notice Function that can only be called by RULES_ADMIN
    function incrementAsRulesAdmin() external onlyRoles(roleManager.RULES_ADMIN()) {
        counter++;
        emit CounterIncremented(msg.sender, counter);
    }

    /// @notice Function that can be called by either STRATEGY_ADMIN or STRATEGY_MANAGER
    function incrementAsStrategyRole() external onlyRoles(_getStrategyRoles()) {
        counter++;
        emit CounterIncremented(msg.sender, counter);
    }

    /// @notice Function that can be called by KYC_ADMIN
    function incrementAsKycAdmin() external onlyRoles(roleManager.KYC_OPERATOR()) {
        counter++;
        emit CounterIncremented(msg.sender, counter);
    }

    /// @notice Function that can be called by KYC_OPERATOR
    function incrementAsKycOperator() external onlyRoles(roleManager.KYC_OPERATOR()) {
        counter++;
        emit CounterIncremented(msg.sender, counter);
    }

    /// @notice Get the current counter value - no restrictions
    function getCounter() external view returns (uint256) {
        return counter;
    }

    /// @notice Helper function to get the strategy roles
    /// @return roles Array containing STRATEGY_ADMIN and STRATEGY_MANAGER roles
    function _getStrategyRoles() internal view returns (uint256) {
        return roleManager.STRATEGY_ADMIN() | roleManager.STRATEGY_OPERATOR();
    }
}
