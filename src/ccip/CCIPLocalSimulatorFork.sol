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

/// @title IRouterFork Interface
interface IRouterFork {
    /**
     * @notice Return the configured onramp for specific a destination chain.
     *  @param destChainSelector The destination chain Id to get the onRamp for.
     * @return The address of the onRamp.
     */
    function getOnRamp(uint64 destChainSelector) external view returns (address);

    /**
     * @notice Gets the list of offRamps
     *
     * @return offRamps - Array of OffRamp structs
     */
    function getOffRamps() external view returns (CCIPForkAdapterTypes.RouterOffRamp[] memory);
}

/// @title IEVM2EVMOffRampStaticConfigFork
/// @notice Minimal view surface for pre-v1.6 OffRamp static config (EVM2EVMOffRamp 1.5.x).
interface IEVM2EVMOffRampStaticConfigFork {
    struct StaticConfig {
        address commitStore;
        uint64 chainSelector;
        uint64 sourceChainSelector;
        address onRamp;
        address prevOffRamp;
        address rmnProxy;
        address tokenAdminRegistry;
    }

    function getStaticConfig() external view returns (StaticConfig memory);
}

/// @title IOffRampSourceConfigFork
/// @notice Minimal view surface for v1.6+ OffRamp per-source-chain config (OffRamp 1.6.x).
/// @dev `router` is ABI-compatible with `IRouter` in CCIP OffRamp `SourceChainConfig`.
interface IOffRampSourceConfigFork {
    struct SourceChainConfig {
        address router;
        bool isEnabled;
        uint64 minSeqNr;
        bool isRMNVerificationDisabled;
        bytes onRamp;
    }

    function getSourceChainConfig(uint64 sourceChainSelector) external view returns (SourceChainConfig memory);
}

/// @title IOffRampSourceConfigV2Fork
/// @notice Minimal view/update surface for the CCIP 2.0 OffRamp per-source-chain config, including
///         the CCV sets used to verify messages. Mirrors `OffRamp.SourceChainConfig`.
interface IOffRampSourceConfigV2Fork {
    struct SourceChainConfig {
        address router;
        bool isEnabled;
        bytes[] onRamps;
        address[] defaultCCVs;
        address[] laneMandatedCCVs;
    }

    struct SourceChainConfigArgs {
        address router;
        uint64 sourceChainSelector;
        bool isEnabled;
        bytes[] onRamps;
        address[] defaultCCVs;
        address[] laneMandatedCCVs;
    }

    function getSourceChainConfig(uint64 sourceChainSelector) external view returns (SourceChainConfig memory);

    function applySourceChainConfigUpdates(SourceChainConfigArgs[] calldata updates) external;

    function owner() external view returns (address);
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
        SYNTHETIC_ONLY,
        /// @notice Derives the CCV selection from the destination OffRamp's
        ///         `getCCVsForMessage(encodedMessage)` and executes the raw encoded message through
        ///         the permissionless `execute` entrypoint, so routing does not depend on the local
        ///         `MessageV1` codec. Fork-only.
        OFFRAMP_DERIVED
    }

    enum V2ExecutionMode {
        AUTO,
        RESPECT_NO_EXEC,
        MANUAL_ONLY
    }

    struct PendingV2Message {
        bool exists;
        uint64 sourceChainSelector;
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
    /// @dev `Internal.MessageExecutionState.SUCCESS`.
    uint256 private constant V2_EXECUTION_STATE_SUCCESS = 2;
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

    /// @notice CCIP 2.0 routers deployed next to the Register router (which `getNetworkDetails` returns).
    /// @dev Hand-maintained: `Register` is generated from the CCIP docs API and only carries one router per chain.
    mapping(uint256 chainId => address router) internal s_ccipV2Routers;

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

        s_v2VerificationMode = V2VerificationMode.OFFRAMP_DERIVED;

        // CCIP 2.0 routers verified on-chain (Sep 2026). Lanes of the Register router may be CCIP 2.0 as well.
        s_ccipV2Routers[11155111] = 0x784d49a71BB4C48eB7dA4cD7e6Ecb424f9b5EAB1; // Ethereum Sepolia
        s_ccipV2Routers[43113] = 0x7C9B8B4e8024e5Ee8A630F6FCe9015e470dA5763; // Avalanche Fuji
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
        uint256[] memory forkIds = new uint256[](1);
        forkIds[0] = forkId;

        _routeCapturedMessages(forkIds, vm.activeFork());
    }

    /**
     * @notice  To be called after the sending of the cross-chain message (`ccipSend`).
     *          Override variant of the `switchChainAndRouteMessage(uint256 forkId)` function in case of multiple destination forks.
     *          Goes through provided `forkIds` and tries to route messages to the matching destination.
     *
     * @param forkIds - The IDs of the destination network forks. These are the returned values of `createFork()` or `createSelectFork()`
     */
    function switchChainAndRouteMessage(uint256[] memory forkIds) external {
        _routeCapturedMessages(forkIds, vm.activeFork());
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
     * @notice Returns the CCIP 2.0 router deployed next to the Register router on `chainId`, or address(0) if none is
     *         known. Send through this router (and point receivers at it) to use its CCIP 2.0 lanes; messages sent
     *         through either router are routed by `switchChainAndRouteMessage`.
     */
    function getCCIPV2RouterAddress(uint256 chainId) external view returns (address) {
        return s_ccipV2Routers[chainId];
    }

    /**
     * @notice Manually sets the CCIP 2.0 router for `chainId`. Use address(0) to route through the Register router only.
     */
    function setCCIPV2RouterAddress(uint256 chainId, address router) external {
        s_ccipV2Routers[chainId] = router;
    }

    /**
     * @notice Returns the destination OffRamp configured for `sourceOnRamp` on the given fork, if
     *         discoverable. Useful to configure CCIP 2.0 lane CCVs before routing a message.
     *
     * @param forkId - The ID of the destination network fork.
     * @param sourceChainSelector - The chain selector of the source chain.
     * @param sourceOnRamp - The address of the OnRamp on the source chain.
     *
     * @return offRamp - The matching OffRamp address, or address(0) when not found.
     */
    function getOffRampForLane(uint256 forkId, uint64 sourceChainSelector, address sourceOnRamp)
        external
        returns (address offRamp)
    {
        uint256 previousForkId = vm.activeFork();
        vm.selectFork(forkId);
        offRamp = _findOffRampOnCurrentFork(sourceChainSelector, sourceOnRamp);
        vm.selectFork(previousForkId);
    }

    /**
     * @notice Points a destination lane's default CCVs at `ccv` by impersonating the OffRamp owner.
     *         Fork-only testing helper for CCIP 2.0 lanes: the mocked CCV must be configured on the
     *         destination lane before a captured message can be routed through the permissionless
     *         execution path. Router, enabled flag and OnRamp bindings are preserved.
     *
     * @param forkId - The ID of the destination network fork.
     * @param offRamp - The destination OffRamp that holds the lane config.
     * @param sourceChainSelector - The chain selector of the source chain.
     * @param ccv - The CCV address to set as the lane default.
     */
    function setLaneDefaultCCVs(uint256 forkId, address offRamp, uint64 sourceChainSelector, address ccv) external {
        uint256 previousForkId = vm.activeFork();
        vm.selectFork(forkId);

        IOffRampSourceConfigV2Fork.SourceChainConfig memory current =
            IOffRampSourceConfigV2Fork(offRamp).getSourceChainConfig(sourceChainSelector);
        require(current.isEnabled, "CCIPLocalSimulatorFork: lane not enabled");

        address[] memory defaultCCVs = new address[](1);
        defaultCCVs[0] = ccv;

        IOffRampSourceConfigV2Fork.SourceChainConfigArgs[] memory updates =
            new IOffRampSourceConfigV2Fork.SourceChainConfigArgs[](1);
        updates[0] = IOffRampSourceConfigV2Fork.SourceChainConfigArgs({
            router: current.router,
            sourceChainSelector: sourceChainSelector,
            isEnabled: true,
            onRamps: current.onRamps,
            defaultCCVs: defaultCCVs,
            laneMandatedCCVs: new address[](0)
        });

        address owner = IOffRampSourceConfigV2Fork(offRamp).owner();
        vm.startPrank(owner);
        IOffRampSourceConfigV2Fork(offRamp).applySourceChainConfigUpdates(updates);
        vm.stopPrank();

        vm.selectFork(previousForkId);
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
        attempted = _routeV2Message(entry, pending.sourceChainSelector, true);

        if (s_processedMessages[messageId]) {
            _dequeuePendingV2Message(routeScope, messageId);
        }
    }

    /**
     * @notice Internal function to route captured messages to their respective destination forks.
     *
     * @param forkIds - Destination fork IDs.
     * @param sourceForkId - Source fork ID.
     */
    function _routeCapturedMessages(uint256[] memory forkIds, uint256 sourceForkId) internal {
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 logsLength = entries.length;
        uint64 sourceChainSelector = i_register.getNetworkDetails(block.chainid).chainSelector;

        for (uint256 i; i < logsLength; ++i) {
            _routeCapturedMessage(entries[i], forkIds, sourceForkId, sourceChainSelector);
        }
    }

    function _routeCapturedMessage(
        Vm.Log memory entry,
        uint256[] memory forkIds,
        uint256 sourceForkId,
        uint64 sourceChainSelector
    ) internal {
        CCIPEra logEra = _detectEraFromLog(entry);
        if (logEra == CCIPEra.UNKNOWN) {
            return;
        }

        uint64 v2DestinationChainSelector;
        if (logEra == CCIPEra.V2) {
            if (s_v2VerificationMode == V2VerificationMode.OFFRAMP_DERIVED) {
                v2DestinationChainSelector = uint64(uint256(entry.topics[1]));
            } else {
                CCIPForkAdapterV2.DecodedMessage memory decodedMessage = CCIPForkAdapterV2.decodeMessage(
                    entry.topics, entry.data, IMessageV1Decoder(address(i_messageV1Decoder))
                );
                v2DestinationChainSelector = decodedMessage.message.destChainSelector;
            }
        }

        for (uint256 j; j < forkIds.length; ++j) {
            vm.selectFork(forkIds[j]);
            uint64 destinationChainSelector = i_register.getNetworkDetails(block.chainid).chainSelector;

            if (logEra == CCIPEra.V2 && v2DestinationChainSelector != destinationChainSelector) {
                continue;
            }

            vm.selectFork(sourceForkId);
            address onRampContract = _findSourceOnRamp(destinationChainSelector, entry.emitter);
            if (onRampContract == address(0)) {
                continue;
            }

            CCIPEra routingEra = _selectRoutingEra(logEra, _detectEra(onRampContract));

            vm.selectFork(forkIds[j]);
            if (_routeMessageForEra(entry, routingEra, onRampContract, sourceChainSelector)) {
                break;
            }
        }
    }

    function _routeMessageForEra(
        Vm.Log memory entry,
        CCIPEra routingEra,
        address sourceOnRamp,
        uint64 sourceChainSelector
    ) internal returns (bool attempted) {
        if (routingEra == CCIPEra.PRE_V1_DOT_6) {
            return _routePreV1dot6Message(entry, sourceOnRamp);
        }

        if (routingEra == CCIPEra.V1_DOT_6) {
            return _routeV1dot6Message(entry, sourceOnRamp);
        }

        if (routingEra == CCIPEra.V2) {
            return _routeV2Message(entry, sourceChainSelector, false);
        }

        return false;
    }

    function _routePreV1dot6Message(Vm.Log memory entry, address sourceOnRamp) internal returns (bool attempted) {
        CCIPForkAdapterTypes.PreV1dot6Message memory message = CCIPForkAdapterPreV1dot6.decodeMessage(entry.data);

        if (s_processedMessages[message.messageId]) {
            return true;
        }

        address offRamp = _findOffRampOnCurrentFork(message.sourceChainSelector, sourceOnRamp);
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

    function _routeV1dot6Message(Vm.Log memory entry, address sourceOnRamp) internal returns (bool attempted) {
        CCIPForkAdapterTypes.V1dot6EVM2AnyRampMessage memory message = CCIPForkAdapterV1dot6.decodeMessage(entry.data);

        if (s_processedMessages[message.header.messageId]) {
            return true;
        }

        address offRamp = _findOffRampOnCurrentFork(message.header.sourceChainSelector, sourceOnRamp);
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

    /// @notice Routes a CCIP 2.0 message on the current (destination) fork.
    /// @param sourceChainSelector Chain selector of the source chain the message was sent from.
    /// @param forceExecution Execute even if the V2 execution mode would queue the message.
    function _routeV2Message(Vm.Log memory entry, uint64 sourceChainSelector, bool forceExecution)
        internal
        returns (bool attempted)
    {
        if (s_v2VerificationMode == V2VerificationMode.OFFRAMP_DERIVED) {
            return _routeV2MessageOffRampDerived(entry, sourceChainSelector, forceExecution);
        }
        return _routeV2MessageWithLocalCodec(entry, forceExecution);
    }

    /// @notice Routes a CCIP 2.0 message without decoding it locally: the destination OffRamp's `getCCVsForMessage`
    ///         selects the CCVs and the permissionless `execute` entrypoint consumes the raw encoded message, so routing
    ///         keeps working when the on-chain `MessageV1` wire format moves ahead of the pinned codec.
    /// @dev `execute` does not revert when the inner execution fails on a first attempt (it records `FAILURE`), so
    ///      the message is marked processed only when the OffRamp reports `SUCCESS`.
    function _routeV2MessageOffRampDerived(Vm.Log memory entry, uint64 sourceChainSelector, bool forceExecution)
        internal
        returns (bool attempted)
    {
        if (entry.topics.length < 4) {
            return false;
        }

        bytes32 messageId = entry.topics[3];
        if (s_processedMessages[messageId]) {
            return true;
        }

        (,, bytes memory encodedMessage, CCIPForkAdapterTypes.V2Receipt[] memory receipts,) =
            abi.decode(entry.data, (address, uint256, bytes, CCIPForkAdapterTypes.V2Receipt[], bytes[]));

        // The OnRamp emits the event, so the log emitter is the source OnRamp (queued messages keep it too).
        address offRamp = _findOffRampOnCurrentFork(sourceChainSelector, entry.emitter);
        if (offRamp == address(0)) {
            return false;
        }

        if (!forceExecution && _shouldQueueV2Message(receipts)) {
            _enqueuePendingV2Message(messageId, entry, sourceChainSelector);
            return true;
        }

        (address[] memory ccvs, bytes[] memory verifierResults) =
            _buildSyntheticV2VerificationInputs(offRamp, encodedMessage, new bytes[](0));

        try IOffRampExecuteV2(offRamp).execute(encodedMessage, ccvs, verifierResults, uint32(0)) {
            if (_isV2ExecutionSuccess(offRamp, keccak256(encodedMessage))) {
                s_processedMessages[messageId] = true;
                _dequeuePendingV2Message(_routeScope(), messageId);
            } else {
                console2.log("CCIPLocalSimulatorFork: CCIP 2.0 execution did not succeed for message");
                console2.logBytes32(messageId);
            }
        } catch (bytes memory err) {
            console2.logBytes(err);
        }

        return true;
    }

    /// @dev Reads `getExecutionState(messageId)` from an OffRamp 2.0 without trusting the return shape.
    function _isV2ExecutionSuccess(address offRamp, bytes32 messageId) internal view returns (bool) {
        (bool ok, bytes memory data) =
            offRamp.staticcall(abi.encodeWithSelector(IOffRampExecuteV2.getExecutionState.selector, messageId));
        return ok && data.length == 32 && abi.decode(data, (uint256)) == V2_EXECUTION_STATE_SUCCESS;
    }

    function _routeV2MessageWithLocalCodec(Vm.Log memory entry, bool forceExecution) internal returns (bool attempted) {
        CCIPForkAdapterV2.DecodedMessage memory decodedMessage =
            CCIPForkAdapterV2.decodeMessage(entry.topics, entry.data, IMessageV1Decoder(address(i_messageV1Decoder)));

        if (s_processedMessages[decodedMessage.messageId]) {
            return true;
        }

        address offRamp = CCIPForkAdapterV2.extractOffRampAddress(decodedMessage);
        if (offRamp == address(0)) {
            // The OnRamp emits the event and stamps `onRampAddress = abi.encode(address(this))`, so the log emitter
            // is the source OnRamp (also for queued messages, which keep the original emitter).
            offRamp = _findOffRampOnCurrentFork(decodedMessage.message.sourceChainSelector, entry.emitter);
        }
        if (offRamp == address(0)) {
            return false;
        }

        if (!forceExecution && _shouldQueueV2Message(decodedMessage.receipts)) {
            _enqueuePendingV2Message(decodedMessage.messageId, entry, decodedMessage.message.sourceChainSelector);
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
            (success, returnData) = CCIPForkAdapterV2.execute(
                offRamp, decodedMessage.message, decodedMessage.messageId, ccvs, verifierResults
            );
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
            address[] memory derivedCCVs, bytes[] memory derivedVerifierResults
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

        (bool ok, bytes memory data) =
            offRamp.staticcall(abi.encodeWithSelector(IOffRampExecuteV2.getCCVsForMessage.selector, encodedMessage));
        if (!ok) {
            return new address[](0);
        }
        // Decoded in an external self-call so an unexpected return shape cannot revert the routing flow.
        try this.decodeCCVsForMessage(data) returns (
            address[] memory requiredCCVs_, address[] memory optionalCCVs_, uint8 threshold_
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

        // Low-level probe: a high-level `try` does not catch the no-code check or a mis-shaped return value.
        (bool ok, bytes memory data) =
            resolver.staticcall(abi.encodeWithSelector(IVersionedVerifierResolverAdminFork.owner.selector));
        if (!ok || data.length != 32) {
            return false;
        }
        address resolverOwner = abi.decode(data, (address));
        if (resolverOwner == address(0)) {
            return false;
        }

        IVersionedVerifierResolverAdminFork.InboundImplementationArgs[] memory updates =
            new IVersionedVerifierResolverAdminFork.InboundImplementationArgs[](1);
        updates[0] = IVersionedVerifierResolverAdminFork.InboundImplementationArgs({
            version: SYNTHETIC_V2_VERIFIER_VERSION, verifier: syntheticVerifier
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

    function _shouldQueueV2Message(CCIPForkAdapterTypes.V2Receipt[] memory receipts) internal view returns (bool) {
        if (s_v2ExecutionMode == V2ExecutionMode.AUTO) {
            return false;
        }

        if (s_v2ExecutionMode == V2ExecutionMode.MANUAL_ONLY) {
            return true;
        }

        return _isNoExecV2Message(receipts);
    }

    function _isNoExecV2Message(CCIPForkAdapterTypes.V2Receipt[] memory receipts) internal pure returns (bool) {
        uint256 receiptsLength = receipts.length;
        if (receiptsLength < 2) {
            return false;
        }

        address executor = receipts[receiptsLength - 2].issuer;
        return executor == Client.NO_EXECUTION_ADDRESS;
    }

    function _enqueuePendingV2Message(bytes32 messageId, Vm.Log memory entry, uint64 sourceChainSelector) internal {
        uint256 routeScope = _routeScope();
        PendingV2Message storage pending = s_pendingV2MessagesByScope[routeScope][messageId];
        if (pending.exists) {
            return;
        }

        pending.exists = true;
        pending.sourceChainSelector = sourceChainSelector;
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
        return selector == INVALID_VERIFIER_RESULTS_SELECTOR || selector == INVALID_VERIFIER_RESULTS_LENGTH_SELECTOR
            || selector == INBOUND_IMPLEMENTATION_NOT_FOUND_SELECTOR;
    }

    /// @notice Returns the destination OffRamp whose lane is configured for `sourceOnRamp`, if discoverable.
    /// @dev The router lists OffRamps of several protocol versions for the same source chain (e.g. 1.6 and 2.0
    ///      side by side during a lane migration). Their getters share selectors but not return shapes, and a
    ///      mismatched return payload fails to decode in the calling frame, which Solidity `try/catch` cannot catch.
    ///      So every candidate is probed with low-level calls and decoded through an external self-call, and a
    ///      candidate of unknown shape is skipped instead of reverting the routing flow.
    function _findOffRampForOnRamp(
        CCIPForkAdapterTypes.RouterOffRamp[] memory offRamps,
        uint64 sourceChainSelector,
        address sourceOnRamp
    ) internal view returns (address offRampAddress) {
        for (uint256 i = offRamps.length; i > 0; --i) {
            if (offRamps[i - 1].sourceChainSelector != sourceChainSelector) {
                continue;
            }

            address candidate = offRamps[i - 1].offRamp;
            if (_offRampServesOnRamp(candidate, sourceChainSelector, sourceOnRamp)) {
                return candidate;
            }
        }

        return address(0);
    }

    function _offRampServesOnRamp(address offRamp, uint64 sourceChainSelector, address sourceOnRamp)
        internal
        view
        returns (bool)
    {
        (bool isReadable, CCIPEra era) = _detectOffRampEra(offRamp);

        if (!isReadable) {
            // No readable `typeAndVersion` (older deployments, test doubles): probe every known shape. A payload of
            // another version may still decode, but a match needs the lane's OnRamp bytes to equal
            // `abi.encode(sourceOnRamp)` exactly, so a wrong-shape decode yields no match and the next shape is tried.
            return _v1dot6LaneMatches(offRamp, sourceChainSelector, sourceOnRamp)
                || _v2LaneMatches(offRamp, sourceChainSelector, sourceOnRamp)
                || _preV1dot6LaneMatches(offRamp, sourceChainSelector, sourceOnRamp);
        }

        if (era == CCIPEra.V2) {
            return _v2LaneMatches(offRamp, sourceChainSelector, sourceOnRamp);
        }
        if (era == CCIPEra.V1_DOT_6) {
            // Pre-1.6 fallback kept as defense in depth for 1.6 deployments; it can no longer revert.
            return _v1dot6LaneMatches(offRamp, sourceChainSelector, sourceOnRamp)
                || _preV1dot6LaneMatches(offRamp, sourceChainSelector, sourceOnRamp);
        }
        if (era == CCIPEra.PRE_V1_DOT_6) {
            return _preV1dot6LaneMatches(offRamp, sourceChainSelector, sourceOnRamp);
        }

        // Readable `typeAndVersion` of an OffRamp version this simulator does not know: unknown shape, skip.
        return false;
    }

    /// @return isReadable False when `typeAndVersion` is missing or does not decode to a string.
    /// @return era The OffRamp era, or UNKNOWN for an unrecognised type or version.
    function _detectOffRampEra(address offRamp) internal view returns (bool isReadable, CCIPEra era) {
        (bool ok, bytes memory data) =
            offRamp.staticcall(abi.encodeWithSelector(ITypeAndVersionProbe.typeAndVersion.selector));
        if (!ok) {
            return (false, CCIPEra.UNKNOWN);
        }

        bytes memory typeAndVersion;
        try this.decodeTypeAndVersion(data) returns (string memory decoded) {
            typeAndVersion = bytes(decoded);
        } catch {
            return (false, CCIPEra.UNKNOWN);
        }

        if (_startsWith(typeAndVersion, bytes("OffRamp 2."))) {
            return (true, CCIPEra.V2);
        }
        if (_startsWith(typeAndVersion, bytes("OffRamp 1.6"))) {
            return (true, CCIPEra.V1_DOT_6);
        }
        if (_startsWith(typeAndVersion, bytes("EVM2EVMOffRamp 1."))) {
            return (true, CCIPEra.PRE_V1_DOT_6);
        }
        return (true, CCIPEra.UNKNOWN);
    }

    function _v2LaneMatches(address offRamp, uint64 sourceChainSelector, address sourceOnRamp)
        internal
        view
        returns (bool)
    {
        (bool ok, bytes memory data) = offRamp.staticcall(
            abi.encodeWithSelector(IOffRampSourceConfigV2Fork.getSourceChainConfig.selector, sourceChainSelector)
        );
        if (!ok) {
            return false;
        }

        try this.decodeSourceChainConfigV2(data) returns (IOffRampSourceConfigV2Fork.SourceChainConfig memory cfg) {
            if (!cfg.isEnabled) {
                return false;
            }
            for (uint256 i; i < cfg.onRamps.length; ++i) {
                if (cfg.onRamps[i].length == 32 && abi.decode(cfg.onRamps[i], (address)) == sourceOnRamp) {
                    return true;
                }
            }
        } catch {}

        return false;
    }

    function _v1dot6LaneMatches(address offRamp, uint64 sourceChainSelector, address sourceOnRamp)
        internal
        view
        returns (bool)
    {
        (bool ok, bytes memory data) = offRamp.staticcall(
            abi.encodeWithSelector(IOffRampSourceConfigFork.getSourceChainConfig.selector, sourceChainSelector)
        );
        if (!ok) {
            return false;
        }

        try this.decodeSourceChainConfigV1dot6(data) returns (IOffRampSourceConfigFork.SourceChainConfig memory cfg) {
            return cfg.isEnabled && cfg.onRamp.length == 32 && abi.decode(cfg.onRamp, (address)) == sourceOnRamp;
        } catch {
            return false;
        }
    }

    function _preV1dot6LaneMatches(address offRamp, uint64 sourceChainSelector, address sourceOnRamp)
        internal
        view
        returns (bool)
    {
        (bool ok, bytes memory data) =
            offRamp.staticcall(abi.encodeWithSelector(IEVM2EVMOffRampStaticConfigFork.getStaticConfig.selector));
        if (!ok) {
            return false;
        }

        try this.decodeStaticConfigPreV1dot6(data) returns (IEVM2EVMOffRampStaticConfigFork.StaticConfig memory cfg) {
            return cfg.onRamp == sourceOnRamp && cfg.sourceChainSelector == sourceChainSelector;
        } catch {
            return false;
        }
    }

    /// @notice External decode helper for `getCCVsForMessage` return data. Do not call directly.
    function decodeCCVsForMessage(bytes calldata data)
        external
        pure
        returns (address[] memory requiredCCVs, address[] memory optionalCCVs, uint8 threshold)
    {
        return abi.decode(data, (address[], address[], uint8));
    }

    /// @notice External decode helper for the OffRamp lookup. Do not call directly.
    /// @dev Decoding runs in an external self-call so a mismatched payload fails inside `try/catch`.
    function decodeTypeAndVersion(bytes calldata data) external pure returns (string memory) {
        return abi.decode(data, (string));
    }

    /// @notice External decode helper for the OffRamp lookup. Do not call directly.
    function decodeSourceChainConfigV2(bytes calldata data)
        external
        pure
        returns (IOffRampSourceConfigV2Fork.SourceChainConfig memory)
    {
        return abi.decode(data, (IOffRampSourceConfigV2Fork.SourceChainConfig));
    }

    /// @notice External decode helper for the OffRamp lookup. Do not call directly.
    function decodeSourceChainConfigV1dot6(bytes calldata data)
        external
        pure
        returns (IOffRampSourceConfigFork.SourceChainConfig memory)
    {
        return abi.decode(data, (IOffRampSourceConfigFork.SourceChainConfig));
    }

    /// @notice External decode helper for the OffRamp lookup. Do not call directly.
    function decodeStaticConfigPreV1dot6(bytes calldata data)
        external
        pure
        returns (IEVM2EVMOffRampStaticConfigFork.StaticConfig memory)
    {
        return abi.decode(data, (IEVM2EVMOffRampStaticConfigFork.StaticConfig));
    }

    /// @notice Returns the OnRamp on the current (source) fork that emitted `emitter`'s log towards
    ///         `destChainSelector`, checking the Register router and then the CCIP 2.0 router. address(0) if neither.
    function _findSourceOnRamp(uint64 destChainSelector, address emitter) internal view returns (address onRamp) {
        address[2] memory routers = _routersOnCurrentChain();
        for (uint256 i; i < routers.length; ++i) {
            if (routers[i] == address(0)) {
                continue;
            }
            (bool ok, bytes memory data) =
                routers[i].staticcall(abi.encodeWithSelector(IRouterFork.getOnRamp.selector, destChainSelector));
            if (ok && data.length == 32 && abi.decode(data, (address)) == emitter && emitter != address(0)) {
                return emitter;
            }
        }
        return address(0);
    }

    /// @notice Returns the destination OffRamp for the lane of `sourceOnRamp`, searching the OffRamps of the Register
    ///         router and then of the CCIP 2.0 router on the current fork.
    function _findOffRampOnCurrentFork(uint64 sourceChainSelector, address sourceOnRamp)
        internal
        view
        returns (address offRampAddress)
    {
        address[2] memory routers = _routersOnCurrentChain();
        for (uint256 i; i < routers.length; ++i) {
            if (routers[i] == address(0)) {
                continue;
            }
            (bool ok, bytes memory data) =
                routers[i].staticcall(abi.encodeWithSelector(IRouterFork.getOffRamps.selector));
            if (!ok) {
                continue;
            }
            try this.decodeRouterOffRamps(data) returns (CCIPForkAdapterTypes.RouterOffRamp[] memory offRamps) {
                offRampAddress = _findOffRampForOnRamp(offRamps, sourceChainSelector, sourceOnRamp);
            } catch {}
            if (offRampAddress != address(0)) {
                return offRampAddress;
            }
        }
        return address(0);
    }

    /// @return routers The Register router and the CCIP 2.0 router (address(0) if unset or identical) of this chain.
    function _routersOnCurrentChain() internal view returns (address[2] memory routers) {
        routers[0] = i_register.getNetworkDetails(block.chainid).routerAddress;
        address ccipV2Router = s_ccipV2Routers[block.chainid];
        if (ccipV2Router != routers[0]) {
            routers[1] = ccipV2Router;
        }
    }

    /// @notice External decode helper for router `getOffRamps` return data. Do not call directly.
    function decodeRouterOffRamps(bytes calldata data)
        external
        pure
        returns (CCIPForkAdapterTypes.RouterOffRamp[] memory)
    {
        return abi.decode(data, (CCIPForkAdapterTypes.RouterOffRamp[]));
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

    function _startsWith(bytes memory value, bytes memory prefix) internal pure returns (bool) {
        if (prefix.length > value.length) {
            return false;
        }
        for (uint256 i; i < prefix.length; ++i) {
            if (value[i] != prefix[i]) {
                return false;
            }
        }
        return true;
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
