// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {
    CCIPLocalSimulatorFork,
    IRouterFork,
    IOffRampSourceConfigFork,
    IEVM2EVMOffRampStaticConfigFork
} from "../../../src/ccip/CCIPLocalSimulatorFork.sol";
import {CCIPForkAdapterTypes} from "../../../src/ccip/adapters/CCIPForkAdapterTypes.sol";
import {CCIPForkAdapterV1dot6} from "../../../src/ccip/adapters/CCIPForkAdapterV1dot6.sol";

/// @dev Exposes internal OffRamp resolution for unit testing.
contract CCIPLocalSimulatorForkHarness is CCIPLocalSimulatorFork {
    function exposedDecodeReceiver(bytes memory encoded) external pure returns (address) {
        return _decodeEVMAddress(encoded);
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
        IRouterFork.OffRamp[] calldata offRamps,
        uint64 sourceChainSelector,
        address sourceOnRamp
    ) external view returns (address) {
        IRouterFork.OffRamp[] memory ramps = new IRouterFork.OffRamp[](offRamps.length);
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

    constructor(
        uint64 chainSelector_,
        uint64 sourceChainSelector_,
        address correctOnRamp_,
        address wrongOnRamp_
    ) MockOffRampPre16(chainSelector_, sourceChainSelector_, correctOnRamp_) {
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

        IRouterFork.OffRamp[] memory ramps = new IRouterFork.OffRamp[](3);
        ramps[0] = IRouterFork.OffRamp({sourceChainSelector: SOURCE_SELECTOR, offRamp: good});
        ramps[1] = IRouterFork.OffRamp({sourceChainSelector: SOURCE_SELECTOR, offRamp: bad});
        ramps[2] = IRouterFork.OffRamp({sourceChainSelector: SOURCE_SELECTOR, offRamp: foreign});

        assertEq(harness.exposedFindOffRamp(ramps, SOURCE_SELECTOR, sourceOnRamp), good);
    }

    function test_findOffRamp_returnsMatchingPreV16() public {
        address sourceOnRamp = address(0xB0B);
        address pre = address(new MockOffRampPre16(DEST_CHAIN_SELECTOR, SOURCE_SELECTOR, sourceOnRamp));

        IRouterFork.OffRamp[] memory ramps = new IRouterFork.OffRamp[](1);
        ramps[0] = IRouterFork.OffRamp({sourceChainSelector: SOURCE_SELECTOR, offRamp: pre});

        assertEq(harness.exposedFindOffRamp(ramps, SOURCE_SELECTOR, sourceOnRamp), pre);
    }

    function test_findOffRamp_returnsZeroWhenNoMatch() public {
        address sourceOnRamp = address(0xC0C0);
        address wrong = address(new MockOffRampV16(address(0x1), SOURCE_SELECTOR, address(0xDEAD), true));

        IRouterFork.OffRamp[] memory ramps = new IRouterFork.OffRamp[](1);
        ramps[0] = IRouterFork.OffRamp({sourceChainSelector: SOURCE_SELECTOR, offRamp: wrong});

        assertEq(harness.exposedFindOffRamp(ramps, SOURCE_SELECTOR, sourceOnRamp), address(0));
    }

    function test_findOffRamp_fallsBackToStaticWhenV16OnRampWrong() public {
        address sourceOnRamp = address(0xD00D);
        address wrongOnRamp = address(0xBAD1);
        address combo = address(new MockOffRampV16WrongThenPre16(DEST_CHAIN_SELECTOR, SOURCE_SELECTOR, sourceOnRamp, wrongOnRamp));

        IRouterFork.OffRamp[] memory ramps = new IRouterFork.OffRamp[](1);
        ramps[0] = IRouterFork.OffRamp({sourceChainSelector: SOURCE_SELECTOR, offRamp: combo});

        assertEq(harness.exposedFindOffRamp(ramps, SOURCE_SELECTOR, sourceOnRamp), combo);
    }

    function test_findOffRamp_ignoresDisabledV16Lane() public {
        address sourceOnRamp = address(0xE11E);
        address routerAddr = address(0xF00D);
        address disabled = address(new MockOffRampV16(routerAddr, SOURCE_SELECTOR, sourceOnRamp, false));
        address enabled = address(new MockOffRampV16(routerAddr, SOURCE_SELECTOR, sourceOnRamp, true));

        IRouterFork.OffRamp[] memory ramps = new IRouterFork.OffRamp[](2);
        ramps[0] = IRouterFork.OffRamp({sourceChainSelector: SOURCE_SELECTOR, offRamp: disabled});
        ramps[1] = IRouterFork.OffRamp({sourceChainSelector: SOURCE_SELECTOR, offRamp: enabled});

        assertEq(harness.exposedFindOffRamp(ramps, SOURCE_SELECTOR, sourceOnRamp), enabled);
    }
}
