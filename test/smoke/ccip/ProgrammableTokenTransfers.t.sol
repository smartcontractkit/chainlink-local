// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {ProgrammableTokenTransfers} from "../../../src/test/ccip/ProgrammableTokenTransfers.sol";
import {CCIPLocalSimulator, IRouterClient, LinkToken, BurnMintERC677Helper} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";

contract ProgrammableTokenTransfersTest is Test {
    ProgrammableTokenTransfers public sender;
    ProgrammableTokenTransfers public receiver;
    CCIPLocalSimulator public ccipLocalSimulator;

    uint64 chainSelector;
    BurnMintERC677Helper ccipBnM;

    function setUp() public {
        ccipLocalSimulator = new CCIPLocalSimulator();
        (
            uint64 chainSelector_,
            IRouterClient sourceRouter,
            IRouterClient destinationRouter,
            ,
            LinkToken linkToken,
            BurnMintERC677Helper ccipBnM_,

        ) = ccipLocalSimulator.configuration();

        sender = new ProgrammableTokenTransfers(
            address(sourceRouter),
            address(linkToken)
        );

        receiver = new ProgrammableTokenTransfers(
            address(destinationRouter),
            address(linkToken)
        );

        chainSelector = chainSelector_;
        ccipBnM = ccipBnM_;
    }

    function testProgrammableTokenTransfer() public {
        uint256 amountToSend = 0.001 ether;
        uint256 amountForFees = 1 ether;
        string memory textToSend = "Hello World";

        ccipBnM.drip(address(sender));

        ccipLocalSimulator.requestLinkFromFaucet(
            address(sender),
            amountForFees
        );

        sender.allowlistDestinationChain(chainSelector, true);

        receiver.allowlistSourceChain(chainSelector, true);
        receiver.allowlistSender(address(sender), true);

        uint256 senderBalanceBefore = ccipBnM.balanceOf(address(sender));
        uint256 receiverBalanceBefore = ccipBnM.balanceOf(address(receiver));

        bytes32 messageId = sender.sendMessagePayLINK(
            chainSelector,
            address(receiver),
            textToSend,
            address(ccipBnM),
            amountToSend
        );

        (
            bytes32 _messageId,
            string memory _text,
            address _tokenAddress,
            uint256 _tokenAmount
        ) = receiver.getLastReceivedMessageDetails();

        assertEq(_messageId, messageId);
        assertEq(_text, textToSend);
        assertEq(_tokenAddress, address(ccipBnM));
        assertEq(_tokenAmount, amountToSend);

        uint256 senderBalanceAfter = ccipBnM.balanceOf(address(sender));
        uint256 receiverBalanceAfter = ccipBnM.balanceOf(address(receiver));

        assertEq(senderBalanceAfter, senderBalanceBefore - amountToSend);
        assertEq(receiverBalanceAfter, receiverBalanceBefore + amountToSend);
    }
}
