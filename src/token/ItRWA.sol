// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

/**
 * @title ItRWA
 * @notice Interface for Tokenized Real World Asset (tRWA)
 * @dev Defines the interface with all events and errors for the tRWA contract
 *      This is an extension interface (does not duplicate ERC4626 methods)
 */
interface ItRWA {
    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidAddress();
    error AssetMismatch();
    error RuleCheckFailed(string reason);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the address of the strategy
    function strategy() external view returns (address);

    /// @notice Returns the address of the underlying asset
    function asset() external view returns (address);

    // Note: Standard ERC4626 operations are defined in the ERC4626 interface
    // and are not redefined here to avoid conflicts
}
