// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {
    CCIPLocalSimulator,
    IRouterClient
} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

import {BasicMessageReceiver} from "../../../src/test/ccip/BasicMessageReceiver.sol";
import {EncodeExtraArgsOffchain} from "../../../src/test/ccip/utils/EncodeExtraArgsOffchain.sol";

contract HelloWorldBasicMessageReceiverFasterThanFinalityLocalTest is Test {
    uint64 internal s_chainSelector;
    IRouterClient internal s_sourceRouter;
    IRouterClient internal s_destinationRouter;
    EncodeExtraArgsOffchain internal s_encoder;

    address internal s_alice;

    function setUp() public {
        CCIPLocalSimulator simulator = new CCIPLocalSimulator();
        (uint64 chainSelector_, IRouterClient sourceRouter_, IRouterClient destinationRouter_,,,,) = simulator.configuration();

        s_chainSelector = chainSelector_;
        s_sourceRouter = sourceRouter_;
        s_destinationRouter = destinationRouter_;
        s_encoder = new EncodeExtraArgsOffchain();

        s_alice = makeAddr("alice");
        vm.deal(s_alice, 100 ether);
    }

    function test_helloWorldBasicMessageReceiverFasterThanFinality_local() external {
        BasicMessageReceiver receiver = new BasicMessageReceiver(address(s_destinationRouter));

        bytes memory payload = bytes("Hello World");
        uint32 gasLimit = 200_000;
        uint16 blockConfirmations = 1;
        bytes memory extraArgs = s_encoder.encodeV3Basic(gasLimit, blockConfirmations);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(receiver)),
            data: payload,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: extraArgs,
            feeToken: address(0)
        });

        vm.startPrank(s_alice);
        uint256 fee = s_sourceRouter.getFee(s_chainSelector, message);
        bytes32 messageId = s_sourceRouter.ccipSend{value: fee}(s_chainSelector, message);
        vm.stopPrank();

        assertEq(receiver.latestMessageId(), messageId);
        assertEq(receiver.latestSourceChainSelector(), s_chainSelector);
        assertEq(receiver.latestSender(), s_alice);
        assertEq(receiver.latestMessage(), payload);
    }
}
