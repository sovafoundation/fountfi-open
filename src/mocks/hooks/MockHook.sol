// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IHook} from "../../hooks/IHook.sol";

/**
 * @title MockHook
 * @notice Mock implementation of the IHook interface for testing
 */
contract MockHook is IHook {
    string public name;
    bool public approveOperations;
    string public rejectReason;

    // Event for verification in tests
    event HookCalled(string operation, address token, address user, uint256 assets, address receiver);
    event WithdrawHookCalled(address token, address by, uint256 assets, address to, address owner);
    event TransferHookCalled(address token, address from, address to, uint256 amount);

    constructor(bool _approveOperations, string memory _rejectReason) {
        name = "MockHook";
        approveOperations = _approveOperations;
        rejectReason = _rejectReason;
    }

    /**
     * @notice Set the name of the hook (useful for creating unique identifiers in tests)
     * @param _name New name for the hook
     */
    function setName(string memory _name) external {
        name = _name;
    }

    /**
     * @notice Set whether operations should be approved
     * @param _approve Whether operations should be approved
     * @param _reason Reason for rejection if not approved
     */
    function setApproveStatus(bool _approve, string memory _reason) external {
        approveOperations = _approve;
        rejectReason = _reason;
    }

    /**
     * @notice Returns the unique identifier for this hook
     * @return Hook identifier
     */
    function hookId() external view returns (bytes32) {
        return keccak256(abi.encodePacked(name));
    }

    /**
     * @notice Returns the human readable name of this hook
     * @return Hook name
     */
    function hookName() external view returns (string memory) {
        return name;
    }

    /**
     * @notice Called before a deposit operation
     * @param token Address of the token
     * @param user Address of the user
     * @param assets Amount of assets to deposit
     * @param receiver Address of the receiver
     * @return result Result of the hook evaluation
     */
    function onBeforeDeposit(address token, address user, uint256 assets, address receiver)
        external
        virtual
        returns (HookOutput memory)
    {
        emit HookCalled("deposit", token, user, assets, receiver);

        return HookOutput({approved: approveOperations, reason: approveOperations ? "" : rejectReason});
    }

    /**
     * @notice Called before a withdraw operation
     * @param token Address of the token
     * @param by Address of the sender
     * @param assets Amount of assets to withdraw
     * @param to Address of the receiver
     * @param owner Address of the owner
     * @return result Result of the hook evaluation
     */
    function onBeforeWithdraw(address token, address by, uint256 assets, address to, address owner)
        external
        virtual
        returns (HookOutput memory)
    {
        emit WithdrawHookCalled(token, by, assets, to, owner);

        return HookOutput({approved: approveOperations, reason: approveOperations ? "" : rejectReason});
    }

    /**
     * @notice Called before a transfer operation
     * @param token Address of the token
     * @param from Address of the sender
     * @param to Address of the receiver
     * @param amount Amount of assets to transfer
     * @return result Result of the hook evaluation
     */
    function onBeforeTransfer(address token, address from, address to, uint256 amount)
        external
        virtual
        returns (HookOutput memory)
    {
        emit TransferHookCalled(token, from, to, amount);

        return HookOutput({approved: approveOperations, reason: approveOperations ? "" : rejectReason});
    }
}
