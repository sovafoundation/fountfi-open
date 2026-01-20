// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20} from "solady/tokens/ERC20.sol";
import {Ownable} from "solady/auth/Ownable.sol";

/**
 * @title MockERC20
 * @notice A simple ERC20 token for testing purposes
 */
contract MockERC20 is ERC20, Ownable {
    // Token metadata
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    /**
     * @notice Contract constructor
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param decimals_ Token decimals
     */
    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _initializeOwner(msg.sender);
    }

    /**
     * @notice Returns the name of the token
     * @return Token name
     */
    function name() public view override returns (string memory) {
        return _name;
    }

    /**
     * @notice Returns the symbol of the token
     * @return Token symbol
     */
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /**
     * @notice Returns the decimals of the token
     * @return Token decimals
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Mint tokens to a specified address
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from a specified address
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
