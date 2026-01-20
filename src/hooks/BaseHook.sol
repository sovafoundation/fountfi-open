// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IHook} from "./IHook.sol";

/**
 * NOTE: For future stateful hooks, consider access control on the hook functions.
 */

/**
 * @title BaseHook
 * @notice Base contract for all hooks
 * @dev This contract is used to implement the IHook interface
 *      and provides a base implementation for all hooks.
 *      It is not meant to be used as a standalone contract.
 */
abstract contract BaseHook is IHook {
    /*//////////////////////////////////////////////////////////////
                            STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Human readable name of the hook
    string public override name;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructor
     * @param _name Human readable name of the hook
     */
    constructor(string memory _name) {
        name = _name;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the unique identifier for this hook
     * @return Hook identifier
     */
    function hookId() external view override returns (bytes32) {
        return keccak256(abi.encodePacked(name, address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                            HOOK LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Called before a deposit operation
     * @return HookOutput Result of the hook evaluation
     */
    function onBeforeDeposit(address, /*token*/ address, /*user*/ uint256, /*assets*/ address /*receiver*/ )
        public
        virtual
        override
        returns (IHook.HookOutput memory)
    {
        return IHook.HookOutput({approved: true, reason: ""});
    }

    /**
     * @notice Called before a withdraw operation
     * @return HookOutput Result of the hook evaluation
     */
    function onBeforeWithdraw(address, /*token*/ address, /*by*/ uint256, /*assets*/ address, /*to*/ address /*owner*/ )
        public
        virtual
        override
        returns (IHook.HookOutput memory)
    {
        return IHook.HookOutput({approved: true, reason: ""});
    }

    /**
     * @notice Called before a transfer operation
     * @return HookOutput Result of the hook evaluation
     */
    function onBeforeTransfer(address, /*token*/ address, /*from*/ address, /*to*/ uint256 /*amount*/ )
        public
        virtual
        override
        returns (IHook.HookOutput memory)
    {
        return IHook.HookOutput({approved: true, reason: ""});
    }
}
