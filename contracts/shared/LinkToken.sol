// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {ERC677} from "@chainlink/contracts-ccip/src/v0.8/shared/token/ERC677/ERC677.sol";

contract LinkToken is ERC677 {
    constructor() ERC677("ChainLink Token", "LINK") {}
}
