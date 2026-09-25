// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, Vm} from "forge-std/Test.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {MessageV1Codec} from "@chainlink/contracts-ccip/contracts/libraries/MessageV1Codec.sol";
import {FinalityCodec} from "@chainlink/contracts-ccip/contracts/libraries/FinalityCodec.sol";
import {CCIPLocalSimulatorFork} from "../../../src/ccip/CCIPLocalSimulatorFork.sol";
import {CCIPForkAdapterTypes} from "../../../src/ccip/adapters/CCIPForkAdapterTypes.sol";
import {CCIPForkAdapterV1dot6} from "../../../src/ccip/adapters/CCIPForkAdapterV1dot6.sol";
import {CCIPForkAdapterPreV1dot6} from "../../../src/ccip/adapters/CCIPForkAdapterPreV1dot6.sol";
import {CCIPForkAdapterV2, IMessageV1Decoder} from "../../../src/ccip/adapters/CCIPForkAdapterV2.sol";
import {MessageV1CodecDecoder} from "../../../src/ccip/adapters/MessageV1CodecDecoder.sol";

contract MockV1dot6OffRamp {
    address internal s_receiver;
    address internal s_destToken;
    bytes internal s_sourcePoolAddress;
    uint32 internal s_gasOverride;

    function executeSingleMessage(
        CCIPForkAdapterTypes.V1dot6Any2EVMRampMessage calldata message,
        bytes[] calldata,
        uint32[] calldata tokenGasOverrides
    ) external {
        s_receiver = message.receiver;
        s_destToken = message.tokenAmounts[0].destTokenAddress;
        s_sourcePoolAddress = message.tokenAmounts[0].sourcePoolAddress;
        s_gasOverride = tokenGasOverrides[0];
    }

    function receiver() external view returns (address) {
        return s_receiver;
    }

    function destToken() external view returns (address) {
        return s_destToken;
    }

    function sourcePoolAddress() external view returns (bytes memory) {
        return s_sourcePoolAddress;
    }

    function gasOverride() external view returns (uint32) {
        return s_gasOverride;
    }
}

contract MockPreV1dot6OffRamp {
    uint256 internal s_numOverrides;
    uint32 internal s_gasOverride = type(uint32).max;

    function executeSingleMessage(
        CCIPForkAdapterTypes.PreV1dot6Message calldata,
        bytes[] calldata,
        uint32[] calldata tokenGasOverrides
    ) external {
        s_numOverrides = tokenGasOverrides.length;
        s_gasOverride = tokenGasOverrides[0];
    }

    function numOverrides() external view returns (uint256) {
        return s_numOverrides;
    }

    function gasOverride() external view returns (uint32) {
        return s_gasOverride;
    }
}

contract MockV2OffRamp {
    address[] internal s_requiredCCVs;
    address[] internal s_optionalCCVs;
    uint8 internal s_threshold;

    bytes32 internal s_messageId;
    uint256 internal s_numCCVs;
    uint256 internal s_numVerifierResults;
    uint256 internal s_executionCount;
    address internal s_offRampAddressFromMessage;

    constructor(address[] memory requiredCCVs, address[] memory optionalCCVs, uint8 threshold) {
        s_requiredCCVs = requiredCCVs;
        s_optionalCCVs = optionalCCVs;
        s_threshold = threshold;
    }

    function getCCVsForMessage(bytes calldata)
        external
        view
        returns (address[] memory requiredCCVs, address[] memory optionalCCVs, uint8 threshold)
    {
        return (s_requiredCCVs, s_optionalCCVs, s_threshold);
    }

    function executeSingleMessage(
        MessageV1Codec.MessageV1 calldata message,
        bytes32 messageId_,
        address[] calldata ccvs,
        bytes[] calldata verifierResults,
        uint32
    ) external {
        s_messageId = messageId_;
        s_numCCVs = ccvs.length;
        s_numVerifierResults = verifierResults.length;
        s_executionCount += 1;
        s_offRampAddressFromMessage = _decodeAddress(message.offRampAddress);
    }

    function messageId() external view returns (bytes32) {
        return s_messageId;
    }

    function numCCVs() external view returns (uint256) {
        return s_numCCVs;
    }

    function numVerifierResults() external view returns (uint256) {
        return s_numVerifierResults;
    }

    function offRampAddressFromMessage() external view returns (address) {
        return s_offRampAddressFromMessage;
    }

    function executionCount() external view returns (uint256) {
        return s_executionCount;
    }

    function _decodeAddress(bytes calldata encodedAddress) internal pure returns (address decodedAddress) {
        if (encodedAddress.length == 32) {
            return abi.decode(encodedAddress, (address));
        }
        if (encodedAddress.length == 20) {
            assembly {
                decodedAddress := shr(96, calldataload(encodedAddress.offset))
            }
            return decodedAddress;
        }

        revert("invalid address encoding");
    }
}

contract CCIPLocalSimulatorForkHarness is CCIPLocalSimulatorFork {
    /// @dev These tests cover the opt-in local-codec V2 path, which was the default before OFFRAMP_DERIVED.
    constructor() {
        s_v2VerificationMode = V2VerificationMode.HYBRID;
    }

    function routeV2Message(Vm.Log memory entry) external returns (bool attempted) {
        // The local-codec path reads the source chain selector from the decoded message.
        return _routeV2Message(entry, 0, false);
    }
}

contract MockFailingVerifier {
    error InvalidVerifierResults();

    function verifyMessage(MessageV1Codec.MessageV1 memory, bytes32, bytes memory) external pure {
        revert InvalidVerifierResults();
    }
}

contract MockVersionedResolver {
    struct InboundImplementationArgs {
        bytes4 version;
        address verifier;
    }

    address private immutable i_owner;
    mapping(bytes4 version => address verifier) private s_inboundImplementations;

    constructor(bytes4 initialVersion, address initialVerifier) {
        i_owner = msg.sender;
        s_inboundImplementations[initialVersion] = initialVerifier;
    }

    function owner() external view returns (address) {
        return i_owner;
    }

    function applyInboundImplementationUpdates(InboundImplementationArgs[] calldata implementations) external {
        require(msg.sender == i_owner, "only owner");
        for (uint256 i; i < implementations.length; ++i) {
            s_inboundImplementations[implementations[i].version] = implementations[i].verifier;
        }
    }

    function getInboundImplementation(bytes calldata verifierResults) external view returns (address) {
        require(verifierResults.length >= 4, "invalid verifierResults");
        return s_inboundImplementations[bytes4(verifierResults[:4])];
    }
}

interface ITestResolver {
    function getInboundImplementation(bytes calldata verifierResults) external view returns (address);
}

interface ITestVerifier {
    function verifyMessage(MessageV1Codec.MessageV1 memory message, bytes32 messageId, bytes memory verifierResults)
        external;
}

contract MockV2OffRampWithVerifier {
    address[] internal s_requiredCCVs;
    uint256 internal s_successfulExecutions;

    constructor(address resolver) {
        s_requiredCCVs = new address[](1);
        s_requiredCCVs[0] = resolver;
    }

    function getCCVsForMessage(bytes calldata)
        external
        view
        returns (address[] memory requiredCCVs, address[] memory optionalCCVs, uint8 threshold)
    {
        return (s_requiredCCVs, new address[](0), 0);
    }

    function executeSingleMessage(
        MessageV1Codec.MessageV1 calldata message,
        bytes32 messageId,
        address[] calldata ccvs,
        bytes[] calldata verifierResults,
        uint32
    ) external {
        require(msg.sender == address(this), "can only self-call");
        require(ccvs.length == 1 && verifierResults.length == 1, "unexpected ccv input");

        address verifierImpl = ITestResolver(ccvs[0]).getInboundImplementation(verifierResults[0]);
        require(verifierImpl != address(0), "missing verifier impl");

        ITestVerifier(verifierImpl).verifyMessage(message, messageId, verifierResults[0]);
        s_successfulExecutions += 1;
    }

    function successfulExecutions() external view returns (uint256) {
        return s_successfulExecutions;
    }
}

contract CCIPForkAdaptersUnitTest is Test {
    function test_v1dot6AdapterDecodesAbiEncodedReceiverAndDestTokenAddress() public {
        MockV1dot6OffRamp offRamp = new MockV1dot6OffRamp();

        address expectedReceiver = makeAddr("receiver");
        address expectedDestToken = makeAddr("destToken");
        address expectedSourcePool = makeAddr("sourcePool");
        uint32 expectedGasLimit = 555_555;

        CCIPForkAdapterTypes.V1dot6EVM2AnyTokenTransfer[] memory tokenTransfers =
            new CCIPForkAdapterTypes.V1dot6EVM2AnyTokenTransfer[](1);
        tokenTransfers[0] = CCIPForkAdapterTypes.V1dot6EVM2AnyTokenTransfer({
            sourcePoolAddress: expectedSourcePool,
            destTokenAddress: abi.encode(expectedDestToken),
            extraData: "",
            amount: 1,
            destExecData: abi.encode(expectedGasLimit)
        });

        CCIPForkAdapterTypes.V1dot6EVM2AnyRampMessage memory message = CCIPForkAdapterTypes.V1dot6EVM2AnyRampMessage({
            header: CCIPForkAdapterTypes.V1dot6RampMessageHeader({
                messageId: keccak256("m"), sourceChainSelector: 1, destChainSelector: 2, sequenceNumber: 3, nonce: 4
            }),
            sender: makeAddr("sender"),
            data: "hello",
            receiver: abi.encode(expectedReceiver),
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({gasLimit: expectedGasLimit, allowOutOfOrderExecution: false})
            ),
            feeToken: address(0),
            feeTokenAmount: 0,
            feeValueJuels: 0,
            tokenAmounts: tokenTransfers
        });

        (bool success,) = CCIPForkAdapterV1dot6.execute(message, address(offRamp));
        assertTrue(success);

        assertEq(offRamp.receiver(), expectedReceiver);
        assertEq(offRamp.destToken(), expectedDestToken);
        assertEq(abi.decode(offRamp.sourcePoolAddress(), (address)), expectedSourcePool);
        // A zero token gas override keeps the source-stamped `destGasAmount` (OffRamp only overrides when non-zero).
        assertEq(offRamp.gasOverride(), 0);
    }

    /// @dev EVM2EVMOffRamp 1.5 only overrides `destGasAmount` with a non-zero value, so the adapter must pass zeros.
    function test_preV1dot6AdapterPassesZeroTokenGasOverrides() public {
        MockPreV1dot6OffRamp offRamp = new MockPreV1dot6OffRamp();

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: makeAddr("token"), amount: 1});
        CCIPForkAdapterTypes.PreV1dot6Message memory message;
        message.receiver = makeAddr("receiver");
        message.gasLimit = 555_555;
        message.tokenAmounts = tokenAmounts;
        message.sourceTokenData = new bytes[](1);

        (bool success,) = CCIPForkAdapterPreV1dot6.execute(address(offRamp), message);
        assertTrue(success);
        assertEq(offRamp.numOverrides(), 1);
        assertEq(offRamp.gasOverride(), 0);
    }

    function test_v2AdapterDecodesEventAndRoutesUsingVerifierBlobs() public {
        address ccv1 = makeAddr("ccv1");
        address ccv2 = makeAddr("ccv2");

        address[] memory requiredCCVs = new address[](1);
        requiredCCVs[0] = ccv1;
        address[] memory optionalCCVs = new address[](1);
        optionalCCVs[0] = ccv2;

        // required=[ccv1], optional=[ccv2], threshold=1: the OffRamp needs ccv1 plus ccv2. (A threshold above the number
        // of optional CCVs is rejected by the OffRamp with `InvalidOptionalThreshold`.)
        MockV2OffRamp offRamp = new MockV2OffRamp(requiredCCVs, optionalCCVs, 1);
        MessageV1CodecDecoder decoder = new MessageV1CodecDecoder();

        MessageV1Codec.MessageV1 memory message = MessageV1Codec.MessageV1({
            sourceChainSelector: 111,
            destChainSelector: 222,
            messageNumber: 1,
            executionGasLimit: 400_000,
            ccipReceiveGasLimit: 300_000,
            finality: FinalityCodec._encodeBlockDepth(2),
            ccvAndExecutorHash: bytes32(0),
            onRampAddress: abi.encode(makeAddr("onRamp")),
            offRampAddress: abi.encodePacked(address(offRamp)),
            sender: abi.encode(makeAddr("sender")),
            receiver: abi.encodePacked(makeAddr("receiver")),
            destBlob: "",
            tokenTransfer: new MessageV1Codec.TokenTransferV1[](0),
            data: "payload"
        });

        bytes memory encodedMessage = MessageV1Codec._encodeMessageV1(message);
        bytes32 messageId = keccak256(encodedMessage);

        bytes[] memory verifierBlobs = new bytes[](2);
        verifierBlobs[0] = hex"1234";
        verifierBlobs[1] = hex"5678";

        CCIPForkAdapterTypes.V2Receipt[] memory receipts = new CCIPForkAdapterTypes.V2Receipt[](2);
        receipts[0] = CCIPForkAdapterTypes.V2Receipt({
            issuer: ccv1, destGasLimit: 10_000, destBytesOverhead: 32, feeTokenAmount: 1, extraArgs: hex""
        });
        receipts[1] = CCIPForkAdapterTypes.V2Receipt({
            issuer: ccv2, destGasLimit: 10_000, destBytesOverhead: 32, feeTokenAmount: 1, extraArgs: hex""
        });
        bytes memory eventData = abi.encode(address(0x1), uint256(0), encodedMessage, receipts, verifierBlobs);

        bytes32[] memory topics = new bytes32[](4);
        topics[0] = CCIPForkAdapterV2.eventSelector();
        topics[1] = bytes32(uint256(222));
        topics[2] = bytes32(uint256(uint160(makeAddr("sender"))));
        topics[3] = messageId;

        CCIPForkAdapterV2.DecodedMessage memory decodedMessage =
            CCIPForkAdapterV2.decodeMessage(topics, eventData, IMessageV1Decoder(address(decoder)));

        assertEq(decodedMessage.messageId, messageId);
        assertEq(decodedMessage.message.sourceChainSelector, 111);
        assertEq(CCIPForkAdapterV2.extractOffRampAddress(decodedMessage), address(offRamp));

        (address[] memory ccvs, bytes[] memory verifierResults) =
            CCIPForkAdapterV2.deriveVerificationInputs(address(offRamp), decodedMessage);
        assertEq(ccvs.length, 2);
        assertEq(verifierResults.length, 2);
        assertEq(verifierResults[0], verifierBlobs[0]);
        assertEq(verifierResults[1], verifierBlobs[1]);

        (bool success,) = CCIPForkAdapterV2.execute(
            address(offRamp), decodedMessage.message, decodedMessage.messageId, ccvs, verifierResults
        );
        assertTrue(success);

        assertEq(offRamp.messageId(), messageId);
        assertEq(offRamp.numCCVs(), 2);
        assertEq(offRamp.numVerifierResults(), 2);
        assertEq(offRamp.offRampAddressFromMessage(), address(offRamp));
    }

    function test_routeV2MessageRetriesWithSyntheticVerifierInputsWhenProofsFail() public {
        bytes4 failingVersion = 0x11111111;
        MockFailingVerifier failingVerifier = new MockFailingVerifier();
        MockVersionedResolver resolver = new MockVersionedResolver(failingVersion, address(failingVerifier));
        MockV2OffRampWithVerifier offRamp = new MockV2OffRampWithVerifier(address(resolver));

        MessageV1CodecDecoder decoder = new MessageV1CodecDecoder();
        CCIPLocalSimulatorForkHarness simulator = new CCIPLocalSimulatorForkHarness();

        MessageV1Codec.MessageV1 memory message = MessageV1Codec.MessageV1({
            sourceChainSelector: 111,
            destChainSelector: 222,
            messageNumber: 1,
            executionGasLimit: 400_000,
            ccipReceiveGasLimit: 300_000,
            finality: FinalityCodec._encodeBlockDepth(2),
            ccvAndExecutorHash: bytes32(0),
            onRampAddress: abi.encode(makeAddr("onRamp")),
            offRampAddress: abi.encodePacked(address(offRamp)),
            sender: abi.encode(makeAddr("sender")),
            receiver: abi.encodePacked(makeAddr("receiver")),
            destBlob: "",
            tokenTransfer: new MessageV1Codec.TokenTransferV1[](0),
            data: "payload"
        });

        bytes memory encodedMessage = MessageV1Codec._encodeMessageV1(message);
        bytes32 messageId = keccak256(encodedMessage);

        bytes[] memory verifierBlobs = new bytes[](1);
        verifierBlobs[0] = abi.encodePacked(failingVersion);

        CCIPForkAdapterTypes.V2Receipt[] memory receipts = new CCIPForkAdapterTypes.V2Receipt[](1);
        receipts[0] = CCIPForkAdapterTypes.V2Receipt({
            issuer: address(resolver), destGasLimit: 10_000, destBytesOverhead: 32, feeTokenAmount: 1, extraArgs: hex""
        });
        bytes memory eventData = abi.encode(address(0x1), uint256(0), encodedMessage, receipts, verifierBlobs);

        bytes32[] memory topics = new bytes32[](4);
        topics[0] = CCIPForkAdapterV2.eventSelector();
        topics[1] = bytes32(uint256(222));
        topics[2] = bytes32(uint256(uint160(makeAddr("sender"))));
        topics[3] = messageId;

        Vm.Log memory entry;
        entry.topics = topics;
        entry.data = eventData;
        entry.emitter = makeAddr("onRampEmitter");
        bool attempted = simulator.routeV2Message(entry);

        assertTrue(attempted);
        assertEq(offRamp.successfulExecutions(), 1);

        address syntheticImpl = resolver.getInboundImplementation(hex"464f524b");
        assertTrue(syntheticImpl != address(0));

        CCIPForkAdapterV2.DecodedMessage memory decodedMessage =
            CCIPForkAdapterV2.decodeMessage(topics, eventData, IMessageV1Decoder(address(decoder)));
        assertEq(decodedMessage.messageId, messageId);
    }

    function test_routeV2MessageQueuesNoExecAndAllowsManualExecution() public {
        address[] memory requiredCCVs = new address[](0);
        address[] memory optionalCCVs = new address[](0);
        MockV2OffRamp offRamp = new MockV2OffRamp(requiredCCVs, optionalCCVs, 0);
        CCIPLocalSimulatorForkHarness simulator = new CCIPLocalSimulatorForkHarness();

        MessageV1Codec.MessageV1 memory message = MessageV1Codec.MessageV1({
            sourceChainSelector: 111,
            destChainSelector: 222,
            messageNumber: 1,
            executionGasLimit: 400_000,
            ccipReceiveGasLimit: 300_000,
            finality: FinalityCodec._encodeBlockDepth(2),
            ccvAndExecutorHash: bytes32(0),
            onRampAddress: abi.encode(makeAddr("onRamp")),
            offRampAddress: abi.encodePacked(address(offRamp)),
            sender: abi.encode(makeAddr("sender")),
            receiver: abi.encodePacked(makeAddr("receiver")),
            destBlob: "",
            tokenTransfer: new MessageV1Codec.TokenTransferV1[](0),
            data: "payload"
        });

        bytes memory encodedMessage = MessageV1Codec._encodeMessageV1(message);
        bytes32 messageId = keccak256(encodedMessage);

        CCIPForkAdapterTypes.V2Receipt[] memory receipts = new CCIPForkAdapterTypes.V2Receipt[](2);
        receipts[0] = CCIPForkAdapterTypes.V2Receipt({
            issuer: Client.NO_EXECUTION_ADDRESS,
            destGasLimit: 10_000,
            destBytesOverhead: 32,
            feeTokenAmount: 0,
            extraArgs: hex""
        });
        receipts[1] = CCIPForkAdapterTypes.V2Receipt({
            issuer: makeAddr("router"), destGasLimit: 0, destBytesOverhead: 0, feeTokenAmount: 1, extraArgs: hex""
        });
        bytes memory eventData = abi.encode(address(0x1), uint256(0), encodedMessage, receipts, new bytes[](0));

        bytes32[] memory topics = new bytes32[](4);
        topics[0] = CCIPForkAdapterV2.eventSelector();
        topics[1] = bytes32(uint256(222));
        topics[2] = bytes32(uint256(uint160(makeAddr("sender"))));
        topics[3] = messageId;

        Vm.Log memory entry;
        entry.topics = topics;
        entry.data = eventData;
        entry.emitter = makeAddr("onRampEmitter");

        bool attempted = simulator.routeV2Message(entry);
        assertTrue(attempted);
        assertEq(offRamp.executionCount(), 0);

        bytes32[] memory pendingMessageIds = simulator.getPendingV2MessageIds();
        assertEq(pendingMessageIds.length, 1);
        assertEq(pendingMessageIds[0], messageId);
        assertTrue(simulator.isPendingV2Message(messageId));

        bool manualAttempted = simulator.executePendingV2Message(messageId);
        assertTrue(manualAttempted);
        assertEq(offRamp.executionCount(), 1);
        assertFalse(simulator.isPendingV2Message(messageId));
    }

    function test_v2VerificationModeStrictFailsWhileSyntheticOnlySucceeds() public {
        bytes4 failingVersion = 0x11111111;
        MockFailingVerifier failingVerifier = new MockFailingVerifier();
        MockVersionedResolver resolver = new MockVersionedResolver(failingVersion, address(failingVerifier));
        MockV2OffRampWithVerifier offRamp = new MockV2OffRampWithVerifier(address(resolver));

        MessageV1Codec.MessageV1 memory message = MessageV1Codec.MessageV1({
            sourceChainSelector: 111,
            destChainSelector: 222,
            messageNumber: 1,
            executionGasLimit: 400_000,
            ccipReceiveGasLimit: 300_000,
            finality: FinalityCodec._encodeBlockDepth(2),
            ccvAndExecutorHash: bytes32(0),
            onRampAddress: abi.encode(makeAddr("onRamp")),
            offRampAddress: abi.encodePacked(address(offRamp)),
            sender: abi.encode(makeAddr("sender")),
            receiver: abi.encodePacked(makeAddr("receiver")),
            destBlob: "",
            tokenTransfer: new MessageV1Codec.TokenTransferV1[](0),
            data: "payload"
        });

        bytes memory encodedMessage = MessageV1Codec._encodeMessageV1(message);
        bytes32 messageId = keccak256(encodedMessage);

        bytes[] memory verifierBlobs = new bytes[](1);
        verifierBlobs[0] = abi.encodePacked(failingVersion);

        CCIPForkAdapterTypes.V2Receipt[] memory receipts = new CCIPForkAdapterTypes.V2Receipt[](1);
        receipts[0] = CCIPForkAdapterTypes.V2Receipt({
            issuer: address(resolver), destGasLimit: 10_000, destBytesOverhead: 32, feeTokenAmount: 1, extraArgs: hex""
        });
        bytes memory eventData = abi.encode(address(0x1), uint256(0), encodedMessage, receipts, verifierBlobs);

        bytes32[] memory topics = new bytes32[](4);
        topics[0] = CCIPForkAdapterV2.eventSelector();
        topics[1] = bytes32(uint256(222));
        topics[2] = bytes32(uint256(uint160(makeAddr("sender"))));
        topics[3] = messageId;

        Vm.Log memory entry;
        entry.topics = topics;
        entry.data = eventData;
        entry.emitter = makeAddr("onRampEmitter");

        CCIPLocalSimulatorForkHarness strictSimulator = new CCIPLocalSimulatorForkHarness();
        strictSimulator.setV2VerificationMode(CCIPLocalSimulatorFork.V2VerificationMode.STRICT);
        // Strict routing (default): the rejected proofs surface as a revert instead of a silent non-delivery.
        vm.expectPartialRevert(CCIPLocalSimulatorFork.CCIPLocalSimulatorFork__MessageExecutionFailed.selector);
        strictSimulator.routeV2Message(entry);
        assertEq(offRamp.successfulExecutions(), 0);

        // Without strict routing, the failure is recorded instead.
        strictSimulator.setStrictRouting(false);
        assertTrue(strictSimulator.routeV2Message(entry));
        assertEq(offRamp.successfulExecutions(), 0);
        (CCIPLocalSimulatorFork.MessageStatus status,) = strictSimulator.getMessageStatus(topics[3]);
        assertEq(uint8(status), uint8(CCIPLocalSimulatorFork.MessageStatus.FAILED));

        CCIPLocalSimulatorForkHarness syntheticOnlySimulator = new CCIPLocalSimulatorForkHarness();
        syntheticOnlySimulator.setV2VerificationMode(CCIPLocalSimulatorFork.V2VerificationMode.SYNTHETIC_ONLY);
        assertTrue(syntheticOnlySimulator.routeV2Message(entry));
        assertEq(offRamp.successfulExecutions(), 1);
    }
}
