// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {BaseHook} from "./BaseHook.sol";
import {RoleManaged} from "../auth/RoleManaged.sol";
import {IHook} from "./IHook.sol";

/**
 * @title KycRulesHook
 * @notice Hook that restricts transfers based on sender/receiver KYC status
 * @dev Uses allow/deny lists to determine if transfers are permitted
 */
contract KycRulesHook is BaseHook, RoleManaged {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroAddress();
    error AddressAlreadyDenied();
    error InvalidArrayLength();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event AddressAllowed(address indexed account, address indexed operator);
    event AddressDenied(address indexed account, address indexed operator);
    event AddressRestrictionRemoved(address indexed account, address indexed operator);
    event BatchAddressAllowed(uint256 count, address indexed operator);
    event BatchAddressDenied(uint256 count, address indexed operator);
    event BatchAddressRestrictionRemoved(uint256 count, address indexed operator);

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    // Allow and deny lists
    mapping(address => bool) public isAddressAllowed;
    mapping(address => bool) public isAddressDenied;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructor
     * @param _roleManager Address of the role manager contract
     */
    constructor(address _roleManager) BaseHook("KycRulesHook-1.0") RoleManaged(_roleManager) {}

    /*//////////////////////////////////////////////////////////////
                            WHITELIST MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allow an address to transfer/receive tokens
     * @param account Address to allow
     */
    function allow(address account) external onlyRoles(roleManager.KYC_OPERATOR()) {
        _allow(account);
    }

    /**
     * @notice Deny an address from transferring/receiving tokens
     * @param account Address to deny
     */
    function deny(address account) external onlyRoles(roleManager.KYC_OPERATOR()) {
        _deny(account);
    }

    /**
     * @notice Reset an address by removing it from both allow and deny lists
     * @param account Address to reset
     */
    function reset(address account) external onlyRoles(roleManager.KYC_OPERATOR()) {
        _reset(account);
    }

    /**
     * @notice Batch allow addresses to transfer/receive tokens
     * @param accounts Array of addresses to allow
     */
    function batchAllow(address[] calldata accounts) external onlyRoles(roleManager.KYC_OPERATOR()) {
        uint256 length = accounts.length;
        if (length == 0) revert InvalidArrayLength();

        for (uint256 i = 0; i < length;) {
            _allow(accounts[i]);

            unchecked {
                ++i;
            }
        }

        emit BatchAddressAllowed(length, msg.sender);
    }

    /**
     * @notice Batch deny addresses from transferring/receiving tokens
     * @param accounts Array of addresses to deny
     */
    function batchDeny(address[] calldata accounts) external onlyRoles(roleManager.KYC_OPERATOR()) {
        uint256 length = accounts.length;
        if (length == 0) revert InvalidArrayLength();

        for (uint256 i = 0; i < length;) {
            _deny(accounts[i]);

            unchecked {
                ++i;
            }
        }

        emit BatchAddressDenied(length, msg.sender);
    }

    /**
     * @notice Batch reset addresses by removing them from both allow and deny lists
     * @param accounts Array of addresses to reset
     */
    function batchReset(address[] calldata accounts) external onlyRoles(roleManager.KYC_OPERATOR()) {
        uint256 length = accounts.length;
        if (length == 0) revert InvalidArrayLength();

        for (uint256 i = 0; i < length;) {
            _reset(accounts[i]);

            unchecked {
                ++i;
            }
        }

        emit BatchAddressRestrictionRemoved(length, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if an address is allowed to transfer/receive tokens
     * @param account Address to check
     * @return Whether the address is allowed
     */
    function isAllowed(address account) public view returns (bool) {
        return !isAddressDenied[account] && isAddressAllowed[account];
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal function to allow an address
     * @param account Address to allow
     */
    function _allow(address account) internal {
        if (account == address(0)) revert ZeroAddress();
        if (isAddressDenied[account]) revert AddressAlreadyDenied();

        isAddressAllowed[account] = true;

        emit AddressAllowed(account, msg.sender);
    }

    /**
     * @notice Internal function to deny an address
     * @param account Address to deny
     */
    function _deny(address account) internal {
        if (account == address(0)) revert ZeroAddress();

        isAddressAllowed[account] = false;
        isAddressDenied[account] = true;

        emit AddressDenied(account, msg.sender);
    }

    /**
     * @notice Internal function to reset an address
     * @param account Address to reset
     */
    function _reset(address account) internal {
        if (account == address(0)) revert ZeroAddress();

        isAddressAllowed[account] = false;
        isAddressDenied[account] = false;

        emit AddressRestrictionRemoved(account, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            HOOK LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Hook executed before a transfer operation
     * @param from Address sending tokens
     * @param to Address receiving tokens
     * @return bytes4 Selector indicating success or specific failure reason
     */
    function onBeforeTransfer(
        address, // token
        address from,
        address to,
        uint256 // amount
    ) public view override returns (IHook.HookOutput memory) {
        return _checkSenderAndReceiver(from, to);
    }

    /**
     * @notice Hook executed before a deposit operation
     * @param user Address initiating the deposit
     * @param receiver Address receiving the shares
     * @return bytes4 Selector indicating success or specific failure reason
     */
    function onBeforeDeposit(
        address, // token
        address user,
        uint256, // amount
        address receiver
    ) public view override returns (IHook.HookOutput memory) {
        return _checkSenderAndReceiver(user, receiver);
    }

    /**
     * @notice Hook executed before a withdraw operation
     * @param user Address initiating the withdrawal
     * @param receiver Address receiving the assets
     * @param owner Address owning the shares
     * @return bytes4 Selector indicating success or specific failure reason
     */
    function onBeforeWithdraw(
        address, // token
        address user,
        uint256, // amount
        address receiver,
        address owner
    ) public view override returns (IHook.HookOutput memory) {
        // Check if the owner is allowed
        if (!isAllowed(owner)) {
            return IHook.HookOutput({approved: false, reason: "KycRules: owner"});
        }

        return _checkSenderAndReceiver(user, receiver);
    }

    /**
     * @notice Internal function to check if both sender and receiver are allowed
     * @param from Address sending tokens
     * @param to Address receiving tokens
     * @return IHook.HookOutput Result of the check
     */
    function _checkSenderAndReceiver(address from, address to) internal view returns (IHook.HookOutput memory) {
        if (from != address(0) && !isAllowed(from)) {
            return IHook.HookOutput({approved: false, reason: "KycRules: sender"});
        }

        if (to != address(0) && !isAllowed(to)) {
            return IHook.HookOutput({approved: false, reason: "KycRules: receiver"});
        }

        return IHook.HookOutput({approved: true, reason: ""});
    }
}
