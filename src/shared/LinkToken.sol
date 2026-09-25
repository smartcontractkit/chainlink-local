// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ERC677} from "@chainlink/contracts/src/v0.8/shared/token/ERC677/ERC677.sol";

/// @title LinkToken
/// @notice This contract implements the ChainLink Token (LINK) using the ERC677 standard.
/// @dev Inherits from the ERC677 token contract and initializes with a fixed total supply and standard token details.
contract LinkToken is ERC677 {
    /// @notice The total supply of LINK tokens.
    uint256 private constant TOTAL_SUPPLY = 10 ** 27;

    /// @notice The name of the LINK token.
    string private constant NAME = "ChainLink Token";

    /// @notice The symbol of the LINK token.
    string private constant SYMBOL = "LINK";

    /**
     * @notice Constructor to initialize the LinkToken contract with a fixed total supply, name, and symbol.
     * @dev Calls the ERC677 constructor with the name and symbol, and then mints the total supply to the contract deployer.
     */
    constructor() ERC677(NAME, SYMBOL) {
        _onCreate();
    }

    /**
     * @notice Hook that is called when this contract is created.
     * @dev Useful to override constructor behaviour in child contracts (e.g., LINK bridge tokens).
     *      The default implementation mints 10**27 tokens to the contract deployer.
     */
    function _onCreate() internal virtual {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
