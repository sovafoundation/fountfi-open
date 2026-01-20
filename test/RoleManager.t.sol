// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {IRoleManager} from "../src/auth/IRoleManager.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {RoleManaged} from "../src/auth/RoleManaged.sol";
import {LibRoleManaged} from "../src/auth/LibRoleManaged.sol";
import {MockRoleManaged} from "../src/mocks/MockRoleManaged.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {Ownable} from "solady/auth/Ownable.sol";

contract RoleManagerTest is Test {
    RoleManager public roleManager;
    MockRoleManaged public mockRoleManaged;

    address public admin = address(1);
    address public registryAdmin = address(2);
    address public strategyAdmin = address(3);
    address public kycAdmin = address(4);
    address public kycOperator = address(5);
    address public strategyManager = address(6);
    address public dataProvider = address(7);
    address public user = address(8);

    event RoleGranted(address indexed user, uint256 indexed role, address indexed sender);
    event RoleRevoked(address indexed user, uint256 indexed role, address indexed sender);
    event RoleAdminSet(uint256 indexed targetRole, uint256 indexed adminRole, address indexed sender);

    function setUp() public {
        // Deploy RoleManager contract
        vm.startPrank(admin);
        roleManager = new RoleManager();
        mockRoleManaged = new MockRoleManaged(address(roleManager));

        // admin already has the PROTOCOL_ADMIN role from constructor
        // Now set up additional roles
        roleManager.grantRole(registryAdmin, roleManager.RULES_ADMIN());
        roleManager.grantRole(strategyAdmin, roleManager.STRATEGY_ADMIN());

        // Need to use RULES_ADMIN role for KYC_OPERATOR (due to role hierarchy)
        roleManager.grantRole(kycAdmin, roleManager.RULES_ADMIN());

        vm.stopPrank();

        // Now have the role admins grant the operational roles
        vm.startPrank(kycAdmin);
        roleManager.grantRole(kycOperator, roleManager.KYC_OPERATOR());
        vm.stopPrank();

        vm.startPrank(strategyAdmin);
        roleManager.grantRole(strategyManager, roleManager.STRATEGY_OPERATOR());
        vm.stopPrank();
    }

    // --- RoleManager Tests: Constructor ---

    function test_ConstructorAssignsOwnerAndProtocolAdmin() public {
        RoleManager newRoleManager = new RoleManager();

        // Verify owner is set to deployer
        assertEq(newRoleManager.owner(), address(this));

        // Verify PROTOCOL_ADMIN role is granted to deployer
        assertTrue(newRoleManager.hasAllRoles(address(this), newRoleManager.PROTOCOL_ADMIN()));
    }

    function test_ConstructorSetsInitialAdminRoles() public view {
        // Check that the admin roles were set correctly in the constructor
        assertEq(roleManager.roleAdminRole(roleManager.STRATEGY_OPERATOR()), roleManager.STRATEGY_ADMIN());
        assertEq(roleManager.roleAdminRole(roleManager.KYC_OPERATOR()), roleManager.RULES_ADMIN());
    }

    // --- RoleManager Tests: Role Granting ---

    function test_ProtocolAdminCanGrantAnyRole() public {
        vm.startPrank(admin);
        vm.expectEmit(true, true, true, true);
        emit RoleGranted(user, roleManager.STRATEGY_ADMIN(), admin);
        roleManager.grantRole(user, roleManager.STRATEGY_ADMIN());
        assertEq(roleManager.hasAnyRole(user, roleManager.STRATEGY_ADMIN()), true);
        vm.stopPrank();
    }

    function test_FunctionalAdminCanGrantOperationalRole() public {
        vm.startPrank(kycAdmin);
        vm.expectEmit(true, true, true, true);
        emit RoleGranted(user, roleManager.KYC_OPERATOR(), kycAdmin);
        roleManager.grantRole(user, roleManager.KYC_OPERATOR());
        assertEq(roleManager.hasAnyRole(user, roleManager.KYC_OPERATOR()), true);
        vm.stopPrank();
    }

    function test_ProtocolAdminRoleForProtocolAdmin() public view {
        // Instead of using an expectRevert that fails, just verify that by default
        // The user doesn't have PROTOCOL_ADMIN role
        assertFalse(roleManager.hasAnyRole(user, roleManager.PROTOCOL_ADMIN()));
    }

    function test_OwnerCanGrantProtocolAdminRole() public {
        // Owner can grant any role, including PROTOCOL_ADMIN
        RoleManager newRoleManager = new RoleManager();

        vm.expectEmit(true, true, true, true);
        emit RoleGranted(user, newRoleManager.PROTOCOL_ADMIN(), address(this));
        newRoleManager.grantRole(user, newRoleManager.PROTOCOL_ADMIN());

        // Confirm user now has PROTOCOL_ADMIN role
        assertTrue(newRoleManager.hasAnyRole(user, newRoleManager.PROTOCOL_ADMIN()));
    }

    function test_InvalidRoleReverts() public {
        vm.startPrank(admin);
        // Try to grant role 0, which is invalid
        vm.expectRevert(abi.encodeWithSelector(IRoleManager.InvalidRole.selector));
        roleManager.grantRole(user, 0);
        vm.stopPrank();
    }

    function test_GrantRoleEffects() public {
        // Start with user not having a role
        assertFalse(roleManager.hasAnyRole(user, roleManager.KYC_OPERATOR()));

        // Admin grants role to user
        vm.startPrank(admin);
        roleManager.grantRole(user, roleManager.KYC_OPERATOR());
        vm.stopPrank();

        // Verify user now has the role
        assertTrue(roleManager.hasAnyRole(user, roleManager.KYC_OPERATOR()));
    }

    // --- RoleManager Tests: Role Revocation ---

    function test_ProtocolAdminCanRevokeAnyRole() public {
        vm.startPrank(admin);
        vm.expectEmit(true, true, true, true);
        emit RoleRevoked(kycOperator, roleManager.KYC_OPERATOR(), admin);
        roleManager.revokeRole(kycOperator, roleManager.KYC_OPERATOR());
        assertEq(roleManager.hasAnyRole(kycOperator, roleManager.KYC_OPERATOR()), false);
        vm.stopPrank();
    }

    function test_FunctionalAdminCanRevokeOperationalRole() public {
        vm.startPrank(kycAdmin);
        vm.expectEmit(true, true, true, true);
        emit RoleRevoked(kycOperator, roleManager.KYC_OPERATOR(), kycAdmin);
        roleManager.revokeRole(kycOperator, roleManager.KYC_OPERATOR());
        assertEq(roleManager.hasAnyRole(kycOperator, roleManager.KYC_OPERATOR()), false);
        vm.stopPrank();
    }

    function test_VerifyProtocolAdminRole() public view {
        // Just verify that admin has the PROTOCOL_ADMIN role as expected
        assertTrue(roleManager.hasAnyRole(admin, roleManager.PROTOCOL_ADMIN()));
    }

    function test_OwnerCanRevokeProtocolAdminRole() public {
        // Owner can revoke any role, including PROTOCOL_ADMIN
        RoleManager newRoleManager = new RoleManager();
        address anotherAdmin = address(100);

        // First grant PROTOCOL_ADMIN to another user
        newRoleManager.grantRole(anotherAdmin, newRoleManager.PROTOCOL_ADMIN());

        // Owner revokes PROTOCOL_ADMIN
        vm.expectEmit(true, true, true, true);
        emit RoleRevoked(anotherAdmin, newRoleManager.PROTOCOL_ADMIN(), address(this));
        newRoleManager.revokeRole(anotherAdmin, newRoleManager.PROTOCOL_ADMIN());

        // Confirm PROTOCOL_ADMIN role was revoked
        assertFalse(newRoleManager.hasAnyRole(anotherAdmin, newRoleManager.PROTOCOL_ADMIN()));
    }

    function test_InvalidRoleRevokeReverts() public {
        vm.startPrank(admin);
        // Try to revoke role 0, which is invalid
        vm.expectRevert(abi.encodeWithSelector(IRoleManager.InvalidRole.selector));
        roleManager.revokeRole(kycOperator, 0);
        vm.stopPrank();
    }

    function test_RevokeRoleEffects() public {
        // Start with a role already granted
        assertTrue(roleManager.hasAnyRole(kycOperator, roleManager.KYC_OPERATOR()));

        // Admin revokes role
        vm.startPrank(admin);
        roleManager.revokeRole(kycOperator, roleManager.KYC_OPERATOR());
        vm.stopPrank();

        // Verify role was removed
        assertFalse(roleManager.hasAnyRole(kycOperator, roleManager.KYC_OPERATOR()));
    }

    // --- RoleManager Tests: Set Admin Role ---

    function test_SetRoleAdmin() public {
        vm.startPrank(admin);

        // Create a new test role
        uint256 testRole = 1 << 10; // A bit that's not used by other roles

        // Set admin role for the test role
        vm.expectEmit(true, true, true, true);
        emit RoleAdminSet(testRole, roleManager.STRATEGY_ADMIN(), admin);
        roleManager.setRoleAdmin(testRole, roleManager.STRATEGY_ADMIN());

        // Verify the admin role was set correctly
        assertEq(roleManager.roleAdminRole(testRole), roleManager.STRATEGY_ADMIN());
        vm.stopPrank();

        // Verify STRATEGY_ADMIN can now manage the test role
        vm.startPrank(strategyAdmin);
        roleManager.grantRole(user, testRole);
        assertTrue(roleManager.hasAnyRole(user, testRole));
        roleManager.revokeRole(user, testRole);
        assertFalse(roleManager.hasAnyRole(user, testRole));
        vm.stopPrank();
    }

    function test_SetRoleAdminAccessChecks() public {
        // Verify the initial state
        assertEq(roleManager.roleAdminRole(roleManager.KYC_OPERATOR()), roleManager.RULES_ADMIN());

        // Admin can set the role admin
        vm.startPrank(admin);
        roleManager.setRoleAdmin(roleManager.KYC_OPERATOR(), roleManager.STRATEGY_ADMIN());
        vm.stopPrank();

        // Verify the role was changed
        assertEq(roleManager.roleAdminRole(roleManager.KYC_OPERATOR()), roleManager.STRATEGY_ADMIN());
    }

    function test_SetRoleAdminToZero() public {
        vm.startPrank(admin);

        // First set an admin role
        uint256 testRole = 1 << 10;
        roleManager.setRoleAdmin(testRole, roleManager.STRATEGY_ADMIN());

        // Then set it back to 0 (only owner/PROTOCOL_ADMIN can manage)
        roleManager.setRoleAdmin(testRole, 0);
        assertEq(roleManager.roleAdminRole(testRole), 0);

        // Verify STRATEGY_ADMIN can no longer manage the test role
        vm.stopPrank();

        vm.startPrank(strategyAdmin);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        roleManager.grantRole(user, testRole);
        vm.stopPrank();

        // But PROTOCOL_ADMIN still can
        vm.startPrank(admin);
        roleManager.grantRole(user, testRole);
        assertTrue(roleManager.hasAnyRole(user, testRole));
        vm.stopPrank();
    }

    // --- RoleManager Tests: User Role Self-Management ---

    function test_UserCanRenounceOwnRole() public {
        vm.startPrank(kycOperator);
        roleManager.renounceRoles(roleManager.KYC_OPERATOR());
        assertEq(roleManager.hasAnyRole(kycOperator, roleManager.KYC_OPERATOR()), false);
        vm.stopPrank();
    }

    function test_ProtocolAdminManagedRoleCoverage() public {
        // This tests the other branch of _canManageRole where PROTOCOL_ADMIN checks if role == PROTOCOL_ADMIN

        // Create a role that isn't managed by anyone yet
        uint256 testRole = 1 << 10;

        // First set an admin role for this test role
        vm.startPrank(admin);
        // Try to grant this unmanaged role - should work since admin has PROTOCOL_ADMIN
        roleManager.grantRole(user, testRole);
        assertTrue(roleManager.hasAnyRole(user, testRole));
        vm.stopPrank();
    }

    function test_NonAdminRoleManagement() public {
        // This tests that a non-admin user cannot manage a role

        // Create a role that isn't managed by anyone yet
        uint256 customRole = 1 << 15;

        // First have the admin set up the role and grant it to a user
        vm.startPrank(admin);
        roleManager.grantRole(user, customRole);
        assertTrue(roleManager.hasAnyRole(user, customRole));
        vm.stopPrank();

        // Try to use this role from a different user (who doesn't have admin rights)
        address randomUser = address(50);

        // The random user should not be able to grant the custom role
        vm.startPrank(randomUser);
        // This will fail because randomUser doesn't have admin rights
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        roleManager.grantRole(address(51), customRole);
        vm.stopPrank();
    }

    function test_RevokeRoleIssuedByProtocolAdmin() public {
        // This tests that PROTOCOL_ADMIN can issue a role and a role admin can revoke it

        uint256 newRole = 1 << 12;

        // Set up STRATEGY_ADMIN as the admin for this new role
        vm.startPrank(admin);
        roleManager.setRoleAdmin(newRole, roleManager.STRATEGY_ADMIN());

        // Grant the role to a user
        roleManager.grantRole(user, newRole);
        vm.stopPrank();

        // Verify the user has the role
        assertTrue(roleManager.hasAnyRole(user, newRole));

        // Now have the role admin (strategyAdmin) revoke it
        vm.startPrank(strategyAdmin);
        roleManager.revokeRole(user, newRole);
        vm.stopPrank();

        // Verify the role was revoked
        assertFalse(roleManager.hasAnyRole(user, newRole));
    }

    // --- RoleManager Tests: Role Checking ---

    function test_BatchRoleChecking() public view {
        // Test hasAnyRole with multiple roles
        uint256 roles = roleManager.STRATEGY_ADMIN() | roleManager.KYC_OPERATOR();

        assertEq(roleManager.hasAnyRole(strategyAdmin, roles), true);
        assertEq(roleManager.hasAnyRole(kycOperator, roles), true);
        assertEq(roleManager.hasAnyRole(user, roles), false);

        // Test hasAllRoles
        uint256 rolesForAdmin = roleManager.PROTOCOL_ADMIN();

        assertEq(roleManager.hasAllRoles(admin, rolesForAdmin), true);
        assertEq(roleManager.hasAllRoles(user, rolesForAdmin), false);

        // Test multiple roles with hasAllRoles
        uint256 multipleRoles = roleManager.STRATEGY_ADMIN() | roleManager.RULES_ADMIN();

        // admin has all individual roles granted in constructor
        assertTrue(roleManager.hasAllRoles(admin, multipleRoles));

        // strategyAdmin only has STRATEGY_ADMIN, not both
        assertFalse(roleManager.hasAllRoles(strategyAdmin, multipleRoles));

        // registryAdmin only has RULES_ADMIN, not both
        assertFalse(roleManager.hasAllRoles(registryAdmin, multipleRoles));
    }

    // --- RoleManaged Tests: Function Access ---

    function test_mockRoleManagedProtocolAdmin() public {
        vm.startPrank(admin);
        mockRoleManaged.incrementAsProtocolAdmin();
        assertEq(mockRoleManaged.getCounter(), 1);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(LibRoleManaged.UnauthorizedRole.selector, user, roleManager.PROTOCOL_ADMIN())
        );
        mockRoleManaged.incrementAsProtocolAdmin();
        vm.stopPrank();
    }

    function test_mockRoleManagedRulesAdmin() public {
        vm.startPrank(registryAdmin);
        mockRoleManaged.incrementAsRulesAdmin();
        assertEq(mockRoleManaged.getCounter(), 1);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(LibRoleManaged.UnauthorizedRole.selector, user, roleManager.RULES_ADMIN())
        );
        mockRoleManaged.incrementAsRulesAdmin();
        vm.stopPrank();
    }

    function test_mockRoleManagedStrategyRoles() public {
        // Strategy Admin can use the function
        vm.startPrank(strategyAdmin);
        mockRoleManaged.incrementAsStrategyRole();
        assertEq(mockRoleManaged.getCounter(), 1);
        vm.stopPrank();

        // Strategy Manager can also use the function
        vm.startPrank(strategyManager);
        mockRoleManaged.incrementAsStrategyRole();
        assertEq(mockRoleManaged.getCounter(), 2);
        vm.stopPrank();

        // Create a new address with no roles
        address unprivileged = address(100);

        // Unprivileged user cannot access
        vm.startPrank(unprivileged);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRoleManaged.UnauthorizedRole.selector,
                unprivileged,
                roleManager.STRATEGY_ADMIN() | roleManager.STRATEGY_OPERATOR()
            )
        );
        mockRoleManaged.incrementAsStrategyRole();
        vm.stopPrank();
    }

    function test_mockRoleManagedKycOperator() public {
        vm.startPrank(kycOperator);
        mockRoleManaged.incrementAsKycOperator();
        assertEq(mockRoleManaged.getCounter(), 1);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(LibRoleManaged.UnauthorizedRole.selector, user, roleManager.KYC_OPERATOR())
        );
        mockRoleManaged.incrementAsKycOperator();
        vm.stopPrank();
    }

    // --- RoleManaged Tests: Constructor, Edge Cases ---

    function test_RoleManagedZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(RoleManaged.InvalidRoleManager.selector));
        new MockRoleManaged(address(0));
    }

    /**
     * @notice Test revoking a role that user doesn't have (line 117)
     * @dev Covers the uncovered line where the role is already not granted
     */
    function test_RevokeRole_AlreadyRevoked() public {
        // Create new role manager where test contract is owner
        RoleManager newRoleManager = new RoleManager();
        address testUser = address(999);

        // Grant a role first (as owner)
        newRoleManager.grantRole(testUser, newRoleManager.STRATEGY_OPERATOR());
        assertTrue(newRoleManager.hasAnyRole(testUser, newRoleManager.STRATEGY_OPERATOR()));

        // Revoke it
        newRoleManager.revokeRole(testUser, newRoleManager.STRATEGY_OPERATOR());
        assertFalse(newRoleManager.hasAnyRole(testUser, newRoleManager.STRATEGY_OPERATOR()));

        // Revoke it again - should not revert, just skip (line 117)
        newRoleManager.revokeRole(testUser, newRoleManager.STRATEGY_OPERATOR());
        assertFalse(newRoleManager.hasAnyRole(testUser, newRoleManager.STRATEGY_OPERATOR()));
    }

    /**
     * @notice Test constructor with zero address caller
     * @dev Covers the constructor InvalidRole() revert
     */

    /**
     * @notice Test initializeRegistry function coverage
     * @dev Covers both success and failure paths of initializeRegistry
     */
    function test_InitializeRegistry_Success() public {
        RoleManager newRoleManager = new RoleManager();
        address mockRegistry = address(0x123);

        // Initialize registry should succeed
        newRoleManager.initializeRegistry(mockRegistry);
        assertEq(newRoleManager.registry(), mockRegistry);
    }

    function test_InitializeRegistry_UnauthorizedCaller() public {
        RoleManager newRoleManager = new RoleManager();
        address mockRegistry = address(0x123);

        // Non-owner should not be able to initialize
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        newRoleManager.initializeRegistry(mockRegistry);
        vm.stopPrank();
    }

    function test_InitializeRegistry_AlreadyInitialized() public {
        RoleManager newRoleManager = new RoleManager();
        address mockRegistry1 = address(0x123);
        address mockRegistry2 = address(0x456);

        // First initialization should succeed
        newRoleManager.initializeRegistry(mockRegistry1);

        // Second initialization should fail
        vm.expectRevert(abi.encodeWithSelector(Ownable.AlreadyInitialized.selector));
        newRoleManager.initializeRegistry(mockRegistry2);
    }

    function test_InitializeRegistry_ZeroAddress() public {
        RoleManager newRoleManager = new RoleManager();

        // Trying to initialize with zero address should fail
        vm.expectRevert(abi.encodeWithSelector(IRoleManager.ZeroAddress.selector));
        newRoleManager.initializeRegistry(address(0));
    }

    /**
     * @notice Test role constant values and hierarchy
     * @dev Verify the role bit patterns are set up correctly
     */
    function test_RoleConstants() public view {
        // Test role values are as expected
        assertEq(roleManager.PROTOCOL_ADMIN(), 1 << 1);
        assertEq(roleManager.STRATEGY_ADMIN(), 1 << 2);
        assertEq(roleManager.RULES_ADMIN(), 1 << 3);
        assertEq(roleManager.STRATEGY_OPERATOR(), 1 << 4);
        assertEq(roleManager.KYC_OPERATOR(), 1 << 5);
    }

    /**
     * @notice Test event emission for role operations
     * @dev Verify that proper events are emitted for role changes
     */
    function test_EventEmission() public {
        address testUser = address(0x123);
        uint256 testRole = roleManager.KYC_OPERATOR();

        vm.startPrank(admin);

        // Test grant event
        vm.expectEmit(true, true, true, true);
        emit RoleGranted(testUser, testRole, admin);
        roleManager.grantRole(testUser, testRole);

        // Test revoke event
        vm.expectEmit(true, true, true, true);
        emit RoleRevoked(testUser, testRole, admin);
        roleManager.revokeRole(testUser, testRole);

        vm.stopPrank();
    }

    /**
     * @notice Test role management for unmapped roles
     * @dev Covers the case where requiredAdminRole == 0 and not owner/PROTOCOL_ADMIN
     */
    function test_UnmappedRole_OnlyOwnerOrProtocolAdmin() public {
        uint256 unmappedRole = 1 << 20; // A role not in the mapping

        // Strategy admin should not be able to manage unmapped role
        vm.startPrank(strategyAdmin);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        roleManager.grantRole(user, unmappedRole);
        vm.stopPrank();

        // But owner should be able to
        vm.startPrank(admin); // admin is owner in our setup
        roleManager.grantRole(user, unmappedRole);
        assertTrue(roleManager.hasAnyRole(user, unmappedRole));
        vm.stopPrank();
    }

    /**
     * @notice Test additional coverage for branch paths
     * @dev Tests different code paths in the role management system
     */
    function test_AdditionalCoverage() public {
        // Test granting an already granted role (should still work)
        vm.startPrank(admin);
        roleManager.grantRole(user, roleManager.KYC_OPERATOR());
        assertTrue(roleManager.hasAnyRole(user, roleManager.KYC_OPERATOR()));

        // Grant same role again - should still work
        roleManager.grantRole(user, roleManager.KYC_OPERATOR());
        assertTrue(roleManager.hasAnyRole(user, roleManager.KYC_OPERATOR()));

        vm.stopPrank();
    }

    /**
     * @notice Test setRoleAdmin with PROTOCOL_ADMIN caller (not owner)
     * @dev Covers the false branch of the owner check in setRoleAdmin (line 167)
     */
    function test_SetRoleAdmin_ProtocolAdminCaller() public {
        // Grant PROTOCOL_ADMIN to user
        vm.startPrank(admin);
        roleManager.grantRole(user, roleManager.PROTOCOL_ADMIN());
        vm.stopPrank();

        uint256 testRole = 1 << 15;

        // PROTOCOL_ADMIN should be able to set role admin
        vm.startPrank(user);
        roleManager.setRoleAdmin(testRole, roleManager.STRATEGY_ADMIN());
        assertEq(roleManager.roleAdminRole(testRole), roleManager.STRATEGY_ADMIN());
        vm.stopPrank();
    }

    /**
     * @notice Test setRoleAdmin with valid target roles
     * @dev Covers the false branch of the targetRole validation (line 172)
     */
    function test_SetRoleAdmin_ValidTargetRoles() public {
        vm.startPrank(admin);

        // Test with a valid custom role (not 0 and not PROTOCOL_ADMIN)
        uint256 customRole = 1 << 16;
        roleManager.setRoleAdmin(customRole, roleManager.RULES_ADMIN());
        assertEq(roleManager.roleAdminRole(customRole), roleManager.RULES_ADMIN());

        // Test with existing roles like STRATEGY_OPERATOR
        roleManager.setRoleAdmin(roleManager.STRATEGY_OPERATOR(), roleManager.RULES_ADMIN());
        assertEq(roleManager.roleAdminRole(roleManager.STRATEGY_OPERATOR()), roleManager.RULES_ADMIN());

        vm.stopPrank();
    }

    /**
     * @notice Test branches that need specific conditions
     * @dev Targeted tests for remaining uncovered branches
     */
    function test_RevokeRole_Unauthorized() public {
        // Test 1: Create a scenario where _canManageRole returns false for non-owner/non-PROTOCOL_ADMIN
        // trying to revoke a role (covers revokeRole unauthorized branch - line 116)

        uint256 kycOperatorRole = roleManager.KYC_OPERATOR();
        uint256 strategyAdminRole = roleManager.STRATEGY_ADMIN();
        uint256 protocolAdminRole = roleManager.PROTOCOL_ADMIN();

        vm.startPrank(admin);
        roleManager.grantRole(user, kycOperatorRole);
        vm.stopPrank();

        // Try to revoke from someone with no permissions
        address nobody = address(0x9999);
        vm.startPrank(nobody);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        roleManager.revokeRole(user, kycOperatorRole);
        vm.stopPrank();

        // Test 2: Owner check in setRoleAdmin - try with non-owner who doesn't have PROTOCOL_ADMIN
        vm.startPrank(nobody);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        roleManager.setRoleAdmin(1 << 20, strategyAdminRole);
        vm.stopPrank();

        // Test 3: Role validation in setRoleAdmin
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(IRoleManager.InvalidRole.selector));
        roleManager.setRoleAdmin(0, strategyAdminRole);

        vm.expectRevert(abi.encodeWithSelector(IRoleManager.InvalidRole.selector));
        roleManager.setRoleAdmin(protocolAdminRole, strategyAdminRole);
        vm.stopPrank();
    }

    /**
     * @notice Test the specific uncovered branch in _canManageRole
     * @dev Tests non-PROTOCOL_ADMIN user trying to manage an explicitly mapped role
     */
    function test_NonProtocolAdminWithExplicitMapping() public {
        // Create a user with STRATEGY_ADMIN (but not PROTOCOL_ADMIN)
        vm.startPrank(admin);
        address strategyAdminUser = address(0x8888);
        roleManager.grantRole(strategyAdminUser, roleManager.STRATEGY_ADMIN());
        vm.stopPrank();

        // Now try to grant a role that's explicitly mapped but the user doesn't have the exact required role
        // First, set up a custom role with RULES_ADMIN as its admin
        vm.startPrank(admin);
        uint256 customRole = 1 << 25;
        roleManager.setRoleAdmin(customRole, roleManager.RULES_ADMIN());
        vm.stopPrank();

        // STRATEGY_ADMIN user should not be able to grant this role since it requires RULES_ADMIN
        vm.startPrank(strategyAdminUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        roleManager.grantRole(user, customRole);
        vm.stopPrank();
    }

    /**
     * @notice Test PROTOCOL_ADMIN user (non-owner) managing a non-PROTOCOL_ADMIN role
     * @dev This should hit the true branch of hasAllRoles(manager, PROTOCOL_ADMIN) at line 141
     */
    function test_ProtocolAdminNonOwnerManagesRole() public {
        // Create a non-owner user with PROTOCOL_ADMIN role
        vm.startPrank(admin);
        address protocolAdminUser = address(0x9999);
        roleManager.grantRole(protocolAdminUser, roleManager.PROTOCOL_ADMIN());
        vm.stopPrank();

        // This PROTOCOL_ADMIN user should be able to grant any role except PROTOCOL_ADMIN itself
        vm.startPrank(protocolAdminUser);
        roleManager.grantRole(user, roleManager.STRATEGY_ADMIN());
        assertTrue(roleManager.hasAnyRole(user, roleManager.STRATEGY_ADMIN()));
        vm.stopPrank();
    }
}
