// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test, Vm, console2} from "forge-std/Test.sol";
import {Register} from "./Register.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts@4.8.3/token/ERC20/IERC20.sol";
import {CCIPForkAdapterTypes} from "./adapters/CCIPForkAdapterTypes.sol";
import {CCIPForkAdapterPreV1dot6} from "./adapters/CCIPForkAdapterPreV1dot6.sol";
import {CCIPForkAdapterV1dot6} from "./adapters/CCIPForkAdapterV1dot6.sol";
import {CCIPForkAdapterV2, IMessageV1Decoder, IOffRampExecuteV2} from "./adapters/CCIPForkAdapterV2.sol";
import {MessageV1CodecDecoder} from "./adapters/MessageV1CodecDecoder.sol";

interface IRouterFork {
    function getOnRamp(uint64 destChainSelector) external view returns (address);

    function getOffRamps() external view returns (CCIPForkAdapterTypes.RouterOffRamp[] memory);
}

interface ITypeAndVersionProbe {
    function typeAndVersion() external view returns (string memory);
}

interface IVersionedVerifierResolverAdminFork {
    struct InboundImplementationArgs {
        bytes4 version;
        address verifier;
    }

    function owner() external view returns (address);

    function applyInboundImplementationUpdates(InboundImplementationArgs[] calldata implementations) external;
}

contract CCIPLocalSimulatorV2NoOpVerifier {
    fallback() external payable {}
}

/// @title CCIPLocalSimulatorFork
/// @notice Works with Foundry only
contract CCIPLocalSimulatorFork is Test {
    enum CCIPEra {
        UNKNOWN,
        PRE_V1_DOT_6,
        V1_DOT_6,
        V2
    }

    enum V2VerificationMode {
        STRICT,
        HYBRID,
        SYNTHETIC_ONLY
    }

    enum V2ExecutionMode {
        AUTO,
        RESPECT_NO_EXEC,
        MANUAL_ONLY
    }

    struct PendingV2Message {
        bool exists;
        address emitter;
        bytes32[] topics;
        bytes data;
    }

    /// @notice The immutable register instance
    Register immutable i_register;

    /// @notice Helper to decode MessageV1 from memory bytes.
    MessageV1CodecDecoder immutable i_messageV1Decoder;

    /// @notice The address of the LINK faucet
    address constant LINK_FAUCET = 0x4281eCF07378Ee595C564a59048801330f3084eE;

    /// @notice Mapping to track processed messages
    mapping(bytes32 messageId => bool isProcessed) internal s_processedMessages;

    bytes4 private constant GET_EXPECTED_NEXT_MESSAGE_NUMBER_SELECTOR =
        bytes4(keccak256("getExpectedNextMessageNumber(uint64)"));
    bytes4 private constant GET_EXPECTED_NEXT_SEQUENCE_NUMBER_SELECTOR =
        bytes4(keccak256("getExpectedNextSequenceNumber(uint64)"));
    bytes4 private constant SYNTHETIC_V2_VERIFIER_VERSION = 0x464f524b; // "FORK"
    bytes4 private constant INVALID_VERIFIER_RESULTS_SELECTOR = bytes4(keccak256("InvalidVerifierResults()"));
    bytes4 private constant INVALID_VERIFIER_RESULTS_LENGTH_SELECTOR =
        bytes4(keccak256("InvalidVerifierResultsLength()"));
    bytes4 private constant INBOUND_IMPLEMENTATION_NOT_FOUND_SELECTOR =
        bytes4(keccak256("InboundImplementationNotFound(address,bytes)"));

    mapping(uint256 routeScope => address verifier) internal s_syntheticV2VerifierByScope;
    mapping(uint256 routeScope => mapping(address resolver => bool isConfigured)) internal
        s_isSyntheticResolverConfiguredByScope;
    mapping(uint256 routeScope => mapping(bytes32 messageId => PendingV2Message pendingMessage)) internal
        s_pendingV2MessagesByScope;
    mapping(uint256 routeScope => bytes32[] messageIds) internal s_pendingV2MessageIdsByScope;

    V2VerificationMode internal s_v2VerificationMode;
    V2ExecutionMode internal s_v2ExecutionMode;

    /**
     * @notice Constructor to initialize the contract
     */
    constructor() {
        vm.recordLogs();
        i_register = new Register();
        i_messageV1Decoder = new MessageV1CodecDecoder();

        vm.makePersistent(address(i_register));
        vm.makePersistent(address(i_messageV1Decoder));

        s_v2VerificationMode = V2VerificationMode.HYBRID;
        s_v2ExecutionMode = V2ExecutionMode.RESPECT_NO_EXEC;
    }

    /**
     * @notice  To be called after the sending of the cross-chain message (`ccipSend`).
     *          Goes through the list of past logs and looks for the supported CCIP send events.
     *          Switches to a destination network fork. Routes the sent cross-chain message on the destination network.
     *          If you sent more than one message, it will try to route all of them to `forkId`.
     *
     * @param forkId - The ID of the destination network fork. This is the returned value of `createFork()` or `createSelectFork()`
     */
    function switchChainAndRouteMessage(uint256 forkId) external {
        uint256 sourceForkId = vm.activeFork();
        address sourceRouterAddress = i_register.getNetworkDetails(block.chainid).routerAddress;

        uint256[] memory forkIds = new uint256[](1);
        forkIds[0] = forkId;

        _routeCapturedMessages(forkIds, sourceForkId, sourceRouterAddress);
    }

    /**
     * @notice  To be called after the sending of the cross-chain message (`ccipSend`).
     *          Override variant of the `switchChainAndRouteMessage(uint256 forkId)` function in case of multiple destination forks.
     *          Goes through provided `forkIds` and tries to route messages to the matching destination.
     *
     * @param forkIds - The IDs of the destination network forks. These are the returned values of `createFork()` or `createSelectFork()`
     */
    function switchChainAndRouteMessage(uint256[] memory forkIds) external {
        uint256 sourceForkId = vm.activeFork();
        address sourceRouterAddress = i_register.getNetworkDetails(block.chainid).routerAddress;

        _routeCapturedMessages(forkIds, sourceForkId, sourceRouterAddress);
    }

    /**
     * @notice Returns the default values for currently CCIP supported networks.
     */
    function getNetworkDetails(uint256 chainId) external view returns (Register.NetworkDetails memory) {
        return i_register.getNetworkDetails(chainId);
    }

    /**
     * @notice Manually sets network details.
     */
    function setNetworkDetails(uint256 chainId, Register.NetworkDetails memory networkDetails) external {
        i_register.setNetworkDetails(chainId, networkDetails);
    }

    /**
     * @notice Requests LINK tokens from the faucet.
     */
    function requestLinkFromFaucet(address to, uint256 amount) external returns (bool success) {
        address linkAddress = i_register.getNetworkDetails(block.chainid).linkAddress;

        vm.startPrank(LINK_FAUCET);
        success = IERC20(linkAddress).transfer(to, amount);
        vm.stopPrank();
    }

    function setV2VerificationMode(V2VerificationMode mode) external {
        s_v2VerificationMode = mode;
    }

    function getV2VerificationMode() external view returns (V2VerificationMode mode) {
        return s_v2VerificationMode;
    }

    function setV2ExecutionMode(V2ExecutionMode mode) external {
        s_v2ExecutionMode = mode;
    }

    function getV2ExecutionMode() external view returns (V2ExecutionMode mode) {
        return s_v2ExecutionMode;
    }

    function getPendingV2MessageIds() external view returns (bytes32[] memory messageIds) {
        return s_pendingV2MessageIdsByScope[_routeScope()];
    }

    function isPendingV2Message(bytes32 messageId) external view returns (bool isPending) {
        return s_pendingV2MessagesByScope[_routeScope()][messageId].exists;
    }

    function executePendingV2Message(bytes32 messageId) external returns (bool attempted) {
        uint256 routeScope = _routeScope();
        PendingV2Message storage pending = s_pendingV2MessagesByScope[routeScope][messageId];
        if (!pending.exists) {
            return false;
        }

        Vm.Log memory entry = _pendingV2MessageToLog(pending);
        attempted = _routeV2Message(entry, true);

        if (s_processedMessages[messageId]) {
            _dequeuePendingV2Message(routeScope, messageId);
        }
    }

    /**
     * @notice Internal function to route captured messages to their respective destination forks.
     *
     * @param forkIds - Destination fork IDs.
     * @param sourceForkId - Source fork ID.
     * @param sourceRouterAddress - Router on the source chain.
     */
    function _routeCapturedMessages(uint256[] memory forkIds, uint256 sourceForkId, address sourceRouterAddress)
        internal
    {
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 logsLength = entries.length;

        for (uint256 i; i < logsLength; ++i) {
            Vm.Log memory entry = entries[i];
            CCIPEra logEra = _detectEraFromLog(entry);
            if (logEra == CCIPEra.UNKNOWN) {
                continue;
            }

            for (uint256 j; j < forkIds.length; ++j) {
                vm.selectFork(forkIds[j]);
                uint64 destinationChainSelector = i_register.getNetworkDetails(block.chainid).chainSelector;

                vm.selectFork(sourceForkId);
                address onRampContract = IRouterFork(sourceRouterAddress).getOnRamp(destinationChainSelector);

                if (entry.emitter != onRampContract || onRampContract == address(0)) {
                    continue;
                }

                CCIPEra detectedEra = _detectEra(onRampContract);
                CCIPEra routingEra = _selectRoutingEra(logEra, detectedEra);

                vm.selectFork(forkIds[j]);
                bool attempted = _routeMessageForEra(entry, routingEra);

                if (attempted) {
                    break;
                }
            }
        }
    }

    function _routeMessageForEra(Vm.Log memory entry, CCIPEra routingEra) internal returns (bool attempted) {
        if (routingEra == CCIPEra.PRE_V1_DOT_6) {
            return _routePreV1dot6Message(entry);
        }

        if (routingEra == CCIPEra.V1_DOT_6) {
            return _routeV1dot6Message(entry);
        }

        if (routingEra == CCIPEra.V2) {
            return _routeV2Message(entry);
        }

        return false;
    }

    function _routePreV1dot6Message(Vm.Log memory entry) internal returns (bool attempted) {
        CCIPForkAdapterTypes.PreV1dot6Message memory message = CCIPForkAdapterPreV1dot6.decodeMessage(entry.data);

        if (s_processedMessages[message.messageId]) {
            return true;
        }

        address offRamp = _findOffRampOnCurrentFork(message.sourceChainSelector);
        if (offRamp == address(0)) {
            return false;
        }

        vm.startPrank(offRamp);
        (bool success, bytes memory returnData) = CCIPForkAdapterPreV1dot6.execute(offRamp, message);
        vm.stopPrank();

        if (success) {
            s_processedMessages[message.messageId] = true;
        } else {
            console2.logBytes(returnData);
        }

        return true;
    }

    function _routeV1dot6Message(Vm.Log memory entry) internal returns (bool attempted) {
        CCIPForkAdapterTypes.V1dot6EVM2AnyRampMessage memory message = CCIPForkAdapterV1dot6.decodeMessage(entry.data);

        if (s_processedMessages[message.header.messageId]) {
            return true;
        }

        address offRamp = _findOffRampOnCurrentFork(message.header.sourceChainSelector);
        if (offRamp == address(0)) {
            return false;
        }

        vm.startPrank(offRamp);
        (bool success, bytes memory returnData) = CCIPForkAdapterV1dot6.execute(message, offRamp);
        vm.stopPrank();

        if (success) {
            s_processedMessages[message.header.messageId] = true;
        } else {
            console2.logBytes(returnData);
        }

        return true;
    }

    function _routeV2Message(Vm.Log memory entry) internal returns (bool attempted) {
        return _routeV2Message(entry, false);
    }

    function _routeV2Message(Vm.Log memory entry, bool forceExecution) internal returns (bool attempted) {
        CCIPForkAdapterV2.DecodedMessage memory decodedMessage =
            CCIPForkAdapterV2.decodeMessage(entry.topics, entry.data, IMessageV1Decoder(address(i_messageV1Decoder)));

        if (s_processedMessages[decodedMessage.messageId]) {
            return true;
        }

        address offRamp = CCIPForkAdapterV2.extractOffRampAddress(decodedMessage);
        if (offRamp == address(0)) {
            offRamp = _findOffRampOnCurrentFork(decodedMessage.message.sourceChainSelector);
        }
        if (offRamp == address(0)) {
            return false;
        }

        if (!forceExecution && _shouldQueueV2Message(decodedMessage)) {
            _enqueuePendingV2Message(decodedMessage.messageId, entry);
            return true;
        }

        (address[] memory ccvs, bytes[] memory verifierResults, bool usedSyntheticInputs) =
            _deriveV2VerificationInputs(offRamp, decodedMessage);

        vm.startPrank(offRamp);
        (bool success, bytes memory returnData) =
            CCIPForkAdapterV2.execute(offRamp, decodedMessage.message, decodedMessage.messageId, ccvs, verifierResults);
        vm.stopPrank();

        if (
            !success && s_v2VerificationMode == V2VerificationMode.HYBRID && !usedSyntheticInputs
                && _isRecoverableV2VerificationFailure(returnData)
        ) {
            (ccvs, verifierResults) =
                _buildSyntheticV2VerificationInputs(offRamp, decodedMessage.encodedMessage, verifierResults);

            vm.startPrank(offRamp);
            (success, returnData) =
                CCIPForkAdapterV2.execute(offRamp, decodedMessage.message, decodedMessage.messageId, ccvs, verifierResults);
            vm.stopPrank();
        }

        if (success) {
            s_processedMessages[decodedMessage.messageId] = true;
            _dequeuePendingV2Message(_routeScope(), decodedMessage.messageId);
        } else {
            console2.logBytes(returnData);
        }

        return true;
    }

    function deriveV2VerificationInputs(address offRamp, CCIPForkAdapterV2.DecodedMessage calldata decodedMessage)
        external
        view
        returns (address[] memory ccvs, bytes[] memory verifierResults)
    {
        return CCIPForkAdapterV2.deriveVerificationInputs(offRamp, decodedMessage);
    }

    function _deriveV2VerificationInputs(address offRamp, CCIPForkAdapterV2.DecodedMessage memory decodedMessage)
        internal
        returns (address[] memory ccvs, bytes[] memory verifierResults, bool usedSyntheticInputs)
    {
        if (s_v2VerificationMode == V2VerificationMode.SYNTHETIC_ONLY) {
            (ccvs, verifierResults) =
                _buildSyntheticV2VerificationInputs(offRamp, decodedMessage.encodedMessage, new bytes[](0));
            return (ccvs, verifierResults, true);
        }

        try this.deriveV2VerificationInputs(offRamp, decodedMessage) returns (
            address[] memory derivedCCVs,
            bytes[] memory derivedVerifierResults
        ) {
            return (derivedCCVs, derivedVerifierResults, false);
        } catch {
            if (s_v2VerificationMode == V2VerificationMode.HYBRID) {
                (ccvs, verifierResults) =
                    _buildSyntheticV2VerificationInputs(offRamp, decodedMessage.encodedMessage, new bytes[](0));
                return (ccvs, verifierResults, true);
            }

            return (new address[](0), new bytes[](0), false);
        }
    }

    function _buildSyntheticV2VerificationInputs(
        address offRamp,
        bytes memory encodedMessage,
        bytes[] memory existingVerifierResults
    ) internal returns (address[] memory ccvs, bytes[] memory verifierResults) {
        ccvs = _deriveV2CCVSelection(offRamp, encodedMessage);
        verifierResults = new bytes[](ccvs.length);

        if (existingVerifierResults.length == ccvs.length) {
            for (uint256 i; i < ccvs.length; ++i) {
                verifierResults[i] = existingVerifierResults[i];
            }
        }

        if (ccvs.length == 0) {
            return (ccvs, verifierResults);
        }

        address syntheticVerifier = _getOrCreateSyntheticV2Verifier();
        bytes memory syntheticResult = abi.encodePacked(SYNTHETIC_V2_VERIFIER_VERSION);

        for (uint256 i; i < ccvs.length; ++i) {
            if (_configureResolverForSyntheticV2Verification(ccvs[i], syntheticVerifier)) {
                verifierResults[i] = syntheticResult;
            }
        }
    }

    function _deriveV2CCVSelection(address offRamp, bytes memory encodedMessage)
        internal
        view
        returns (address[] memory ccvs)
    {
        address[] memory requiredCCVs;
        address[] memory optionalCCVs;
        uint8 threshold;

        try IOffRampExecuteV2(offRamp).getCCVsForMessage(encodedMessage) returns (
            address[] memory requiredCCVs_,
            address[] memory optionalCCVs_,
            uint8 threshold_
        ) {
            requiredCCVs = requiredCCVs_;
            optionalCCVs = optionalCCVs_;
            threshold = threshold_;
        } catch {
            return new address[](0);
        }

        uint256 totalAvailable = requiredCCVs.length + optionalCCVs.length;
        uint256 targetLength = requiredCCVs.length;

        if (targetLength < threshold) {
            targetLength = threshold;
        }
        if (targetLength > totalAvailable) {
            targetLength = totalAvailable;
        }

        ccvs = new address[](targetLength);
        uint256 ccvCount;
        for (uint256 i = 0; i < requiredCCVs.length && ccvCount < targetLength; ++i) {
            ccvs[ccvCount++] = requiredCCVs[i];
        }
        for (uint256 i = 0; i < optionalCCVs.length && ccvCount < targetLength; ++i) {
            ccvs[ccvCount++] = optionalCCVs[i];
        }
    }

    function _configureResolverForSyntheticV2Verification(address resolver, address syntheticVerifier)
        internal
        returns (bool configured)
    {
        uint256 routeScope = _routeScope();
        if (s_isSyntheticResolverConfiguredByScope[routeScope][resolver]) {
            return true;
        }

        address resolverOwner;
        try IVersionedVerifierResolverAdminFork(resolver).owner() returns (address owner_) {
            resolverOwner = owner_;
        } catch {
            return false;
        }

        if (resolverOwner == address(0)) {
            return false;
        }

        IVersionedVerifierResolverAdminFork.InboundImplementationArgs[] memory updates =
            new IVersionedVerifierResolverAdminFork.InboundImplementationArgs[](1);
        updates[0] = IVersionedVerifierResolverAdminFork.InboundImplementationArgs({
            version: SYNTHETIC_V2_VERIFIER_VERSION,
            verifier: syntheticVerifier
        });

        vm.startPrank(resolverOwner);
        try IVersionedVerifierResolverAdminFork(resolver).applyInboundImplementationUpdates(updates) {
            configured = true;
        } catch {
            configured = false;
        }
        vm.stopPrank();

        if (configured) {
            s_isSyntheticResolverConfiguredByScope[routeScope][resolver] = true;
        }
    }

    function _getOrCreateSyntheticV2Verifier() internal returns (address verifier) {
        uint256 routeScope = _routeScope();
        verifier = s_syntheticV2VerifierByScope[routeScope];
        if (verifier == address(0)) {
            verifier = address(new CCIPLocalSimulatorV2NoOpVerifier());
            s_syntheticV2VerifierByScope[routeScope] = verifier;
        }
    }

    function _routeScope() internal view returns (uint256 routeScope) {
        try vm.activeFork() returns (uint256 activeForkId) {
            return activeForkId;
        } catch {
            return block.chainid;
        }
    }

    function _shouldQueueV2Message(CCIPForkAdapterV2.DecodedMessage memory decodedMessage) internal view returns (bool) {
        if (s_v2ExecutionMode == V2ExecutionMode.AUTO) {
            return false;
        }

        if (s_v2ExecutionMode == V2ExecutionMode.MANUAL_ONLY) {
            return true;
        }

        return _isNoExecV2Message(decodedMessage);
    }

    function _isNoExecV2Message(CCIPForkAdapterV2.DecodedMessage memory decodedMessage) internal pure returns (bool) {
        uint256 receiptsLength = decodedMessage.receipts.length;
        if (receiptsLength < 2) {
            return false;
        }

        address executor = decodedMessage.receipts[receiptsLength - 2].issuer;
        return executor == Client.NO_EXECUTION_ADDRESS;
    }

    function _enqueuePendingV2Message(bytes32 messageId, Vm.Log memory entry) internal {
        uint256 routeScope = _routeScope();
        PendingV2Message storage pending = s_pendingV2MessagesByScope[routeScope][messageId];
        if (pending.exists) {
            return;
        }

        pending.exists = true;
        pending.emitter = entry.emitter;
        pending.data = entry.data;
        delete pending.topics;
        for (uint256 i; i < entry.topics.length; ++i) {
            pending.topics.push(entry.topics[i]);
        }

        s_pendingV2MessageIdsByScope[routeScope].push(messageId);
    }

    function _dequeuePendingV2Message(uint256 routeScope, bytes32 messageId) internal {
        PendingV2Message storage pending = s_pendingV2MessagesByScope[routeScope][messageId];
        if (!pending.exists) {
            return;
        }

        delete s_pendingV2MessagesByScope[routeScope][messageId];

        bytes32[] storage messageIds = s_pendingV2MessageIdsByScope[routeScope];
        for (uint256 i; i < messageIds.length; ++i) {
            if (messageIds[i] == messageId) {
                messageIds[i] = messageIds[messageIds.length - 1];
                messageIds.pop();
                break;
            }
        }
    }

    function _pendingV2MessageToLog(PendingV2Message storage pending) internal view returns (Vm.Log memory entry) {
        entry.topics = new bytes32[](pending.topics.length);
        for (uint256 i; i < pending.topics.length; ++i) {
            entry.topics[i] = pending.topics[i];
        }
        entry.data = pending.data;
        entry.emitter = pending.emitter;
    }

    function _isRecoverableV2VerificationFailure(bytes memory returnData) internal pure returns (bool) {
        if (returnData.length < 4) {
            return false;
        }

        bytes4 selector = bytes4(returnData);
        return selector == INVALID_VERIFIER_RESULTS_SELECTOR
            || selector == INVALID_VERIFIER_RESULTS_LENGTH_SELECTOR
            || selector == INBOUND_IMPLEMENTATION_NOT_FOUND_SELECTOR;
    }

    function _findOffRampOnCurrentFork(uint64 sourceChainSelector) internal view returns (address offRampAddress) {
        address destinationRouterAddress = i_register.getNetworkDetails(block.chainid).routerAddress;

        (bool success, bytes memory returnData) =
            destinationRouterAddress.staticcall(abi.encodeWithSelector(IRouterFork.getOffRamps.selector));
        if (!success || returnData.length == 0) {
            return address(0);
        }

        CCIPForkAdapterTypes.RouterOffRamp[] memory offRamps =
            abi.decode(returnData, (CCIPForkAdapterTypes.RouterOffRamp[]));

        for (uint256 i = offRamps.length; i > 0; --i) {
            if (offRamps[i - 1].sourceChainSelector == sourceChainSelector) {
                return offRamps[i - 1].offRamp;
            }
        }

        return address(0);
    }

    function _detectEra(address onRamp) internal view returns (CCIPEra era) {
        CCIPEra byTypeAndVersion = _detectEraByTypeAndVersion(onRamp);
        if (byTypeAndVersion != CCIPEra.UNKNOWN) {
            return byTypeAndVersion;
        }

        if (_probeSelector(onRamp, GET_EXPECTED_NEXT_MESSAGE_NUMBER_SELECTOR)) {
            return CCIPEra.V2;
        }

        if (_probeSelector(onRamp, GET_EXPECTED_NEXT_SEQUENCE_NUMBER_SELECTOR)) {
            return CCIPEra.V1_DOT_6;
        }

        return CCIPEra.PRE_V1_DOT_6;
    }

    function _detectEraByTypeAndVersion(address onRamp) internal view returns (CCIPEra era) {
        try ITypeAndVersionProbe(onRamp).typeAndVersion() returns (string memory typeAndVersion) {
            bytes memory value = bytes(typeAndVersion);

            if (_contains(value, bytes("2."))) {
                return CCIPEra.V2;
            }

            if (_contains(value, bytes("1.6"))) {
                return CCIPEra.V1_DOT_6;
            }

            if (_contains(value, bytes("1."))) {
                return CCIPEra.PRE_V1_DOT_6;
            }
        } catch {
            return CCIPEra.UNKNOWN;
        }

        return CCIPEra.UNKNOWN;
    }

    function _probeSelector(address target, bytes4 selector) internal view returns (bool supported) {
        (bool success, bytes memory returnData) = target.staticcall(abi.encodeWithSelector(selector, uint64(0)));
        return success && returnData.length >= 32;
    }

    function _detectEraFromLog(Vm.Log memory entry) internal pure returns (CCIPEra era) {
        if (entry.topics.length == 0) {
            return CCIPEra.UNKNOWN;
        }

        bytes32 topic0 = entry.topics[0];

        if (topic0 == CCIPForkAdapterPreV1dot6.eventSelector()) {
            return CCIPEra.PRE_V1_DOT_6;
        }

        if (topic0 == CCIPForkAdapterV1dot6.eventSelector()) {
            return CCIPEra.V1_DOT_6;
        }

        if (topic0 == CCIPForkAdapterV2.eventSelector()) {
            return CCIPEra.V2;
        }

        return CCIPEra.UNKNOWN;
    }

    function _selectRoutingEra(CCIPEra logEra, CCIPEra detectedEra) internal pure returns (CCIPEra) {
        if (logEra == CCIPEra.UNKNOWN) {
            return detectedEra;
        }

        if (detectedEra == CCIPEra.UNKNOWN) {
            return logEra;
        }

        if (detectedEra != logEra) {
            return logEra;
        }

        return detectedEra;
    }

    function _contains(bytes memory haystack, bytes memory needle) internal pure returns (bool) {
        if (needle.length == 0 || needle.length > haystack.length) {
            return false;
        }

        for (uint256 i; i <= haystack.length - needle.length; ++i) {
            bool matchFound = true;
            for (uint256 j; j < needle.length; ++j) {
                if (haystack[i + j] != needle[j]) {
                    matchFound = false;
                    break;
                }
            }

            if (matchFound) {
                return true;
            }
        }

        return false;
    }
}
