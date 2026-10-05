// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, Vm} from "forge-std/Test.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {CCIPLocalSimulatorFork, IOffRampSourceConfigV2Fork} from "../../../src/ccip/CCIPLocalSimulatorFork.sol";
import {Register} from "../../../src/ccip/Register.sol";
import {CCIPForkAdapterTypes} from "../../../src/ccip/adapters/CCIPForkAdapterTypes.sol";
import {CCIPForkAdapterV2} from "../../../src/ccip/adapters/CCIPForkAdapterV2.sol";
import {MessageV1Codec} from "@chainlink/contracts-ccip/contracts/libraries/MessageV1Codec.sol";

/// @dev Exposes the CCIP 2.0 routing entrypoint and processed-message state for unit testing.
contract CCIPLocalSimulatorForkV2Harness is CCIPLocalSimulatorFork {
    function exposedRouteV2(Vm.Log memory entry, uint64 sourceChainSelector) external returns (bool) {
        return _routeV2Message(entry, sourceChainSelector, false);
    }

    function exposedFindSourceOnRamp(uint64 destChainSelector, address emitter) external view returns (address) {
        return _findSourceOnRamp(destChainSelector, emitter);
    }

    function exposedFindOffRampOnCurrentFork(uint64 sourceChainSelector, address sourceOnRamp)
        external
        view
        returns (address)
    {
        return _findOffRampOnCurrentFork(sourceChainSelector, sourceOnRamp);
    }

    function exposedSetLaneDefaultCCVs(address offRamp, uint64 sourceChainSelector, address ccv) external {
        _setLaneDefaultCCVs(offRamp, sourceChainSelector, ccv);
    }

    function exposedLogDestination(Vm.Log memory entry) external pure returns (bool hasDestination, uint64 selector) {
        return _logDestinationChainSelector(entry, _detectEraFromLog(entry));
    }

    function exposedStampedV2OffRamp(bytes memory encodedMessage) external pure returns (address) {
        return _stampedV2OffRamp(encodedMessage);
    }

    function isProcessed(bytes32 messageId) external view returns (bool) {
        return s_processedMessages[messageId];
    }
}

contract MockRouterV2 {
    CCIPForkAdapterTypes.RouterOffRamp[] internal s_offRamps;
    mapping(uint64 destChainSelector => address onRamp) internal s_onRamps;

    function setOnRamp(uint64 destChainSelector, address onRamp) external {
        s_onRamps[destChainSelector] = onRamp;
    }

    function getOnRamp(uint64 destChainSelector) external view returns (address) {
        return s_onRamps[destChainSelector];
    }

    function addOffRamp(uint64 sourceChainSelector, address offRamp) external {
        s_offRamps.push(
            CCIPForkAdapterTypes.RouterOffRamp({sourceChainSelector: sourceChainSelector, offRamp: offRamp})
        );
    }

    function getOffRamps() external view returns (CCIPForkAdapterTypes.RouterOffRamp[] memory) {
        return s_offRamps;
    }
}

/// @dev OffRamp 2.0.0 double for the permissionless `execute` path. Like the real contract, `execute` does NOT revert
///      when the inner execution fails on a first attempt: it records FAILURE and returns normally.
contract MockOffRampV2Execute {
    uint8 internal constant SUCCESS = 2;
    uint8 internal constant FAILURE = 3;

    uint64 internal immutable i_sourceChainSelector;
    address internal immutable i_onRamp;
    address[] internal s_requiredCCVs;
    address[] internal s_optionalCCVs;
    uint8 internal s_threshold;
    bool internal s_innerExecutionFails;
    bytes internal s_innerRevertData = abi.encodeWithSignature("ReceiverError(bytes)", hex"dead");

    error NoStateProgressMade(bytes32 messageId, bytes err);
    bool internal s_garbageCCVs;

    mapping(bytes32 messageId => uint8 state) internal s_states;
    uint256 public executeCount;
    address[] internal s_lastCCVs;
    bytes[] internal s_lastVerifierResults;

    constructor(uint64 sourceChainSelector_, address onRamp_, address[] memory requiredCCVs_) {
        i_sourceChainSelector = sourceChainSelector_;
        i_onRamp = onRamp_;
        s_requiredCCVs = requiredCCVs_;
    }

    function setInnerExecutionFails(bool fails) external {
        s_innerExecutionFails = fails;
    }

    function setOptionalCCVs(address[] calldata optionalCCVs, uint8 threshold) external {
        s_optionalCCVs = optionalCCVs;
        s_threshold = threshold;
    }

    function setGarbageCCVs(bool garbage) external {
        s_garbageCCVs = garbage;
    }

    function typeAndVersion() external pure returns (string memory) {
        return "OffRamp 2.0.0";
    }

    function getSourceChainConfig(uint64 sourceChainSelector)
        external
        view
        returns (IOffRampSourceConfigV2Fork.SourceChainConfig memory cfg)
    {
        if (sourceChainSelector != i_sourceChainSelector) return cfg;
        cfg.isEnabled = true;
        cfg.onRamps = new bytes[](1);
        cfg.onRamps[0] = abi.encode(i_onRamp);
    }

    function getCCVsForMessage(bytes calldata)
        external
        view
        returns (address[] memory requiredCCVs, address[] memory optionalCCVs, uint8 threshold)
    {
        if (s_garbageCCVs) {
            assembly {
                mstore(0, 0x0102030000000000000000000000000000000000000000000000000000000000)
                return(0, 3)
            }
        }
        return (s_requiredCCVs, s_optionalCCVs, s_threshold);
    }

    function execute(bytes calldata encodedMessage, address[] calldata ccvs, bytes[] calldata verifierResults, uint32)
        external
    {
        bytes32 messageId = keccak256(encodedMessage);
        // OffRamp 2.0: a failed first attempt records FAILURE and returns; a failed retry reverts with the inner error.
        if (s_innerExecutionFails && s_states[messageId] == FAILURE) {
            revert NoStateProgressMade(messageId, s_innerRevertData);
        }
        executeCount += 1;
        s_lastCCVs = ccvs;
        delete s_lastVerifierResults;
        for (uint256 i; i < verifierResults.length; ++i) {
            s_lastVerifierResults.push(verifierResults[i]);
        }
        s_states[keccak256(encodedMessage)] = s_innerExecutionFails ? FAILURE : SUCCESS;
    }

    function getExecutionState(bytes32 messageId) external view returns (uint8) {
        return s_states[messageId];
    }

    function lastCCVs() external view returns (address[] memory) {
        return s_lastCCVs;
    }

    function lastVerifierResults() external view returns (bytes[] memory) {
        return s_lastVerifierResults;
    }
}

/// @dev Owner-configurable versioned verifier resolver double (the production CCV shape on 2.0 lanes).
contract MockVersionedResolver {
    struct InboundImplementationArgs {
        bytes4 version;
        address verifier;
    }

    address public owner = address(0x0A11);
    bytes4 public configuredVersion;
    address public configuredVerifier;

    function applyInboundImplementationUpdates(InboundImplementationArgs[] calldata implementations) external {
        require(msg.sender == owner, "only owner");
        configuredVersion = implementations[0].version;
        configuredVerifier = implementations[0].verifier;
    }

    function getInboundImplementation(bytes calldata verifierResults) external view returns (address) {
        return bytes4(verifierResults[:4]) == configuredVersion ? configuredVerifier : address(0);
    }
}

contract CCIPLocalSimulatorForkV2RoutingTest is Test {
    uint64 internal constant SOURCE_SELECTOR = 16015286601757825753;
    address internal constant ON_RAMP = address(0x2000);

    CCIPLocalSimulatorForkV2Harness internal harness;
    MockRouterV2 internal router;

    function setUp() public {
        harness = new CCIPLocalSimulatorForkV2Harness();
        router = new MockRouterV2();
        harness.setNetworkDetails(
            block.chainid,
            Register.NetworkDetails({
                chainSelector: 3478487238524512106,
                routerAddress: address(router),
                linkAddress: address(0),
                wrappedNativeAddress: address(0),
                ccipBnMAddress: address(0),
                ccipLnMAddress: address(0),
                rmnProxyAddress: address(0),
                registryModuleOwnerCustomAddress: address(0),
                tokenAdminRegistryAddress: address(0)
            })
        );
    }

    function _entry(bytes memory encodedMessage, CCIPForkAdapterTypes.V2Receipt[] memory receipts)
        internal
        pure
        returns (Vm.Log memory entry)
    {
        entry.topics = new bytes32[](4);
        entry.topics[0] = CCIPForkAdapterV2.eventSelector();
        entry.topics[1] = bytes32(uint256(3478487238524512106));
        entry.topics[2] = bytes32(uint256(uint160(address(0xA11CE))));
        entry.topics[3] = keccak256(encodedMessage);
        entry.data = abi.encode(address(0), uint256(0), encodedMessage, receipts, new bytes[](0));
        entry.emitter = ON_RAMP;
    }

    function _offRamp(address onRamp, address[] memory ccvs) internal returns (MockOffRampV2Execute offRamp) {
        offRamp = new MockOffRampV2Execute(SOURCE_SELECTOR, onRamp, ccvs);
        router.addOffRamp(SOURCE_SELECTOR, address(offRamp));
    }

    function test_defaultVerificationModeIsOffRampDerived() public {
        CCIPLocalSimulatorFork fresh = new CCIPLocalSimulatorFork();
        assertEq(uint8(fresh.getV2VerificationMode()), uint8(CCIPLocalSimulatorFork.V2VerificationMode.OFFRAMP_DERIVED));
    }

    function test_offRampDerived_successMarksProcessed() public {
        MockOffRampV2Execute offRamp = _offRamp(ON_RAMP, new address[](0));
        Vm.Log memory entry = _entry("message", new CCIPForkAdapterTypes.V2Receipt[](0));

        assertTrue(harness.exposedRouteV2(entry, SOURCE_SELECTOR));
        assertEq(offRamp.executeCount(), 1);
        assertTrue(harness.isProcessed(entry.topics[3]));
    }

    /// @dev OffRamp 2.0 `execute` returns normally on a first-attempt failure, so success must be read from
    ///      `getExecutionState`, not from the call not reverting.
    function test_offRampDerived_failureStateIsNotMarkedProcessed() public {
        MockOffRampV2Execute offRamp = _offRamp(ON_RAMP, new address[](0));
        offRamp.setInnerExecutionFails(true);
        Vm.Log memory entry = _entry("message", new CCIPForkAdapterTypes.V2Receipt[](0));
        harness.setStrictRouting(false);

        assertTrue(harness.exposedRouteV2(entry, SOURCE_SELECTOR));
        assertEq(offRamp.executeCount(), 1);
        assertFalse(harness.isProcessed(entry.topics[3]));
    }

    /// @dev Only the OffRamp bound to the emitting OnRamp is executed, not every OffRamp on the router.
    function test_offRampDerived_onlyExecutesLaneOffRamp() public {
        MockOffRampV2Execute lane = _offRamp(ON_RAMP, new address[](0));
        MockOffRampV2Execute otherLane = _offRamp(address(0x3000), new address[](0));
        Vm.Log memory entry = _entry("message", new CCIPForkAdapterTypes.V2Receipt[](0));

        assertTrue(harness.exposedRouteV2(entry, SOURCE_SELECTOR));
        assertEq(lane.executeCount(), 1);
        assertEq(otherLane.executeCount(), 0);
    }

    function test_offRampDerived_returnsFalseWhenNoLaneOffRamp() public {
        MockOffRampV2Execute otherLane = _offRamp(address(0x3000), new address[](0));
        Vm.Log memory entry = _entry("message", new CCIPForkAdapterTypes.V2Receipt[](0));

        assertFalse(harness.exposedRouteV2(entry, SOURCE_SELECTOR));
        assertEq(otherLane.executeCount(), 0);
    }

    /// @dev Resolver-style CCVs get the synthetic fork verifier, so lanes work without mocking default CCVs.
    ///      CCVs that cannot be reconfigured (e.g. a `CCVNoOpVerifier` set via `setLaneDefaultCCVs`) get an empty result.
    function test_offRampDerived_usesSyntheticResultForResolverCCVs() public {
        MockVersionedResolver resolver = new MockVersionedResolver();
        address plainCCV = address(0xCC5);
        address[] memory ccvs = new address[](2);
        ccvs[0] = address(resolver);
        ccvs[1] = plainCCV;
        MockOffRampV2Execute offRamp = _offRamp(ON_RAMP, ccvs);

        assertTrue(harness.exposedRouteV2(_entry("message", new CCIPForkAdapterTypes.V2Receipt[](0)), SOURCE_SELECTOR));

        address[] memory usedCCVs = offRamp.lastCCVs();
        bytes[] memory results = offRamp.lastVerifierResults();
        assertEq(usedCCVs.length, 2);
        assertEq(usedCCVs[0], address(resolver));
        assertEq(results[0], abi.encodePacked(bytes4(0x464f524b))); // "FORK"
        assertEq(results[1].length, 0);
        assertEq(resolver.configuredVersion(), bytes4(0x464f524b));
        assertTrue(resolver.configuredVerifier() != address(0));
    }

    /// @dev `vm.rollFork` or a snapshot revert on the destination fork drops the resolver update and the synthetic
    ///      verifier's code, while the persistent simulator's storage survives. Routing must set both up again.
    function test_offRampDerived_reconfiguresResolverAfterForkStateReset() public {
        MockVersionedResolver resolver = new MockVersionedResolver();
        address[] memory ccvs = new address[](1);
        ccvs[0] = address(resolver);
        MockOffRampV2Execute offRamp = _offRamp(ON_RAMP, ccvs);

        assertTrue(harness.exposedRouteV2(_entry("first", new CCIPForkAdapterTypes.V2Receipt[](0)), SOURCE_SELECTOR));
        address firstVerifier = resolver.configuredVerifier();
        assertTrue(firstVerifier.code.length > 0);

        // Simulate the reset: the resolver no longer knows "FORK", and the verifier has no code.
        MockVersionedResolver.InboundImplementationArgs[] memory reset =
            new MockVersionedResolver.InboundImplementationArgs[](1);
        reset[0] = MockVersionedResolver.InboundImplementationArgs({version: bytes4(0), verifier: address(0)});
        vm.prank(resolver.owner());
        resolver.applyInboundImplementationUpdates(reset);
        vm.etch(firstVerifier, "");

        assertTrue(harness.exposedRouteV2(_entry("second", new CCIPForkAdapterTypes.V2Receipt[](0)), SOURCE_SELECTOR));
        assertEq(resolver.configuredVersion(), bytes4(0x464f524b)); // "FORK"
        assertTrue(resolver.configuredVerifier().code.length > 0);
        assertEq(offRamp.lastVerifierResults()[0], abi.encodePacked(bytes4(0x464f524b)));
    }

    /// @dev MessageV1 wire prefix up to the OffRamp address (69-byte fixed header, onRamp, offRamp), then a tail.
    function _encodedMessageStampedWith(address offRamp) internal pure returns (bytes memory) {
        return abi.encodePacked(new bytes(69), uint8(32), abi.encode(ON_RAMP), uint8(20), offRamp, "tail");
    }

    /// @dev OffRamp 2.0 only executes a message stamped with its own address (`InvalidOffRamp`). When the routers list
    ///      several OffRamps for the lane (e.g. during an OffRamp upgrade), routing must use the stamped one, not the
    ///      newest match of the router lookup.
    function test_offRampDerived_prefersOffRampStampedInMessage() public {
        MockOffRampV2Execute stamped = _offRamp(ON_RAMP, new address[](0));
        MockOffRampV2Execute newer = _offRamp(ON_RAMP, new address[](0));

        Vm.Log memory entry =
            _entry(_encodedMessageStampedWith(address(stamped)), new CCIPForkAdapterTypes.V2Receipt[](0));
        assertTrue(harness.exposedRouteV2(entry, SOURCE_SELECTOR));
        assertEq(stamped.executeCount(), 1);
        assertEq(newer.executeCount(), 0);
    }

    /// @dev The offset arithmetic of `_stampedV2OffRamp` agrees with the pinned `MessageV1Codec` encoder.
    function testFuzz_stampedV2OffRamp_matchesCodec(address offRamp, bytes memory onRamp, bytes memory data)
        public
        view
    {
        vm.assume(onRamp.length <= 255);
        MessageV1Codec.MessageV1 memory message;
        message.onRampAddress = onRamp;
        message.offRampAddress = abi.encodePacked(offRamp);
        message.sender = abi.encode(address(0xA11CE));
        message.receiver = abi.encodePacked(address(0xB0B));
        message.data = data;
        assertEq(harness.exposedStampedV2OffRamp(MessageV1Codec._encodeMessageV1(message)), offRamp);
    }

    /// @dev OnRamp addresses longer than 185 bytes overflowed a uint8 offset (found by the fuzz test in CI).
    function test_stampedV2OffRamp_longOnRampAddress() public view {
        MessageV1Codec.MessageV1 memory message;
        message.onRampAddress = new bytes(255);
        message.offRampAddress = abi.encodePacked(address(0xFEED));
        message.sender = abi.encode(address(0xA11CE));
        message.receiver = abi.encodePacked(address(0xB0B));
        assertEq(harness.exposedStampedV2OffRamp(MessageV1Codec._encodeMessageV1(message)), address(0xFEED));
    }

    function test_stampedV2OffRamp_malformedReturnsZero() public view {
        assertEq(harness.exposedStampedV2OffRamp("message"), address(0));
        assertEq(harness.exposedStampedV2OffRamp(abi.encodePacked(new bytes(69), uint8(32))), address(0));
        // A 32-byte (non-EVM) OffRamp address.
        assertEq(
            harness.exposedStampedV2OffRamp(
                abi.encodePacked(new bytes(69), uint8(32), abi.encode(ON_RAMP), uint8(32), bytes32(uint256(1)))
            ),
            address(0)
        );
    }

    /// @dev A stamped address that does not serve the lane (no code, other OnRamp) is ignored in favour of the lookup.
    function test_offRampDerived_stampedOffRampNotServingLane_usesLookup() public {
        MockOffRampV2Execute otherLane = new MockOffRampV2Execute(SOURCE_SELECTOR, address(0xBEEF), new address[](0));
        MockOffRampV2Execute laneOffRamp = _offRamp(ON_RAMP, new address[](0));

        assertTrue(
            harness.exposedRouteV2(
                _entry(_encodedMessageStampedWith(address(otherLane)), new CCIPForkAdapterTypes.V2Receipt[](0)),
                SOURCE_SELECTOR
            )
        );
        assertTrue(
            harness.exposedRouteV2(
                _entry(_encodedMessageStampedWith(address(0xDEAD)), new CCIPForkAdapterTypes.V2Receipt[](0)),
                SOURCE_SELECTOR
            )
        );
        assertEq(otherLane.executeCount(), 0);
        assertEq(laneOffRamp.executeCount(), 2);
    }

    function test_offRampDerived_garbageCCVResponseDoesNotRevert() public {
        MockOffRampV2Execute offRamp = _offRamp(ON_RAMP, new address[](0));
        offRamp.setGarbageCCVs(true);

        harness.exposedRouteV2(_entry("message", new CCIPForkAdapterTypes.V2Receipt[](0)), SOURCE_SELECTOR);
    }

    /// @dev `RESPECT_NO_EXEC` (default) queues NO_EXECUTION messages in OFFRAMP_DERIVED mode too.
    function test_offRampDerived_noExecutionMessageIsQueuedThenExecutable() public {
        MockOffRampV2Execute offRamp = _offRamp(ON_RAMP, new address[](0));
        CCIPForkAdapterTypes.V2Receipt[] memory receipts = new CCIPForkAdapterTypes.V2Receipt[](2);
        receipts[0].issuer = Client.NO_EXECUTION_ADDRESS;
        receipts[1].issuer = address(0xFEE);
        Vm.Log memory entry = _entry("message", receipts);
        bytes32 messageId = entry.topics[3];

        assertTrue(harness.exposedRouteV2(entry, SOURCE_SELECTOR));
        assertEq(offRamp.executeCount(), 0);
        assertTrue(harness.isPendingV2Message(messageId));

        assertTrue(harness.executePendingV2Message(messageId));
        assertEq(offRamp.executeCount(), 1);
        assertTrue(harness.isProcessed(messageId));
        assertFalse(harness.isPendingV2Message(messageId));
    }

    // ================================================================
    // │                  CCIP 2.0 parallel routers                    │
    // ================================================================

    function test_ccipV2RouterDefaults() public view {
        assertEq(harness.getCCIPV2RouterAddress(11155111), 0x784d49a71BB4C48eB7dA4cD7e6Ecb424f9b5EAB1);
        assertEq(harness.getCCIPV2RouterAddress(43113), 0x7C9B8B4e8024e5Ee8A630F6FCe9015e470dA5763);
        assertEq(harness.getCCIPV2RouterAddress(1), address(0));
    }

    function test_setCCIPV2RouterAddress() public {
        harness.setCCIPV2RouterAddress(421614, address(0xB0B));
        assertEq(harness.getCCIPV2RouterAddress(421614), address(0xB0B));
    }

    /// @dev A message sent through the CCIP 2.0 router is emitted by that router's OnRamp, not the Register router's.
    function test_findSourceOnRamp_matchesEitherRouter() public {
        uint64 dest = 3478487238524512106;
        router.setOnRamp(dest, address(0xAAA1));
        MockRouterV2 v2Router = new MockRouterV2();
        v2Router.setOnRamp(dest, address(0xBBB2));
        harness.setCCIPV2RouterAddress(block.chainid, address(v2Router));

        assertEq(harness.exposedFindSourceOnRamp(dest, address(0xAAA1)), address(0xAAA1));
        assertEq(harness.exposedFindSourceOnRamp(dest, address(0xBBB2)), address(0xBBB2));
        assertEq(harness.exposedFindSourceOnRamp(dest, address(0xCCC3)), address(0));
    }

    function test_findSourceOnRamp_withoutV2Router() public {
        uint64 dest = 3478487238524512106;
        router.setOnRamp(dest, address(0xAAA1));

        assertEq(harness.exposedFindSourceOnRamp(dest, address(0xAAA1)), address(0xAAA1));
        assertEq(harness.exposedFindSourceOnRamp(dest, address(0xBBB2)), address(0));
    }

    /// @dev The destination OffRamp of a CCIP 2.0-router lane is only listed by the 2.0 router.
    function test_findOffRamp_consultsV2Router() public {
        MockRouterV2 v2Router = new MockRouterV2();
        MockOffRampV2Execute laneOffRamp = new MockOffRampV2Execute(SOURCE_SELECTOR, ON_RAMP, new address[](0));
        v2Router.addOffRamp(SOURCE_SELECTOR, address(laneOffRamp));
        _offRamp(address(0x3000), new address[](0)); // Register router only knows another lane

        assertEq(harness.exposedFindOffRampOnCurrentFork(SOURCE_SELECTOR, ON_RAMP), address(0));

        harness.setCCIPV2RouterAddress(block.chainid, address(v2Router));
        assertEq(harness.exposedFindOffRampOnCurrentFork(SOURCE_SELECTOR, ON_RAMP), address(laneOffRamp));

        assertTrue(harness.exposedRouteV2(_entry("message", new CCIPForkAdapterTypes.V2Receipt[](0)), SOURCE_SELECTOR));
        assertEq(laneOffRamp.executeCount(), 1);
    }

    /// @dev A router returning junk from `getOffRamps` is skipped instead of reverting the lookup.
    function test_findOffRamp_skipsRouterWithGarbageOffRamps() public {
        MockRouterV2 v2Router = new MockRouterV2();
        MockOffRampV2Execute laneOffRamp = new MockOffRampV2Execute(SOURCE_SELECTOR, ON_RAMP, new address[](0));
        v2Router.addOffRamp(SOURCE_SELECTOR, address(laneOffRamp));
        harness.setCCIPV2RouterAddress(block.chainid, address(v2Router));
        vm.etch(address(router), address(new GarbageRouter()).code);

        assertEq(harness.exposedFindOffRampOnCurrentFork(SOURCE_SELECTOR, ON_RAMP), address(laneOffRamp));
    }

    /// @dev Review repro: required=[A], optional=[B, C], threshold=1. The OffRamp needs A plus one optional CCV; selecting
    ///      only [A] fails with `OptionalCCVQuorumNotReached` where production delivers.
    function test_offRampDerived_selectsRequiredPlusThresholdOptionalCCVs() public {
        address a = address(0xA0);
        address b = address(0xB0);
        address c = address(0xC0);
        address[] memory required = new address[](1);
        required[0] = a;
        address[] memory optional = new address[](2);
        optional[0] = b;
        optional[1] = c;
        MockOffRampV2Execute offRamp = _offRamp(ON_RAMP, required);
        offRamp.setOptionalCCVs(optional, 1);

        assertTrue(harness.exposedRouteV2(_entry("message", new CCIPForkAdapterTypes.V2Receipt[](0)), SOURCE_SELECTOR));

        address[] memory used = offRamp.lastCCVs();
        assertEq(used.length, 2);
        assertEq(used[0], a);
        assertEq(used[1], b);
    }

    // ================================================================
    // │                 Observable routing outcomes                  │
    // ================================================================

    function test_strictRoutingIsOnByDefault() public {
        assertTrue(new CCIPLocalSimulatorFork().getStrictRouting());
    }

    function test_getMessageStatus_notFoundForUnknownMessage() public view {
        (CCIPLocalSimulatorFork.MessageStatus status, bytes memory reason) =
            harness.getMessageStatus(bytes32(uint256(1)));
        assertEq(uint8(status), uint8(CCIPLocalSimulatorFork.MessageStatus.NOT_FOUND));
        assertEq(reason.length, 0);
    }

    function test_getMessageStatus_successAfterRouting() public {
        _offRamp(ON_RAMP, new address[](0));
        Vm.Log memory entry = _entry("message", new CCIPForkAdapterTypes.V2Receipt[](0));

        harness.exposedRouteV2(entry, SOURCE_SELECTOR);

        (CCIPLocalSimulatorFork.MessageStatus status,) = harness.getMessageStatus(entry.topics[3]);
        assertEq(uint8(status), uint8(CCIPLocalSimulatorFork.MessageStatus.SUCCESS));
    }

    /// @dev Strict mode (default): a CCIP 2.0 FAILURE reverts with the OffRamp's inner error, recovered from the
    ///      `NoStateProgressMade(messageId, err)` revert of a second `execute` attempt.
    function test_strict_executionFailureReverts_withDecodedReason() public {
        MockOffRampV2Execute offRamp = _offRamp(ON_RAMP, new address[](0));
        offRamp.setInnerExecutionFails(true);
        Vm.Log memory entry = _entry("message", new CCIPForkAdapterTypes.V2Receipt[](0));

        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPLocalSimulatorFork.CCIPLocalSimulatorFork__MessageExecutionFailed.selector,
                entry.topics[3],
                abi.encodeWithSignature("ReceiverError(bytes)", hex"dead")
            )
        );
        harness.exposedRouteV2(entry, SOURCE_SELECTOR);
    }

    function test_nonStrict_executionFailureRecorded_withDecodedReason() public {
        MockOffRampV2Execute offRamp = _offRamp(ON_RAMP, new address[](0));
        offRamp.setInnerExecutionFails(true);
        Vm.Log memory entry = _entry("message", new CCIPForkAdapterTypes.V2Receipt[](0));
        harness.setStrictRouting(false);

        assertTrue(harness.exposedRouteV2(entry, SOURCE_SELECTOR));

        (CCIPLocalSimulatorFork.MessageStatus status, bytes memory reason) = harness.getMessageStatus(entry.topics[3]);
        assertEq(uint8(status), uint8(CCIPLocalSimulatorFork.MessageStatus.FAILED));
        assertEq(reason, abi.encodeWithSignature("ReceiverError(bytes)", hex"dead"));
        assertFalse(harness.isProcessed(entry.topics[3]));
    }

    function test_getMessageStatus_queuedForNoExecutionMessage() public {
        _offRamp(ON_RAMP, new address[](0));
        CCIPForkAdapterTypes.V2Receipt[] memory receipts = new CCIPForkAdapterTypes.V2Receipt[](2);
        receipts[0].issuer = Client.NO_EXECUTION_ADDRESS;
        receipts[1].issuer = address(0xFEE);
        Vm.Log memory entry = _entry("message", receipts);

        harness.exposedRouteV2(entry, SOURCE_SELECTOR);

        (CCIPLocalSimulatorFork.MessageStatus status,) = harness.getMessageStatus(entry.topics[3]);
        assertEq(uint8(status), uint8(CCIPLocalSimulatorFork.MessageStatus.QUEUED));
    }

    /// @dev The OffRamp keys execution state on keccak256(encodedMessage); a log whose messageId topic differs is not a
    ///      genuine CCIP 2.0 message and must not be executed.
    function test_messageIdTopicMustMatchEncodedMessage() public {
        MockOffRampV2Execute offRamp = _offRamp(ON_RAMP, new address[](0));
        Vm.Log memory entry = _entry("message", new CCIPForkAdapterTypes.V2Receipt[](0));
        entry.topics[3] = bytes32(uint256(0xBAD));

        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPLocalSimulatorFork.CCIPLocalSimulatorFork__MessageNotRouted.selector,
                bytes32(uint256(0xBAD)),
                "messageId topic does not match keccak256(encodedMessage)"
            )
        );
        harness.exposedRouteV2(entry, SOURCE_SELECTOR);
        assertEq(offRamp.executeCount(), 0);
    }

    /// @dev 1.6 OnRamps serve several destinations, so 1.6 logs must be filtered by destination like 2.0 logs.
    function test_logDestination_readFromTopic1ForV1dot6AndV2() public view {
        Vm.Log memory v2 = _entry("message", new CCIPForkAdapterTypes.V2Receipt[](0));
        (bool hasV2, uint64 v2Selector) = harness.exposedLogDestination(v2);
        assertTrue(hasV2);
        assertEq(v2Selector, 3478487238524512106);

        Vm.Log memory v16;
        v16.topics = new bytes32[](3);
        v16.topics[0] = keccak256(
            "CCIPMessageSent(uint64,uint64,((bytes32,uint64,uint64,uint64,uint64),address,bytes,bytes,bytes,address,uint256,uint256,(address,bytes,bytes,uint256,bytes)[]))"
        );
        v16.topics[1] = bytes32(uint256(14767482510784806043));
        (bool has16, uint64 selector16) = harness.exposedLogDestination(v16);
        assertTrue(has16);
        assertEq(selector16, 14767482510784806043);
    }

    /// @dev A foreign event with the CCIP 2.0 signature but fewer indexed topics must not panic the routing loop.
    function test_logDestination_shortTopicsDoNotPanic() public view {
        Vm.Log memory entry;
        entry.topics = new bytes32[](1);
        entry.topics[0] = CCIPForkAdapterV2.eventSelector();
        (bool hasDestination,) = harness.exposedLogDestination(entry);
        assertFalse(hasDestination);
    }

    /// @dev `setLaneDefaultCCVs` must not make the lane less strict than production: lane-mandated CCVs are kept.
    function test_setLaneDefaultCCVs_preservesLaneMandatedCCVs() public {
        MockOffRampV2Admin offRamp = new MockOffRampV2Admin(SOURCE_SELECTOR, ON_RAMP);
        harness.exposedSetLaneDefaultCCVs(address(offRamp), SOURCE_SELECTOR, address(0xC0DE));

        IOffRampSourceConfigV2Fork.SourceChainConfig memory cfg = offRamp.getSourceChainConfig(SOURCE_SELECTOR);
        assertEq(cfg.defaultCCVs.length, 1);
        assertEq(cfg.defaultCCVs[0], address(0xC0DE));
        assertEq(cfg.laneMandatedCCVs.length, 1);
        assertEq(cfg.laneMandatedCCVs[0], address(0x3A7D));
        assertEq(cfg.onRamps.length, 1);
        assertEq(cfg.router, address(0xBEEF));
    }

    /// @dev A router whose `getOnRamp` returns a word that is not an address is skipped, not reverted on.
    function test_findSourceOnRamp_nonAddressWordDoesNotRevert() public {
        vm.etch(address(router), address(new NonAddressWordRouter()).code);
        assertEq(harness.exposedFindSourceOnRamp(3478487238524512106, ON_RAMP), address(0));
    }
}

/// @dev Returns a 32-byte word with high bits set from every call.
contract NonAddressWordRouter {
    fallback() external {
        assembly {
            mstore(0, not(0))
            return(0, 32)
        }
    }
}

/// @dev OffRamp 2.0 admin surface used by `setLaneDefaultCCVs`.
contract MockOffRampV2Admin {
    address public owner = address(0x0B0B);
    mapping(uint64 => IOffRampSourceConfigV2Fork.SourceChainConfig) internal s_configs;

    constructor(uint64 sourceChainSelector, address onRamp) {
        IOffRampSourceConfigV2Fork.SourceChainConfig storage cfg = s_configs[sourceChainSelector];
        cfg.router = address(0xBEEF);
        cfg.isEnabled = true;
        cfg.onRamps.push(abi.encode(onRamp));
        cfg.defaultCCVs.push(address(0xDEF0));
        cfg.laneMandatedCCVs.push(address(0x3A7D));
    }

    function getSourceChainConfig(uint64 sourceChainSelector)
        external
        view
        returns (IOffRampSourceConfigV2Fork.SourceChainConfig memory)
    {
        return s_configs[sourceChainSelector];
    }

    function applySourceChainConfigUpdates(IOffRampSourceConfigV2Fork.SourceChainConfigArgs[] calldata updates)
        external
    {
        require(msg.sender == owner, "only owner");
        for (uint256 i; i < updates.length; ++i) {
            IOffRampSourceConfigV2Fork.SourceChainConfig storage cfg = s_configs[updates[i].sourceChainSelector];
            cfg.router = updates[i].router;
            cfg.isEnabled = updates[i].isEnabled;
            delete cfg.onRamps;
            for (uint256 j; j < updates[i].onRamps.length; ++j) {
                cfg.onRamps.push(updates[i].onRamps[j]);
            }
            cfg.defaultCCVs = updates[i].defaultCCVs;
            cfg.laneMandatedCCVs = updates[i].laneMandatedCCVs;
        }
    }
}

contract GarbageRouter {
    fallback() external {
        assembly {
            mstore(0, 0x0102030000000000000000000000000000000000000000000000000000000000)
            return(0, 3)
        }
    }
}
