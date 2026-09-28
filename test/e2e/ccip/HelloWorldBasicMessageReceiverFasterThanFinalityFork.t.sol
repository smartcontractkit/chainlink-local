// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

import {FinalityCodec} from "@chainlink/contracts-ccip/contracts/libraries/FinalityCodec.sol";

import {BasicMessageReceiver} from "../../../src/test/ccip/BasicMessageReceiver.sol";
import {BasicMessageReceiverWithCCVs} from "../../../src/test/ccip/BasicMessageReceiverWithCCVs.sol";
import {EncodeExtraArgsOffchain} from "../../../src/test/ccip/utils/EncodeExtraArgsOffchain.sol";

contract HelloWorldBasicMessageReceiverFasterThanFinalityForkTest is Test {
    CCIPLocalSimulatorFork internal s_forkSimulator;
    EncodeExtraArgsOffchain internal s_encoder;
    uint256 internal s_sourceFork;
    uint256 internal s_destinationFork;

    Register.NetworkDetails internal s_sourceNetwork;
    Register.NetworkDetails internal s_destinationNetwork;

    address internal s_alice;

    function setUp() public {
        s_sourceFork = vm.createSelectFork(vm.envString("ETHEREUM_SEPOLIA_RPC_URL"));
        s_destinationFork = vm.createFork(vm.envString("ARBITRUM_SEPOLIA_RPC_URL"));

        s_forkSimulator = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(s_forkSimulator));

        s_encoder = new EncodeExtraArgsOffchain();
        vm.makePersistent(address(s_encoder));

        vm.selectFork(s_sourceFork);
        s_sourceNetwork = s_forkSimulator.getNetworkDetails(block.chainid);

        vm.selectFork(s_destinationFork);
        s_destinationNetwork = s_forkSimulator.getNetworkDetails(block.chainid);

        s_alice = makeAddr("alice");
        vm.selectFork(s_sourceFork);
        vm.deal(s_alice, 10 ether);
    }

    /// @dev CCIP 2.0: the destination OffRamp only delivers a Faster-Than-Finality message with data to a receiver
    ///      that opts in through `getCCVsAndFinalityConfig`.
    function test_helloWorldBasicMessageReceiverFasterThanFinality_fork() external {
        uint16 blockDepth = 1;

        vm.selectFork(s_destinationFork);
        BasicMessageReceiverWithCCVs receiver = new BasicMessageReceiverWithCCVs(s_destinationNetwork.routerAddress);
        receiver.setAllowedFinalityConfig(s_sourceNetwork.chainSelector, FinalityCodec._encodeBlockDepth(blockDepth));

        bytes memory payload = bytes("Hello World");
        bytes32 messageId = _sendFasterThanFinality(address(receiver), payload, blockDepth);

        s_forkSimulator.switchChainAndRouteMessage(s_destinationFork);

        vm.selectFork(s_destinationFork);
        assertEq(receiver.latestMessageId(), messageId);
        assertEq(receiver.latestSourceChainSelector(), s_sourceNetwork.chainSelector);
        assertEq(receiver.latestSender(), s_alice);
        assertEq(receiver.latestMessage(), payload);
    }

    /// @dev Production parity: a receiver that does not opt into Faster-Than-Finality only accepts finalized messages,
    ///      so the OffRamp records FAILURE with `InvalidRequestedFinality`. Strict routing (the default) surfaces exactly
    ///      that reason; without strict routing it is recorded in `getMessageStatus`.
    function test_helloWorldFasterThanFinality_notDeliveredToReceiverRequiringFinality_fork() external {
        vm.selectFork(s_destinationFork);
        BasicMessageReceiver receiver = new BasicMessageReceiver(s_destinationNetwork.routerAddress);

        bytes32 messageId = _sendFasterThanFinality(address(receiver), bytes("Hello World"), 1);
        bytes memory finalityRejection = abi.encodeWithSelector(
            FinalityCodec.InvalidRequestedFinality.selector,
            FinalityCodec._encodeBlockDepth(1),
            FinalityCodec.WAIT_FOR_FINALITY_FLAG
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPLocalSimulatorFork.CCIPLocalSimulatorFork__MessageExecutionFailed.selector,
                messageId,
                finalityRejection
            )
        );
        s_forkSimulator.switchChainAndRouteMessage(s_destinationFork);
    }

    function test_helloWorldFasterThanFinality_nonStrict_recordsFinalityRejection_fork() external {
        vm.selectFork(s_destinationFork);
        BasicMessageReceiver receiver = new BasicMessageReceiver(s_destinationNetwork.routerAddress);

        bytes32 messageId = _sendFasterThanFinality(address(receiver), bytes("Hello World"), 1);
        s_forkSimulator.setStrictRouting(false);
        s_forkSimulator.switchChainAndRouteMessage(s_destinationFork);

        vm.selectFork(s_destinationFork);
        assertEq(receiver.latestMessageId(), bytes32(0));
        (CCIPLocalSimulatorFork.MessageStatus status, bytes memory reason) = s_forkSimulator.getMessageStatus(messageId);
        assertEq(uint8(status), uint8(CCIPLocalSimulatorFork.MessageStatus.FAILED));
        assertEq(
            reason,
            abi.encodeWithSelector(
                FinalityCodec.InvalidRequestedFinality.selector,
                FinalityCodec._encodeBlockDepth(1),
                FinalityCodec.WAIT_FOR_FINALITY_FLAG
            )
        );
    }

    function _sendFasterThanFinality(address receiver, bytes memory payload, uint16 blockDepth)
        internal
        returns (bytes32 messageId)
    {
        vm.selectFork(s_sourceFork);
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: payload,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: s_encoder.encodeV3BasicBlockDepth(200_000, blockDepth),
            feeToken: address(0)
        });

        vm.startPrank(s_alice);
        uint256 fee = IRouterClient(s_sourceNetwork.routerAddress).getFee(s_destinationNetwork.chainSelector, message);
        messageId = IRouterClient(s_sourceNetwork.routerAddress).ccipSend{value: fee}(
            s_destinationNetwork.chainSelector, message
        );
        vm.stopPrank();
    }
}
