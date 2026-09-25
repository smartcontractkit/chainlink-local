// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract BasicMessageReceiver is CCIPReceiver {
    bytes32 public latestMessageId;
    uint64 public latestSourceChainSelector;
    address public latestSender;
    bytes public latestMessage;

    event MessageReceived(
        bytes32 latestMessageId, uint64 latestSourceChainSelector, address latestSender, bytes latestMessage
    );

    constructor(address router) CCIPReceiver(router) {}

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        latestMessageId = message.messageId;
        latestSourceChainSelector = message.sourceChainSelector;
        latestSender = abi.decode(message.sender, (address));
        latestMessage = message.data;

        emit MessageReceived(latestMessageId, latestSourceChainSelector, latestSender, latestMessage);
    }
}
