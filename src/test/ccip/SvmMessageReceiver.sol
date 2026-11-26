// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 *
 * Records the latest message a Solana sender delivered. The Solana sender is a 32-byte public key, so it is kept as
 * `bytes`: `abi.decode(message.sender, (address))` would revert for it. `setShouldRevert(true)` makes `ccipReceive`
 * revert, to test the failed execution of a Solana -> EVM message and its retry.
 */
contract SvmMessageReceiver is CCIPReceiver {
    bool public shouldRevert;
    uint256 public messageCount;
    bytes32 public latestMessageId;
    uint64 public latestSourceChainSelector;
    bytes public latestSender;
    bytes public latestData;
    Client.EVMTokenAmount[] internal s_latestTokenAmounts;

    constructor(address router) CCIPReceiver(router) {}

    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }

    function latestTokenAmounts() external view returns (Client.EVMTokenAmount[] memory) {
        return s_latestTokenAmounts;
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        if (shouldRevert) revert("SvmMessageReceiver: told to revert");
        ++messageCount;
        latestMessageId = message.messageId;
        latestSourceChainSelector = message.sourceChainSelector;
        latestSender = message.sender;
        latestData = message.data;
        delete s_latestTokenAmounts;
        for (uint256 i = 0; i < message.destTokenAmounts.length; ++i) {
            s_latestTokenAmounts.push(message.destTokenAmounts[i]);
        }
    }
}
