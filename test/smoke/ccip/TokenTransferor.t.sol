// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {TokenTransferor} from "../../../src/test/ccip/TokenTransferor.sol";
import {
    CCIPLocalSimulator,
    IRouterClient,
    LinkToken,
    BurnMintERC677Helper
} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";

contract TokenTransferorTest is Test {
    TokenTransferor public tokenTransferor;
    CCIPLocalSimulator public ccipLocalSimulator;

    uint64 chainSelector;
    BurnMintERC677Helper ccipBnM;

    function setUp() public {
        ccipLocalSimulator = new CCIPLocalSimulator();
        (uint64 chainSelector_, IRouterClient sourceRouter,,, LinkToken linkToken, BurnMintERC677Helper ccipBnM_,) =
            ccipLocalSimulator.configuration();

        tokenTransferor = new TokenTransferor(address(sourceRouter), address(linkToken));

        chainSelector = chainSelector_;
        ccipBnM = ccipBnM_;
    }

    function testTokenTransfer() public {
        uint256 amountToSend = 0.001 ether;
        uint256 amountForFees = 1 ether;
        address receiver = msg.sender;

        ccipBnM.drip(address(tokenTransferor));

        ccipLocalSimulator.requestLinkFromFaucet(address(tokenTransferor), amountForFees);

        tokenTransferor.allowlistDestinationChain(chainSelector, true);

        uint256 receiverBalanceBefore = ccipBnM.balanceOf(receiver);
        uint256 tokenTransferorBalanceBefore = ccipBnM.balanceOf(address(tokenTransferor));

        tokenTransferor.transferTokensPayLINK(chainSelector, receiver, address(ccipBnM), amountToSend);

        uint256 receiverBalanceAfter = ccipBnM.balanceOf(receiver);
        uint256 tokenTransferorBalanceAfter = ccipBnM.balanceOf(address(tokenTransferor));

        assertEq(receiverBalanceAfter, receiverBalanceBefore + amountToSend);
        assertEq(tokenTransferorBalanceAfter, tokenTransferorBalanceBefore - amountToSend);
    }
}
