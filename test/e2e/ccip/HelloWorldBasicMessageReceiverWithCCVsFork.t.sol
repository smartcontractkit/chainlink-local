// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {MockVerifier} from "@chainlink/contracts-ccip/contracts/test/mocks/MockVerifier.sol";

import {BasicMessageReceiverWithCCVs} from "../../../src/test/ccip/BasicMessageReceiverWithCCVs.sol";
import {EncodeExtraArgsOffchain} from "../../../src/test/ccip/utils/EncodeExtraArgsOffchain.sol";

contract HelloWorldBasicMessageReceiverWithCCVsForkTest is Test {
    CCIPLocalSimulatorFork internal s_forkSimulator;
    EncodeExtraArgsOffchain internal s_encoder;
    uint256 internal s_sourceFork;
    uint256 internal s_destinationFork;

    Register.NetworkDetails internal s_sourceNetwork;
    Register.NetworkDetails internal s_destinationNetwork;
    MockVerifier internal s_mockVerifierA;
    MockVerifier internal s_mockVerifierB;

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
        bytes memory verifierResult = abi.encodePacked(bytes4(0x464f524b)); // "FORK"
        s_mockVerifierA = new MockVerifier(verifierResult);
        s_mockVerifierB = new MockVerifier(verifierResult);
        vm.makePersistent(address(s_mockVerifierA));
        vm.makePersistent(address(s_mockVerifierB));

        vm.selectFork(s_destinationFork);
        s_destinationNetwork = s_forkSimulator.getNetworkDetails(block.chainid);

        s_alice = makeAddr("alice");
        vm.selectFork(s_sourceFork);
        vm.deal(s_alice, 10 ether);
    }

    function test_helloWorldBasicMessageReceiverWithCCVs_fork() external {
        vm.selectFork(s_destinationFork);
        BasicMessageReceiverWithCCVs receiver = new BasicMessageReceiverWithCCVs(s_destinationNetwork.routerAddress);

        // Multiple CCV config with a deployable mock verifier.
        address[] memory requiredCCVs = new address[](0);
        address[] memory optionalCCVs = new address[](2);
        optionalCCVs[0] = address(s_mockVerifierA);
        optionalCCVs[1] = address(s_mockVerifierB);

        BasicMessageReceiverWithCCVs.CCVConfigArgs[] memory updates =
            new BasicMessageReceiverWithCCVs.CCVConfigArgs[](1);
        updates[0] = BasicMessageReceiverWithCCVs.CCVConfigArgs({
            requiredCCVs: requiredCCVs,
            optionalCCVs: optionalCCVs,
            sourceChainSelector: s_sourceNetwork.chainSelector,
            optionalThreshold: 1
        });
        receiver.applyCCVConfigUpdates(updates);
        uint16 minBlockDepth = 1;
        receiver.setMinBlockDepth(s_sourceNetwork.chainSelector, minBlockDepth);

        vm.selectFork(s_sourceFork);
        bytes memory payload = bytes("Hello World");

        address[] memory ccvs = new address[](1);
        ccvs[0] = address(s_mockVerifierA);
        bytes[] memory ccvArgs = new bytes[](1);
        ccvArgs[0] = "";
        uint32 gasLimit = 200_000;
        uint16 blockConfirmations = 1;
        bytes memory extraArgs = s_encoder.encodeV3(gasLimit, blockConfirmations, ccvs, ccvArgs, address(0), "", "", "");

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(receiver)),
            data: payload,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: extraArgs,
            feeToken: address(0)
        });

        vm.startPrank(s_alice);
        uint256 fee = IRouterClient(s_sourceNetwork.routerAddress).getFee(s_destinationNetwork.chainSelector, message);
        bytes32 messageId = IRouterClient(s_sourceNetwork.routerAddress).ccipSend{value: fee}(
            s_destinationNetwork.chainSelector, message
        );
        vm.stopPrank();

        s_forkSimulator.switchChainAndRouteMessage(s_destinationFork);

        vm.selectFork(s_destinationFork);
        assertEq(receiver.latestMessageId(), messageId);
        assertEq(receiver.latestSourceChainSelector(), s_sourceNetwork.chainSelector);
        assertEq(receiver.latestSender(), s_alice);
        assertEq(receiver.latestMessage(), payload);
    }
}
