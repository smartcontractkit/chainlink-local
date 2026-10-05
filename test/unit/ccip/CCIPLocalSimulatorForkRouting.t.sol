// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {
    CCIPLocalSimulatorFork,
    IOffRampSourceConfigFork,
    IOffRampSourceConfigV2Fork,
    IEVM2EVMOffRampStaticConfigFork
} from "../../../src/ccip/CCIPLocalSimulatorFork.sol";
import {CCIPForkAdapterTypes} from "../../../src/ccip/adapters/CCIPForkAdapterTypes.sol";
import {CCIPForkAdapterV1dot6} from "../../../src/ccip/adapters/CCIPForkAdapterV1dot6.sol";

/// @dev Exposes internal OffRamp resolution for unit testing.
contract CCIPLocalSimulatorForkHarness is CCIPLocalSimulatorFork {
    function exposedDecodeReceiver(bytes memory encoded) external pure returns (address) {
        return CCIPForkAdapterV1dot6._decodeEVMAddress(encoded);
    }

    function exposedExecuteV1dot6(address offRamp, CCIPForkAdapterTypes.V1dot6EVM2AnyRampMessage memory message)
        external
        returns (bool success)
    {
        vm.startPrank(offRamp);
        (success,) = CCIPForkAdapterV1dot6.execute(message, offRamp);
        vm.stopPrank();
    }

    function exposedFindOffRamp(
        CCIPForkAdapterTypes.RouterOffRamp[] calldata offRamps,
        uint64 sourceChainSelector,
        address sourceOnRamp
    ) external view returns (address) {
        CCIPForkAdapterTypes.RouterOffRamp[] memory ramps = new CCIPForkAdapterTypes.RouterOffRamp[](offRamps.length);
        for (uint256 i; i < offRamps.length; ++i) {
            ramps[i] = offRamps[i];
        }
        return _findOffRampForOnRamp(ramps, sourceChainSelector, sourceOnRamp);
    }
}

/// @dev v1.6-style OffRamp mock: `getSourceChainConfig` returns a fixed lane binding.
contract MockOffRampV16 {
    address internal immutable i_router;
    uint64 internal immutable i_sourceChainSelector;
    address internal immutable i_onRamp;
    bool internal immutable i_enabled;

    constructor(address router_, uint64 sourceChainSelector_, address onRamp_, bool enabled_) {
        i_router = router_;
        i_sourceChainSelector = sourceChainSelector_;
        i_onRamp = onRamp_;
        i_enabled = enabled_;
    }

    function getSourceChainConfig(uint64 sourceChainSelector)
        external
        view
        returns (IOffRampSourceConfigFork.SourceChainConfig memory cfg)
    {
        require(sourceChainSelector == i_sourceChainSelector, "bad selector");
        cfg.router = i_router;
        cfg.isEnabled = i_enabled;
        cfg.minSeqNr = 1;
        cfg.isRMNVerificationDisabled = false;
        cfg.onRamp = abi.encode(i_onRamp);
    }
}

/// @dev Pre-v1.6 EVM2EVMOffRamp-style mock.
contract MockOffRampPre16 {
    uint64 internal immutable i_chainSelector;
    uint64 internal immutable i_sourceChainSelector;
    address internal immutable i_onRamp;

    constructor(uint64 chainSelector_, uint64 sourceChainSelector_, address onRamp_) {
        i_chainSelector = chainSelector_;
        i_sourceChainSelector = sourceChainSelector_;
        i_onRamp = onRamp_;
    }

    function getStaticConfig() external view returns (IEVM2EVMOffRampStaticConfigFork.StaticConfig memory c) {
        c.commitStore = address(0x1);
        c.chainSelector = i_chainSelector;
        c.sourceChainSelector = i_sourceChainSelector;
        c.onRamp = i_onRamp;
        c.prevOffRamp = address(0);
        c.rmnProxy = address(0x2);
        c.tokenAdminRegistry = address(0x3);
    }
}

/// @dev Implements v1.6 getter with a wrong onRamp, then pre-v1.6 getter with the correct onRamp (defense in depth).
contract MockOffRampV16WrongThenPre16 is MockOffRampPre16 {
    address internal immutable i_wrongOnRamp;

    constructor(uint64 chainSelector_, uint64 sourceChainSelector_, address correctOnRamp_, address wrongOnRamp_)
        MockOffRampPre16(chainSelector_, sourceChainSelector_, correctOnRamp_)
    {
        i_wrongOnRamp = wrongOnRamp_;
    }

    function getSourceChainConfig(uint64 sourceChainSelector)
        external
        view
        returns (IOffRampSourceConfigFork.SourceChainConfig memory cfg)
    {
        require(sourceChainSelector == i_sourceChainSelector, "bad selector");
        cfg.router = address(0x4);
        cfg.isEnabled = true;
        cfg.minSeqNr = 1;
        cfg.isRMNVerificationDisabled = false;
        cfg.onRamp = abi.encode(i_wrongOnRamp);
    }
}

/// @dev No introspection getters — `_findOffRampForOnRamp` skips these via try/catch.
contract MockOffRampForeign {}

/// @dev v1.6 OffRamp mock that records the `Any2EVMRampMessage` it was handed.
contract MockOffRampRecorder {
    bytes public recordedSender;

    function executeSingleMessage(
        CCIPForkAdapterTypes.V1dot6Any2EVMRampMessage memory message,
        bytes[] calldata,
        uint32[] calldata
    ) external {
        recordedSender = message.sender;
    }
}

/// @dev Shape of `getStaticConfig()` on the real 1.6 and 2.0 OffRamps: 5 static words, versus 7 on pre-1.6
///      `EVM2EVMOffRamp`. Same selector, so decoding it as the pre-1.6 struct must not revert the lookup.
struct FiveWordStaticConfig {
    uint64 localChainSelector;
    uint16 gasForCallExactCheck;
    address rmnRemote;
    address tokenAdminRegistry;
    uint32 maxGasBufferToUpdateState;
}

/// @dev Faithful OffRamp 2.0.0 view surface: `getSourceChainConfig` has the 1.6 selector but the 2.0 struct.
contract MockOffRampV2Real {
    uint64 internal immutable i_sourceChainSelector;
    bool internal immutable i_enabled;
    bytes[] internal s_onRamps;

    constructor(uint64 sourceChainSelector_, address[] memory onRamps_, bool enabled_) {
        i_sourceChainSelector = sourceChainSelector_;
        i_enabled = enabled_;
        for (uint256 i; i < onRamps_.length; ++i) {
            s_onRamps.push(abi.encode(onRamps_[i]));
        }
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
        cfg.router = address(0xBEEF);
        cfg.isEnabled = i_enabled;
        cfg.onRamps = s_onRamps;
        cfg.defaultCCVs = new address[](1);
        cfg.defaultCCVs[0] = address(0xCC5);
        cfg.laneMandatedCCVs = new address[](0);
    }

    function getStaticConfig() external pure returns (FiveWordStaticConfig memory c) {
        c.localChainSelector = 1;
    }
}

/// @dev 2.0 OffRamp without `typeAndVersion`, so the lookup has to probe shapes.
contract MockOffRampV2NoTypeAndVersion {
    uint64 internal immutable i_sourceChainSelector;
    address internal immutable i_onRamp;

    constructor(uint64 sourceChainSelector_, address onRamp_) {
        i_sourceChainSelector = sourceChainSelector_;
        i_onRamp = onRamp_;
    }

    function getSourceChainConfig(uint64 sourceChainSelector)
        external
        view
        returns (IOffRampSourceConfigV2Fork.SourceChainConfig memory cfg)
    {
        if (sourceChainSelector != i_sourceChainSelector) return cfg;
        cfg.router = address(0xBEEF);
        cfg.isEnabled = true;
        cfg.onRamps = new bytes[](1);
        cfg.onRamps[0] = abi.encode(i_onRamp);
        cfg.defaultCCVs = new address[](1);
        cfg.defaultCCVs[0] = address(0xCC5);
    }

    function getStaticConfig() external pure returns (FiveWordStaticConfig memory c) {
        c.localChainSelector = 1;
    }
}

/// @dev 2.0 OffRamp whose lane lists a raw 32-byte OnRamp word that is not an EVM address (e.g. a non-EVM source).
contract MockOffRampV2RawOnRamps {
    uint64 internal immutable i_sourceChainSelector;
    bytes[] internal s_onRamps;

    constructor(uint64 sourceChainSelector_, bytes[] memory onRamps_) {
        i_sourceChainSelector = sourceChainSelector_;
        for (uint256 i; i < onRamps_.length; ++i) {
            s_onRamps.push(onRamps_[i]);
        }
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
        cfg.onRamps = s_onRamps;
    }
}

/// @dev Faithful OffRamp 1.6.x view surface, including the 5-word `getStaticConfig`.
contract MockOffRampV16Real {
    uint64 internal immutable i_sourceChainSelector;
    address internal immutable i_onRamp;

    constructor(uint64 sourceChainSelector_, address onRamp_) {
        i_sourceChainSelector = sourceChainSelector_;
        i_onRamp = onRamp_;
    }

    function typeAndVersion() external pure returns (string memory) {
        return "OffRamp 1.6.0";
    }

    function getSourceChainConfig(uint64 sourceChainSelector)
        external
        view
        returns (IOffRampSourceConfigFork.SourceChainConfig memory cfg)
    {
        if (sourceChainSelector != i_sourceChainSelector) return cfg;
        cfg.router = address(0xBEEF);
        cfg.isEnabled = true;
        cfg.minSeqNr = 1;
        cfg.onRamp = abi.encode(i_onRamp);
    }

    function getStaticConfig() external pure returns (FiveWordStaticConfig memory c) {
        c.localChainSelector = 1;
    }
}

/// @dev Pre-1.6 EVM2EVMOffRamp with its real `typeAndVersion`.
contract MockOffRampPre16Real is MockOffRampPre16 {
    constructor(uint64 chainSelector_, uint64 sourceChainSelector_, address onRamp_)
        MockOffRampPre16(chainSelector_, sourceChainSelector_, onRamp_)
    {}

    function typeAndVersion() external pure returns (string memory) {
        return "EVM2EVMOffRamp 1.5.0";
    }
}

/// @dev Answers every call (including `typeAndVersion`) with 3 junk bytes: an OffRamp of unknown shape.
contract MockOffRampGarbage {
    fallback() external {
        assembly {
            mstore(0, 0x0102030000000000000000000000000000000000000000000000000000000000)
            return(0, 3)
        }
    }
}

/// @dev Future OffRamp version whose config getter has a shape this simulator does not know.
contract MockOffRampUnknownVersion {
    function typeAndVersion() external pure returns (string memory) {
        return "OffRamp 9.0.0";
    }

    function getSourceChainConfig(uint64) external pure returns (uint256, uint256) {
        return (1, 2);
    }
}

contract CCIPLocalSimulatorForkRoutingTest is Test {
    CCIPLocalSimulatorForkHarness internal harness;

    uint64 internal constant SOURCE_SELECTOR = 16015286601757825753;
    uint64 internal constant DEST_CHAIN_SELECTOR = 3478487238524512106;

    function setUp() public {
        harness = new CCIPLocalSimulatorForkHarness();
    }

    function test_decodeReceiver_abiEncodedAddress() public {
        address a = address(0x1234567890123456789012345678901234567890);
        assertEq(harness.exposedDecodeReceiver(abi.encode(a)), a);
    }

    function test_decodeReceiver_twentyByteRaw() public {
        address a = address(0x1234567890123456789012345678901234567890);
        assertEq(harness.exposedDecodeReceiver(abi.encodePacked(a)), a);
    }

    /// @dev v1.6 lanes with an EVM source chain deliver `sender` as a 32-byte ABI word, so receivers can
    ///      `abi.decode(message.sender, (address))` and compare against `abi.encode(trustedRemote)`.
    function test_executeV1dot6_encodesSenderAsAbiWord() public {
        MockOffRampRecorder offRamp = new MockOffRampRecorder();
        address sender = address(0x1234567890123456789012345678901234567890);

        CCIPForkAdapterTypes.V1dot6EVM2AnyRampMessage memory message = CCIPForkAdapterTypes.V1dot6EVM2AnyRampMessage({
            header: CCIPForkAdapterTypes.V1dot6RampMessageHeader({
                messageId: keccak256("messageId"),
                sourceChainSelector: SOURCE_SELECTOR,
                destChainSelector: DEST_CHAIN_SELECTOR,
                sequenceNumber: 1,
                nonce: 1
            }),
            sender: sender,
            data: "",
            receiver: abi.encode(address(0xABCD)),
            extraArgs: "",
            feeToken: address(0),
            feeTokenAmount: 0,
            feeValueJuels: 0,
            tokenAmounts: new CCIPForkAdapterTypes.V1dot6EVM2AnyTokenTransfer[](0)
        });

        assertTrue(harness.exposedExecuteV1dot6(address(offRamp), message));

        bytes memory recordedSender = offRamp.recordedSender();
        assertEq(recordedSender.length, 32);
        // Receivers consume `sender` either by decoding it to an address, or by comparing the raw bytes
        // against an encoded trusted remote. Both must hold.
        assertEq(abi.decode(recordedSender, (address)), sender);
        assertEq(keccak256(recordedSender), keccak256(abi.encode(sender)));
    }

    function test_findOffRamp_returnsMatchingV16RegardlessOfRouterListOrder() public {
        address sourceOnRamp = address(0xA11CE);
        address routerAddr = address(0xBEEF);

        address good = address(new MockOffRampV16(routerAddr, SOURCE_SELECTOR, sourceOnRamp, true));
        address bad = address(new MockOffRampV16(routerAddr, SOURCE_SELECTOR, address(0xBAD), true));
        address foreign = address(new MockOffRampForeign());

        CCIPForkAdapterTypes.RouterOffRamp[] memory ramps = new CCIPForkAdapterTypes.RouterOffRamp[](3);
        ramps[0] = CCIPForkAdapterTypes.RouterOffRamp({sourceChainSelector: SOURCE_SELECTOR, offRamp: good});
        ramps[1] = CCIPForkAdapterTypes.RouterOffRamp({sourceChainSelector: SOURCE_SELECTOR, offRamp: bad});
        ramps[2] = CCIPForkAdapterTypes.RouterOffRamp({sourceChainSelector: SOURCE_SELECTOR, offRamp: foreign});

        assertEq(harness.exposedFindOffRamp(ramps, SOURCE_SELECTOR, sourceOnRamp), good);
    }

    function test_findOffRamp_returnsMatchingPreV16() public {
        address sourceOnRamp = address(0xB0B);
        address pre = address(new MockOffRampPre16(DEST_CHAIN_SELECTOR, SOURCE_SELECTOR, sourceOnRamp));

        CCIPForkAdapterTypes.RouterOffRamp[] memory ramps = new CCIPForkAdapterTypes.RouterOffRamp[](1);
        ramps[0] = CCIPForkAdapterTypes.RouterOffRamp({sourceChainSelector: SOURCE_SELECTOR, offRamp: pre});

        assertEq(harness.exposedFindOffRamp(ramps, SOURCE_SELECTOR, sourceOnRamp), pre);
    }

    function test_findOffRamp_returnsZeroWhenNoMatch() public {
        address sourceOnRamp = address(0xC0C0);
        address wrong = address(new MockOffRampV16(address(0x1), SOURCE_SELECTOR, address(0xDEAD), true));

        CCIPForkAdapterTypes.RouterOffRamp[] memory ramps = new CCIPForkAdapterTypes.RouterOffRamp[](1);
        ramps[0] = CCIPForkAdapterTypes.RouterOffRamp({sourceChainSelector: SOURCE_SELECTOR, offRamp: wrong});

        assertEq(harness.exposedFindOffRamp(ramps, SOURCE_SELECTOR, sourceOnRamp), address(0));
    }

    function test_findOffRamp_fallsBackToStaticWhenV16OnRampWrong() public {
        address sourceOnRamp = address(0xD00D);
        address wrongOnRamp = address(0xBAD1);
        address combo =
            address(new MockOffRampV16WrongThenPre16(DEST_CHAIN_SELECTOR, SOURCE_SELECTOR, sourceOnRamp, wrongOnRamp));

        CCIPForkAdapterTypes.RouterOffRamp[] memory ramps = new CCIPForkAdapterTypes.RouterOffRamp[](1);
        ramps[0] = CCIPForkAdapterTypes.RouterOffRamp({sourceChainSelector: SOURCE_SELECTOR, offRamp: combo});

        assertEq(harness.exposedFindOffRamp(ramps, SOURCE_SELECTOR, sourceOnRamp), combo);
    }

    function test_findOffRamp_ignoresDisabledV16Lane() public {
        address sourceOnRamp = address(0xE11E);
        address routerAddr = address(0xF00D);
        address disabled = address(new MockOffRampV16(routerAddr, SOURCE_SELECTOR, sourceOnRamp, false));
        address enabled = address(new MockOffRampV16(routerAddr, SOURCE_SELECTOR, sourceOnRamp, true));

        CCIPForkAdapterTypes.RouterOffRamp[] memory ramps = new CCIPForkAdapterTypes.RouterOffRamp[](2);
        ramps[0] = CCIPForkAdapterTypes.RouterOffRamp({sourceChainSelector: SOURCE_SELECTOR, offRamp: disabled});
        ramps[1] = CCIPForkAdapterTypes.RouterOffRamp({sourceChainSelector: SOURCE_SELECTOR, offRamp: enabled});

        assertEq(harness.exposedFindOffRamp(ramps, SOURCE_SELECTOR, sourceOnRamp), enabled);
    }

    function _ramps(address[] memory offRamps)
        internal
        pure
        returns (CCIPForkAdapterTypes.RouterOffRamp[] memory ramps)
    {
        ramps = new CCIPForkAdapterTypes.RouterOffRamp[](offRamps.length);
        for (uint256 i; i < offRamps.length; ++i) {
            ramps[i] = CCIPForkAdapterTypes.RouterOffRamp({sourceChainSelector: SOURCE_SELECTOR, offRamp: offRamps[i]});
        }
    }

    function _one(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    /// @dev Mixed-era migration: 1.6 and 2.0 OffRamps registered for the same source selector. Both lanes must be
    ///      resolvable, in both router orders, without the 2.0 `SourceChainConfig` payload reverting the 1.6 decode.
    function test_findOffRamp_mixedEra_resolvesBothLanesInAnyOrder() public {
        address onRampV16 = address(0x1616);
        address onRampV2 = address(0x2020);
        address v16 = address(new MockOffRampV16Real(SOURCE_SELECTOR, onRampV16));
        address v2 = address(new MockOffRampV2Real(SOURCE_SELECTOR, _one(onRampV2), true));

        address[] memory order = new address[](2);
        order[0] = v16;
        order[1] = v2;
        assertEq(harness.exposedFindOffRamp(_ramps(order), SOURCE_SELECTOR, onRampV16), v16);
        assertEq(harness.exposedFindOffRamp(_ramps(order), SOURCE_SELECTOR, onRampV2), v2);

        order[0] = v2;
        order[1] = v16;
        assertEq(harness.exposedFindOffRamp(_ramps(order), SOURCE_SELECTOR, onRampV16), v16);
        assertEq(harness.exposedFindOffRamp(_ramps(order), SOURCE_SELECTOR, onRampV2), v2);
    }

    function test_findOffRamp_v2Only_matchesAnyEntryOfOnRampsArray() public {
        address[] memory onRamps = new address[](2);
        onRamps[0] = address(0xAAAA);
        onRamps[1] = address(0xBBBB);
        address v2 = address(new MockOffRampV2Real(SOURCE_SELECTOR, onRamps, true));

        assertEq(harness.exposedFindOffRamp(_ramps(_one(v2)), SOURCE_SELECTOR, address(0xBBBB)), v2);
        assertEq(harness.exposedFindOffRamp(_ramps(_one(v2)), SOURCE_SELECTOR, address(0xCCCC)), address(0));
    }

    function test_findOffRamp_v2_ignoresDisabledLane() public {
        address onRamp = address(0x2021);
        address disabled = address(new MockOffRampV2Real(SOURCE_SELECTOR, _one(onRamp), false));

        assertEq(harness.exposedFindOffRamp(_ramps(_one(disabled)), SOURCE_SELECTOR, onRamp), address(0));
    }

    /// @dev Two real-shaped 1.6 OffRamps: the non-matching one is probed first (router list is walked newest first)
    ///      and its 5-word `getStaticConfig` must not be decoded as the 7-word pre-1.6 struct.
    function test_findOffRamp_twoV16_nonMatchingFirst_doesNotRevert() public {
        address onRamp = address(0x1617);
        address good = address(new MockOffRampV16Real(SOURCE_SELECTOR, onRamp));
        address other = address(new MockOffRampV16Real(SOURCE_SELECTOR, address(0xDEAD)));

        address[] memory order = new address[](2);
        order[0] = good;
        order[1] = other;
        assertEq(harness.exposedFindOffRamp(_ramps(order), SOURCE_SELECTOR, onRamp), good);
    }

    function test_findOffRamp_preV16WithTypeAndVersion() public {
        address onRamp = address(0x1515);
        address pre = address(new MockOffRampPre16Real(DEST_CHAIN_SELECTOR, SOURCE_SELECTOR, onRamp));
        address v2 = address(new MockOffRampV2Real(SOURCE_SELECTOR, _one(address(0x2022)), true));

        address[] memory order = new address[](2);
        order[0] = pre;
        order[1] = v2;
        assertEq(harness.exposedFindOffRamp(_ramps(order), SOURCE_SELECTOR, onRamp), pre);
    }

    /// @dev Unknown shapes (junk return data, or an unrecognised `typeAndVersion`) are skipped, never reverted on.
    function test_findOffRamp_unknownShape_isSkipped() public {
        address onRamp = address(0x2023);
        address v2 = address(new MockOffRampV2Real(SOURCE_SELECTOR, _one(onRamp), true));

        address[] memory order = new address[](3);
        order[0] = v2;
        order[1] = address(new MockOffRampGarbage());
        order[2] = address(new MockOffRampUnknownVersion());
        assertEq(harness.exposedFindOffRamp(_ramps(order), SOURCE_SELECTOR, onRamp), v2);
        assertEq(harness.exposedFindOffRamp(_ramps(order), SOURCE_SELECTOR, address(0x9999)), address(0));
    }

    function test_findOffRamp_v2WithoutTypeAndVersion_resolvedByShapeProbe() public {
        address onRamp = address(0x2024);
        address v2 = address(new MockOffRampV2NoTypeAndVersion(SOURCE_SELECTOR, onRamp));
        address v16 = address(new MockOffRampV16(address(0xBEEF), SOURCE_SELECTOR, address(0x1618), true));

        address[] memory order = new address[](2);
        order[0] = v2;
        order[1] = v16;
        assertEq(harness.exposedFindOffRamp(_ramps(order), SOURCE_SELECTOR, onRamp), v2);
        assertEq(harness.exposedFindOffRamp(_ramps(order), SOURCE_SELECTOR, address(0x1618)), v16);
        assertEq(harness.exposedFindOffRamp(_ramps(order), SOURCE_SELECTOR, address(0)), address(0));
    }

    /// @dev A 32-byte OnRamp word with high bits set is not an address: it must be skipped, not revert `abi.decode`.
    function test_findOffRamp_nonAddressOnRampWord_isSkipped() public {
        address onRamp = address(0x2025);
        bytes[] memory onRamps = new bytes[](2);
        onRamps[0] = abi.encode(type(uint256).max);
        onRamps[1] = abi.encode(onRamp);
        address v2 = address(new MockOffRampV2RawOnRamps(SOURCE_SELECTOR, onRamps));

        assertEq(harness.exposedFindOffRamp(_ramps(_one(v2)), SOURCE_SELECTOR, onRamp), v2);
        assertEq(harness.exposedFindOffRamp(_ramps(_one(v2)), SOURCE_SELECTOR, address(0x9999)), address(0));
    }
}
