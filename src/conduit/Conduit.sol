// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {RoleManaged} from "../auth/RoleManaged.sol";
import {ItRWA} from "../token/ItRWA.sol";
import {IRegistry} from "../registry/IRegistry.sol";

/**
 * @title Conduit
 * @notice Contract to collect deposits on behalf of tRWA contracts
 * @dev This contract is used to collect deposits from users, and transfer them
 *      to strategy contracts. This allows users to make single global approvals
 *      to the Conduit contract, and then deposit into any strategy.
 */
contract Conduit is RoleManaged {
    using SafeTransferLib for address;

    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidAmount();
    error InvalidToken();
    error InvalidDestination();

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructor
     * @dev Constructor is called by the registry contract
     * @param _roleManager Address of the role manager contract
     */
    constructor(address _roleManager) RoleManaged(_roleManager) {}

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Executes a token transfer on behalf of an approved tRWA contract.
     * @dev The user (`_from`) must have approved this Conduit contract to spend `_amount` of `_token`.
     *      Only callable by an `approvedTRWAContracts`.
     * @param token The address of the ERC20 token to transfer.
     * @param from The address of the user whose tokens are being transferred.
     * @param to The address to transfer the tokens to (e.g., the tRWA contract or a designated vault).
     * @param amount The amount of tokens to transfer.
     */
    function collectDeposit(address token, address from, address to, uint256 amount) external returns (bool) {
        if (amount == 0) revert InvalidAmount();
        if (!IRegistry(registry()).isStrategyToken(msg.sender)) revert InvalidDestination();
        if (ItRWA(msg.sender).asset() != token) revert InvalidToken();
        if (ItRWA(msg.sender).strategy() != to) revert InvalidDestination();

        // Transfer tokens from the user to specific destination
        token.safeTransferFrom(from, to, amount);

        return true;
    }

    /**
     * @notice Rescues ERC20 tokens from the conduit
     * @param tokenAddress The address of the ERC20 token to rescue
     * @param to The address to transfer the tokens to
     * @param amount The amount of tokens to transfer
     */
    function rescueERC20(address tokenAddress, address to, uint256 amount)
        external
        onlyRoles(roleManager.PROTOCOL_ADMIN())
    {
        tokenAddress.safeTransfer(to, amount);
    }
}
