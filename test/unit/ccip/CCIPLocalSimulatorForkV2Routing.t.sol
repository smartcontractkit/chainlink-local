// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, Vm} from "forge-std/Test.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {CCIPLocalSimulatorFork, IOffRampSourceConfigV2Fork} from "../../../src/ccip/CCIPLocalSimulatorFork.sol";
import {Register} from "../../../src/ccip/Register.sol";
import {CCIPForkAdapterTypes} from "../../../src/ccip/adapters/CCIPForkAdapterTypes.sol";
import {CCIPForkAdapterV2} from "../../../src/ccip/adapters/CCIPForkAdapterV2.sol";

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
    bool internal s_innerExecutionFails;
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
        return (s_requiredCCVs, new address[](0), 0);
    }

    function execute(bytes calldata encodedMessage, address[] calldata ccvs, bytes[] calldata verifierResults, uint32)
        external
    {
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
}

contract GarbageRouter {
    fallback() external {
        assembly {
            mstore(0, 0x0102030000000000000000000000000000000000000000000000000000000000)
            return(0, 3)
        }
    }
}
