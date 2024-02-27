// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {WETH9} from "../shared/WETH9.sol";
import {LinkToken} from "../shared/LinkToken.sol";
import {BurnMintERC677Helper} from "../ccip/BurnMintERC677Helper.sol";
import {Router} from "@chainlink/contracts-ccip/src/v0.8/ccip/Router.sol";

interface ICCIPLocalSimulator {
    function DOCUMENTATION()
        external
        view
        returns (
            uint64 chainSelector_,
            Router sourceRouter_,
            Router destinationRouter_,
            WETH9 wrappedNative_,
            LinkToken linkToken_,
            BurnMintERC677Helper ccipBnM_,
            BurnMintERC677Helper ccipLnM_
        );
}
