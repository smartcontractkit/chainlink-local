// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CCIPLocalSimulator, IRouterClient} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {FinalityCodec} from "@chainlink/contracts-ccip/contracts/libraries/FinalityCodec.sol";
import {MockVerifier} from "@chainlink/contracts-ccip/contracts/test/mocks/MockVerifier.sol";

import {BasicMessageReceiverWithCCVs} from "../../../src/test/ccip/BasicMessageReceiverWithCCVs.sol";
import {EncodeExtraArgsOffchain} from "../../../src/test/ccip/utils/EncodeExtraArgsOffchain.sol";

contract HelloWorldBasicMessageReceiverWithCCVsLocalTest is Test {
    uint64 internal s_chainSelector;
    IRouterClient internal s_sourceRouter;
    IRouterClient internal s_destinationRouter;
    EncodeExtraArgsOffchain internal s_encoder;
    MockVerifier internal s_mockVerifierA;
    MockVerifier internal s_mockVerifierB;
    MockVerifier internal s_mockVerifierC;

    address internal s_alice;

    function setUp() public {
        CCIPLocalSimulator simulator = new CCIPLocalSimulator();
        (uint64 chainSelector_, IRouterClient sourceRouter_, IRouterClient destinationRouter_,,,,) =
            simulator.configuration();

        s_chainSelector = chainSelector_;
        s_sourceRouter = sourceRouter_;
        s_destinationRouter = destinationRouter_;
        s_encoder = new EncodeExtraArgsOffchain();
        bytes memory verifierResult = abi.encodePacked(bytes4(0x464f524b)); // "FORK"
        s_mockVerifierA = new MockVerifier(verifierResult);
        s_mockVerifierB = new MockVerifier(verifierResult);
        s_mockVerifierC = new MockVerifier(verifierResult);

        s_alice = makeAddr("alice");
        vm.deal(s_alice, 100 ether);
    }

    function test_helloWorldBasicMessageReceiverWithCCVs_local() external {
        BasicMessageReceiverWithCCVs receiver = new BasicMessageReceiverWithCCVs(address(s_destinationRouter));

        address[] memory requiredCCVs = new address[](1);
        requiredCCVs[0] = address(s_mockVerifierA);
        address[] memory optionalCCVs = new address[](2);
        optionalCCVs[0] = address(s_mockVerifierB);
        optionalCCVs[1] = address(s_mockVerifierC);

        BasicMessageReceiverWithCCVs.CCVConfigArgs[] memory updates =
            new BasicMessageReceiverWithCCVs.CCVConfigArgs[](1);
        updates[0] = BasicMessageReceiverWithCCVs.CCVConfigArgs({
            requiredCCVs: requiredCCVs,
            optionalCCVs: optionalCCVs,
            sourceChainSelector: s_chainSelector,
            optionalThreshold: 1
        });
        receiver.applyCCVConfigUpdates(updates);
        uint16 minBlockDepth = 1;
        receiver.setAllowedFinalityConfig(s_chainSelector, FinalityCodec._encodeBlockDepth(minBlockDepth));

        address[] memory ccvs = new address[](3);
        ccvs[0] = address(s_mockVerifierA);
        ccvs[1] = address(s_mockVerifierB);
        ccvs[2] = address(s_mockVerifierC);
        bytes[] memory ccvArgs = new bytes[](3);

        bytes memory payload = bytes("Hello World");
        uint32 gasLimit = 200_000;
        uint16 blockConfirmations = 1;
        bytes memory extraArgs = s_encoder.encodeV3(
            gasLimit, FinalityCodec._encodeBlockDepth(blockConfirmations), ccvs, ccvArgs, address(0), "", "", ""
        );

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

    function test_getCCVsAndFinalityConfigReflectsUpdates_local() external {
        BasicMessageReceiverWithCCVs receiver = new BasicMessageReceiverWithCCVs(address(s_destinationRouter));

        address[] memory requiredCCVs = new address[](1);
        requiredCCVs[0] = address(s_mockVerifierA);
        address[] memory optionalCCVs = new address[](2);
        optionalCCVs[0] = address(s_mockVerifierB);
        optionalCCVs[1] = address(s_mockVerifierC);

        BasicMessageReceiverWithCCVs.CCVConfigArgs[] memory updates =
            new BasicMessageReceiverWithCCVs.CCVConfigArgs[](1);
        updates[0] = BasicMessageReceiverWithCCVs.CCVConfigArgs({
            requiredCCVs: requiredCCVs,
            optionalCCVs: optionalCCVs,
            sourceChainSelector: s_chainSelector,
            optionalThreshold: 1
        });
        receiver.applyCCVConfigUpdates(updates);

        (
            address[] memory initialRequired,
            address[] memory initialOptional,
            uint8 initialThreshold,
            bytes4 initialFinalityConfig
        ) = receiver.getCCVsAndFinalityConfig(s_chainSelector, "");

        assertEq(initialRequired.length, 1);
        assertEq(initialRequired[0], address(s_mockVerifierA));
        assertEq(initialOptional.length, 2);
        assertEq(initialOptional[0], address(s_mockVerifierB));
        assertEq(initialOptional[1], address(s_mockVerifierC));
        assertEq(initialThreshold, 1);
        assertEq(initialFinalityConfig, FinalityCodec.WAIT_FOR_FINALITY_FLAG);

        uint16 minBlockDepth = 1;
        receiver.setAllowedFinalityConfig(s_chainSelector, FinalityCodec._encodeBlockDepth(minBlockDepth));
        (,,, bytes4 updatedFinalityConfig) = receiver.getCCVsAndFinalityConfig(s_chainSelector, "");
        assertEq(updatedFinalityConfig, FinalityCodec._encodeBlockDepth(minBlockDepth));
    }

    function test_setAllowedFinalityConfig_RevertIfNotOwner_local() external {
        BasicMessageReceiverWithCCVs receiver = new BasicMessageReceiverWithCCVs(address(s_destinationRouter));
        uint16 minBlockDepth = 1;

        vm.prank(s_alice);
        vm.expectRevert();
        receiver.setAllowedFinalityConfig(s_chainSelector, FinalityCodec._encodeBlockDepth(minBlockDepth));
    }
}
