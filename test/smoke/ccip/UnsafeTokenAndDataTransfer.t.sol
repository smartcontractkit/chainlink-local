// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {CCIPSender_Unsafe} from "../../../src/test/ccip/CCIPSender_Unsafe.sol";
import {CCIPReceiver_Unsafe} from "../../../src/test/ccip/CCIPReceiver_Unsafe.sol";
import {CCIPLocalSimulator, IRouterClient, LinkToken, BurnMintERC677Helper} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";

contract UnsafeTokenAndDataTransferTest is Test {
    CCIPSender_Unsafe public sender;
    CCIPReceiver_Unsafe public receiver;

    uint64 chainSelector;
    BurnMintERC677Helper ccipBnM;

    function setUp() public {
        CCIPLocalSimulator ccipLocalSimulator = new CCIPLocalSimulator();

        (
            uint64 chainSelector_,
            IRouterClient sourceRouter_,
            IRouterClient destinationRouter_,
            ,
            LinkToken linkToken_,
            BurnMintERC677Helper ccipBnM_,

        ) = ccipLocalSimulator.configuration();

        chainSelector = chainSelector_;
        ccipBnM = ccipBnM_;
        address sourceRouter = address(sourceRouter_);
        address linkToken = address(linkToken_);
        address destinationRouter = address(destinationRouter_);

        sender = new CCIPSender_Unsafe(linkToken, sourceRouter);
        receiver = new CCIPReceiver_Unsafe(destinationRouter);
    }

    function testSend() public {
        ccipBnM.drip(address(sender)); // 1e18
        assertEq(ccipBnM.totalSupply(), 1 ether);

        string memory textToSend = "Hello World";
        uint256 amountToSend = 100;

        bytes32 messageId = sender.send(
            address(receiver),
            textToSend,
            chainSelector,
            address(ccipBnM),
            amountToSend
        );
        console2.logBytes32(messageId);

        string memory receivedText = receiver.text();

        assertEq(receivedText, textToSend);

        assertEq(ccipBnM.balanceOf(address(sender)), 1 ether - amountToSend);
        assertEq(ccipBnM.balanceOf(address(receiver)), amountToSend);
        assertEq(ccipBnM.totalSupply(), 1 ether);
    }
}
