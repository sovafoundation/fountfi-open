// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

/**
 * @title IHook
 * @notice Interface for operation hooks in the tRWA system
 * @dev Operation hooks are called before key operations (deposit, withdraw, transfer)
 * and can approve or reject the operation with a reason
 */
interface IHook {
    /*//////////////////////////////////////////////////////////////
                            DATA STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @title HookOutput
     * @notice Structure representing the result of a hook evaluation
     * @param approved Whether the operation is approved by this hook
     * @param reason Reason for approval/rejection (for logging or error messages)
     */
    struct HookOutput {
        bool approved;
        string reason;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the unique identifier for this hook
     * @return Hook identifier
     */
    function hookId() external view returns (bytes32);

    /**
     * @notice Returns the human readable name of this hook
     * @return Hook name
     */
    function name() external view returns (string memory);

    /*//////////////////////////////////////////////////////////////
                            HOOK LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Called before a deposit operation
     * @param token Address of the token
     * @param user Address of the user
     * @param assets Amount of assets to deposit
     * @param receiver Address of the receiver
     * @return HookOutput Result of the hook evaluation
     */
    function onBeforeDeposit(address token, address user, uint256 assets, address receiver)
        external
        returns (HookOutput memory);

    /**
     * @notice Called before a withdraw operation
     * @param token Address of the token
     * @param by Address of the sender
     * @param assets Amount of assets to withdraw
     * @param to Address of the receiver
     * @param owner Address of the owner
     * @return HookOutput Result of the hook evaluation
     */
    function onBeforeWithdraw(address token, address by, uint256 assets, address to, address owner)
        external
        returns (HookOutput memory);

    /**
     * @notice Called before a transfer operation
     * @param token Address of the token
     * @param from Address of the sender
     * @param to Address of the receiver
     * @param amount Amount of assets to transfer
     * @return HookOutput Result of the hook evaluation
     */
    function onBeforeTransfer(address token, address from, address to, uint256 amount)
        external
        returns (HookOutput memory);
}
