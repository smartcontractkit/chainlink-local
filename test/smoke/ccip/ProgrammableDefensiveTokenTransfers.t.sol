// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {ProgrammableDefensiveTokenTransfers} from "../../../src/test/ccip/ProgrammableDefensiveTokenTransfers.sol";
import {CCIPLocalSimulator, IRouterClient, LinkToken, BurnMintERC677Helper} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";

contract ProgrammableDefensiveTokenTransfersTest is Test {
    ProgrammableDefensiveTokenTransfers public sender;
    ProgrammableDefensiveTokenTransfers public receiver;
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

        sender = new ProgrammableDefensiveTokenTransfers(
            address(sourceRouter),
            address(linkToken)
        );

        receiver = new ProgrammableDefensiveTokenTransfers(
            address(destinationRouter),
            address(linkToken)
        );

        chainSelector = chainSelector_;
        ccipBnM = ccipBnM_;
    }

    function prepareScenario()
        private
        returns (uint256 amountToSend, string memory textToSend)
    {
        amountToSend = 0.001 ether;
        uint256 amountForFees = 1 ether;
        textToSend = "Hello World";

        ccipBnM.drip(address(sender));

        ccipLocalSimulator.requestLinkFromFaucet(
            address(sender),
            amountForFees
        );

        sender.allowlistDestinationChain(chainSelector, true);

        receiver.allowlistSourceChain(chainSelector, true);
        receiver.allowlistSender(address(sender), true);
    }

    function test_regularTransfer() public {
        (uint256 amountToSend, string memory textToSend) = prepareScenario();

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
    }

    function test_tokenRecovery() public {
        (uint256 amountToSend, string memory textToSend) = prepareScenario();

        receiver.setSimRevert(true);

        uint256 senderBalanceBefore = ccipBnM.balanceOf(address(sender));
        uint256 receiverBalanceBefore = ccipBnM.balanceOf(address(receiver));

        bytes32 messageId = sender.sendMessagePayLINK(
            chainSelector,
            address(receiver),
            textToSend,
            address(ccipBnM),
            amountToSend
        );

        ProgrammableDefensiveTokenTransfers.FailedMessage[]
            memory failedMessages = receiver.getFailedMessages(0, 1);

        assertEq(failedMessages[0].messageId, messageId);
        assertEq(
            uint8(failedMessages[0].errorCode),
            uint8(ProgrammableDefensiveTokenTransfers.ErrorCode.FAILED)
        );

        receiver.retryFailedMessage(messageId, msg.sender);

        ProgrammableDefensiveTokenTransfers.FailedMessage[]
            memory failedMessagesAfter = receiver.getFailedMessages(0, 1);
        assertEq(
            uint8(failedMessagesAfter[0].errorCode),
            uint8(ProgrammableDefensiveTokenTransfers.ErrorCode.RESOLVED)
        );

        uint256 senderBalanceAfter = ccipBnM.balanceOf(address(sender));
        uint256 receiverBalanceAfter = ccipBnM.balanceOf(address(receiver));

        assertEq(senderBalanceAfter, senderBalanceBefore - amountToSend);
        assertEq(receiverBalanceAfter, receiverBalanceBefore);
        assertEq(
            ccipBnM.balanceOf(msg.sender),
            receiverBalanceBefore + amountToSend
        );
    }
}
