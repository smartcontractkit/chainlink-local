// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ERC677} from "@chainlink/contracts-ccip/src/v0.8/shared/token/ERC677/ERC677.sol";

contract LinkToken is ERC677 {
    uint private constant TOTAL_SUPPLY = 10 ** 27;
    string private constant NAME = "ChainLink Token";
    string private constant SYMBOL = "LINK";

    constructor() ERC677(NAME, SYMBOL) {
        _onCreate();
    }

    /**
     * @dev Hook that is called when this contract is created.
     * Useful to override constructor behaviour in child contracts (e.g., LINK bridge tokens).
     * @notice Default implementation mints 10**27 tokens to msg.sender
     */
    function _onCreate() internal virtual {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
