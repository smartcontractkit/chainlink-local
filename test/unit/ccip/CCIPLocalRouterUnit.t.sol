// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CCIPLocalSimulator, IRouterClient, BurnMintERC677Helper} from "../../../src/ccip/CCIPLocalSimulator.sol";
import {CCIPLocalRouter} from "../../../src/ccip/CCIPLocalRouter.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {CCVConfigValidation} from "@chainlink/contracts-ccip/contracts/libraries/CCVConfigValidation.sol";
import {ExtraArgsCodec} from "@chainlink/contracts-ccip/contracts/libraries/ExtraArgsCodec.sol";
import {FinalityCodec} from "@chainlink/contracts-ccip/contracts/libraries/FinalityCodec.sol";
import {MockCCIPRouter} from "@chainlink/contracts-ccip/contracts/test/mocks/MockRouter.sol";

import {BasicMessageReceiver} from "../../../src/test/ccip/BasicMessageReceiver.sol";
import {BasicMessageReceiverWithCCVs} from "../../../src/test/ccip/BasicMessageReceiverWithCCVs.sol";
import {ConfigurableCCVMessageReceiver} from "../../../src/test/ccip/ConfigurableCCVMessageReceiver.sol";

/// @dev Tiny test-only receiver that reverts if it is ever asked to process the same messageId twice. Used to prove
/// that `ccipSend` produces unique messageIds even for otherwise-identical sends (see `CCIPLocalRouterUnitTest`
/// messageId uniqueness tests below).
contract DedupingReceiver is CCIPReceiver {
    mapping(bytes32 => bool) public seen;
    uint256 public acceptedCount;

    constructor(address router) CCIPReceiver(router) {}

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        require(!seen[message.messageId], "duplicate messageId delivered");
        seen[message.messageId] = true;
        acceptedCount++;
    }
}

/// @dev Local mode must apply the CCIP 2.0 OffRamp finality rules, so a test that passes locally does not fail on a
///      fork or in production: an FTF message with data (or a non-zero gas limit) is only delivered to a receiver that
///      allows that finality via `getCCVsAndFinalityConfig`; token-only transfers skip the receiver check.
contract CCIPLocalRouterUnitTest is Test {
    CCIPLocalSimulator internal s_simulator;
    IRouterClient internal s_router;
    uint64 internal s_chainSelector;
    BurnMintERC677Helper internal s_ccipBnM;
    address internal s_alice = makeAddr("alice");

    function setUp() public {
        s_simulator = new CCIPLocalSimulator();
        (uint64 chainSelector, IRouterClient sourceRouter,,,, BurnMintERC677Helper ccipBnM,) =
            s_simulator.configuration();
        s_chainSelector = chainSelector;
        s_router = sourceRouter;
        s_ccipBnM = ccipBnM;
    }

    function _send(address receiver, bytes memory data, Client.EVMTokenAmount[] memory tokens, bytes memory extraArgs)
        internal
        returns (bytes32)
    {
        vm.startPrank(s_alice);
        bytes32 messageId = s_router.ccipSend(
            s_chainSelector,
            Client.EVM2AnyMessage({
                receiver: abi.encode(receiver),
                data: data,
                tokenAmounts: tokens,
                extraArgs: extraArgs,
                feeToken: address(0)
            })
        );
        vm.stopPrank();
        return messageId;
    }

    function _ftf(uint32 gasLimit, uint16 blockDepth) internal pure returns (bytes memory) {
        return ExtraArgsCodec._getBasicEncodedExtraArgsV3BlockDepth(gasLimit, blockDepth);
    }

    function _oneBnM(uint256 amount) internal returns (Client.EVMTokenAmount[] memory tokens) {
        s_ccipBnM.drip(s_alice);
        vm.prank(s_alice);
        s_ccipBnM.approve(address(s_router), amount);
        tokens = new Client.EVMTokenAmount[](1);
        tokens[0] = Client.EVMTokenAmount({token: address(s_ccipBnM), amount: amount});
    }

    function test_ftfMessage_toReceiverRequiringFinality_reverts() public {
        BasicMessageReceiver receiver = new BasicMessageReceiver(address(s_router));

        vm.expectRevert(
            abi.encodeWithSelector(
                FinalityCodec.InvalidRequestedFinality.selector,
                FinalityCodec._encodeBlockDepth(1),
                FinalityCodec.WAIT_FOR_FINALITY_FLAG
            )
        );
        _send(address(receiver), "hello", new Client.EVMTokenAmount[](0), _ftf(200_000, 1));
    }

    function test_ftfMessage_toOptedInReceiver_isDelivered() public {
        BasicMessageReceiverWithCCVs receiver = new BasicMessageReceiverWithCCVs(address(s_router));
        receiver.setAllowedFinalityConfig(s_chainSelector, FinalityCodec._encodeBlockDepth(1));

        bytes32 messageId = _send(address(receiver), "hello", new Client.EVMTokenAmount[](0), _ftf(200_000, 5));

        assertEq(receiver.latestMessageId(), messageId);
        assertEq(receiver.latestMessage(), "hello");
    }

    function test_ftfMessage_belowReceiverMinimumDepth_reverts() public {
        BasicMessageReceiverWithCCVs receiver = new BasicMessageReceiverWithCCVs(address(s_router));
        receiver.setAllowedFinalityConfig(s_chainSelector, FinalityCodec._encodeBlockDepth(10));

        vm.expectRevert(
            abi.encodeWithSelector(
                FinalityCodec.InvalidRequestedFinality.selector,
                FinalityCodec._encodeBlockDepth(5),
                FinalityCodec._encodeBlockDepth(10)
            )
        );
        _send(address(receiver), "hello", new Client.EVMTokenAmount[](0), _ftf(200_000, 5));
    }

    function test_ftfMessage_safeFlag_toReceiverAllowingSafe_isDelivered() public {
        BasicMessageReceiverWithCCVs receiver = new BasicMessageReceiverWithCCVs(address(s_router));
        receiver.setAllowedFinalityConfig(s_chainSelector, FinalityCodec.WAIT_FOR_SAFE_FLAG);

        bytes32 messageId = _send(
            address(receiver),
            "hello",
            new Client.EVMTokenAmount[](0),
            ExtraArgsCodec._getBasicEncodedExtraArgsV3FastConfirmationRule(200_000)
        );

        assertEq(receiver.latestMessageId(), messageId);
    }

    /// @dev Token-only transfers skip the receiver finality check (the pool enforces finality in production).
    function test_ftfTokenOnly_toEOA_isDelivered() public {
        address bob = makeAddr("bob");
        _send(bob, "", _oneBnM(1 ether), _ftf(0, 1));
        assertEq(s_ccipBnM.balanceOf(bob), 1 ether);
    }

    function test_ftfTokenOnly_toContractReceiver_withNoDataAndZeroGas_isDelivered() public {
        BasicMessageReceiver receiver = new BasicMessageReceiver(address(s_router));
        _send(address(receiver), "", _oneBnM(1 ether), _ftf(0, 1));
        assertEq(s_ccipBnM.balanceOf(address(receiver)), 1 ether);
    }

    function test_ftfProgrammableTokenTransfer_toReceiverRequiringFinality_reverts() public {
        BasicMessageReceiver receiver = new BasicMessageReceiver(address(s_router));
        Client.EVMTokenAmount[] memory tokens = _oneBnM(1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                FinalityCodec.InvalidRequestedFinality.selector,
                FinalityCodec._encodeBlockDepth(1),
                FinalityCodec.WAIT_FOR_FINALITY_FLAG
            )
        );
        _send(address(receiver), "hello", tokens, _ftf(200_000, 1));
    }

    function test_waitForFinality_toAnyReceiver_isDelivered() public {
        BasicMessageReceiver receiver = new BasicMessageReceiver(address(s_router));
        bytes32 messageId = _send(
            address(receiver),
            "hello",
            new Client.EVMTokenAmount[](0),
            ExtraArgsCodec._getBasicEncodedExtraArgsV3(200_000, FinalityCodec.WAIT_FOR_FINALITY_FLAG)
        );
        assertEq(receiver.latestMessageId(), messageId);
    }

    /// @dev The OnRamp rejects a finality config with more than one mode at send time.
    function test_invalidFinalityShape_reverts() public {
        BasicMessageReceiverWithCCVs receiver = new BasicMessageReceiverWithCCVs(address(s_router));
        bytes4 twoModes = FinalityCodec._encodeBlockDepthAndSafeFlag(5);

        vm.expectRevert(abi.encodeWithSelector(FinalityCodec.RequestedFinalityCanOnlyHaveOneMode.selector, twoModes));
        _send(
            address(receiver),
            "hello",
            new Client.EVMTokenAmount[](0),
            ExtraArgsCodec._getBasicEncodedExtraArgsV3(200_000, twoModes)
        );
    }

    /// @dev GenericExtraArgsV2 / EVMExtraArgsV1 carry no finality: behaviour is unchanged.
    function test_genericExtraArgsV2_toAnyReceiver_isDelivered() public {
        BasicMessageReceiver receiver = new BasicMessageReceiver(address(s_router));
        bytes32 messageId = _send(
            address(receiver),
            "hello",
            new Client.EVMTokenAmount[](0),
            Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 200_000, allowOutOfOrderExecution: true}))
        );
        assertEq(receiver.latestMessageId(), messageId);
    }

    /// @dev Existing tests cast the local router to the upstream mock to set fees; keep that ABI.
    function test_routerKeepsMockCCIPRouterFeeAbi() public {
        MockCCIPRouter(address(s_router)).setFee(123);
        assertEq(
            s_router.getFee(
                s_chainSelector,
                Client.EVM2AnyMessage({
                    receiver: abi.encode(s_alice),
                    data: "",
                    tokenAmounts: new Client.EVMTokenAmount[](0),
                    extraArgs: "",
                    feeToken: address(0)
                })
            ),
            123
        );
    }

    function _sendAs(
        address sender,
        uint64 destinationChainSelector,
        address receiver,
        bytes memory data,
        Client.EVMTokenAmount[] memory tokens,
        bytes memory extraArgs
    ) internal returns (bytes32) {
        vm.prank(sender);
        return s_router.ccipSend(
            destinationChainSelector,
            Client.EVM2AnyMessage({
                receiver: abi.encode(receiver),
                data: data,
                tokenAmounts: tokens,
                extraArgs: extraArgs,
                feeToken: address(0)
            })
        );
    }

    // ================================================================
    // │                 Unique messageId per send                    │
    // ================================================================

    function test_messageId_sameSenderIdenticalSends_areUnique() public {
        BasicMessageReceiver receiver = new BasicMessageReceiver(address(s_router));
        bytes32 firstId = _send(address(receiver), "hello", new Client.EVMTokenAmount[](0), "");
        bytes32 secondId = _send(address(receiver), "hello", new Client.EVMTokenAmount[](0), "");
        assertTrue(firstId != secondId);
    }

    function test_messageId_differentSenders_areUnique() public {
        BasicMessageReceiver receiver = new BasicMessageReceiver(address(s_router));
        address bob = makeAddr("bob");
        bytes32 aliceId =
            _sendAs(s_alice, s_chainSelector, address(receiver), "hello", new Client.EVMTokenAmount[](0), "");
        bytes32 bobId = _sendAs(bob, s_chainSelector, address(receiver), "hello", new Client.EVMTokenAmount[](0), "");
        assertTrue(aliceId != bobId);
    }

    function test_messageId_differentDestinationSelectors_areUnique() public {
        BasicMessageReceiver receiver = new BasicMessageReceiver(address(s_router));
        bytes32 firstId =
            _sendAs(s_alice, s_chainSelector, address(receiver), "hello", new Client.EVMTokenAmount[](0), "");
        bytes32 secondId =
            _sendAs(s_alice, s_chainSelector + 1, address(receiver), "hello", new Client.EVMTokenAmount[](0), "");
        assertTrue(firstId != secondId);
    }

    /// @dev A receiver that dedupes by messageId must accept two otherwise-identical sends: this fails on the
    ///      pre-fix `keccak256(abi.encode(message))` scheme because both sends produce the same id.
    function test_messageId_dedupingReceiver_acceptsBothSends() public {
        DedupingReceiver receiver = new DedupingReceiver(address(s_router));
        _send(address(receiver), "hello", new Client.EVMTokenAmount[](0), "");
        _send(address(receiver), "hello", new Client.EVMTokenAmount[](0), "");
        assertEq(receiver.acceptedCount(), 2);
    }

    // ================================================================
    // │            GenericExtraArgsV3.tokenReceiver rejection         │
    // ================================================================

    /// @dev Production OnRamp 2.0 rejects a non-empty `tokenReceiver` on all EVM lanes
    ///      (`OnRamp._parseExtraArgsWithDefaults`, `DestChainConfig.tokenReceiverAllowed` is always false for EVM).
    function test_tokenReceiver_nonEmpty_reverts() public {
        BasicMessageReceiver receiver = new BasicMessageReceiver(address(s_router));

        ExtraArgsCodec.GenericExtraArgsV3 memory args;
        args.gasLimit = 200_000;
        args.tokenReceiver = abi.encodePacked(makeAddr("tokenReceiver"));

        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.TokenReceiverNotAllowed.selector, s_chainSelector));
        _send(
            address(receiver), "hello", new Client.EVMTokenAmount[](0), ExtraArgsCodec._encodeGenericExtraArgsV3(args)
        );
    }

    // ================================================================
    // │       Receiver V2 hook mirrored like OffRamp._getCCVsFromReceiver     │
    // ================================================================

    function test_ccvHook_revertingGetter_finalizedMessage_reverts() public {
        ConfigurableCCVMessageReceiver receiver = new ConfigurableCCVMessageReceiver(address(s_router));
        bytes memory revertData = abi.encodeWithSignature("Boom()");
        receiver.setRevert(true, revertData);

        vm.expectRevert(revertData);
        _send(address(receiver), "hello", new Client.EVMTokenAmount[](0), "");
    }

    function test_ccvHook_revertingGetter_ftfMessage_reverts() public {
        ConfigurableCCVMessageReceiver receiver = new ConfigurableCCVMessageReceiver(address(s_router));
        bytes memory revertData = abi.encodeWithSignature("Boom()");
        receiver.setRevert(true, revertData);

        vm.expectRevert(revertData);
        _send(address(receiver), "hello", new Client.EVMTokenAmount[](0), _ftf(200_000, 1));
    }

    function test_ccvHook_duplicateRequiredCCVs_reverts() public {
        ConfigurableCCVMessageReceiver receiver = new ConfigurableCCVMessageReceiver(address(s_router));
        address ccv = makeAddr("ccv");
        address[] memory duplicateRequired = new address[](2);
        duplicateRequired[0] = ccv;
        duplicateRequired[1] = ccv;
        receiver.setCCVConfig(duplicateRequired, new address[](0), 0, FinalityCodec.WAIT_FOR_FINALITY_FLAG);

        vm.expectRevert(abi.encodeWithSelector(CCVConfigValidation.DuplicateCCVNotAllowed.selector, ccv));
        _send(address(receiver), "hello", new Client.EVMTokenAmount[](0), "");
    }

    function test_ccvHook_duplicateOptionalCCVs_reverts() public {
        ConfigurableCCVMessageReceiver receiver = new ConfigurableCCVMessageReceiver(address(s_router));
        address ccv = makeAddr("ccv");
        address[] memory duplicateOptional = new address[](2);
        duplicateOptional[0] = ccv;
        duplicateOptional[1] = ccv;
        receiver.setCCVConfig(new address[](0), duplicateOptional, 1, FinalityCodec.WAIT_FOR_FINALITY_FLAG);

        vm.expectRevert(abi.encodeWithSelector(CCVConfigValidation.DuplicateCCVNotAllowed.selector, ccv));
        _send(address(receiver), "hello", new Client.EVMTokenAmount[](0), "");
    }

    function test_ccvHook_optionalThresholdExceedsOptionalLength_reverts() public {
        ConfigurableCCVMessageReceiver receiver = new ConfigurableCCVMessageReceiver(address(s_router));
        address[] memory optionalCCVs = new address[](1);
        optionalCCVs[0] = makeAddr("ccv");
        receiver.setCCVConfig(new address[](0), optionalCCVs, 2, FinalityCodec.WAIT_FOR_FINALITY_FLAG);

        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.InvalidOptionalThreshold.selector, 2, 1));
        _send(address(receiver), "hello", new Client.EVMTokenAmount[](0), "");
    }

    /// @dev Finalized messages must still invoke the V2 hook (not only FTF messages): a reverting hook must make a
    ///      finalized send revert too.
    function test_ccvHook_finalizedMessage_stillCallsHook() public {
        ConfigurableCCVMessageReceiver receiver = new ConfigurableCCVMessageReceiver(address(s_router));
        receiver.setCCVConfig(new address[](0), new address[](0), 0, FinalityCodec.WAIT_FOR_FINALITY_FLAG);

        // Valid config: the finalized send must succeed and reach the receiver.
        bytes32 messageId = _send(address(receiver), "hello", new Client.EVMTokenAmount[](0), "");
        assertEq(receiver.latestMessageId(), messageId);

        // Now make the hook revert: the same finalized send must revert too, proving the hook is actually invoked
        // for finalized messages and not skipped as it was before the fix.
        bytes memory revertData = abi.encodeWithSignature("Boom()");
        receiver.setRevert(true, revertData);
        vm.expectRevert(revertData);
        _send(address(receiver), "hello", new Client.EVMTokenAmount[](0), "");
    }

    // ================================================================
    // │              Sends the 2.0 OnRamp rejects                    │
    // ================================================================

    function test_moreThanOneToken_reverts() public {
        BasicMessageReceiver receiver = new BasicMessageReceiver(address(s_router));
        Client.EVMTokenAmount[] memory tokens = _oneBnM(1 ether);
        Client.EVMTokenAmount[] memory twoTokens = new Client.EVMTokenAmount[](2);
        twoTokens[0] = tokens[0];
        twoTokens[1] = tokens[0];

        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.CanOnlySendOneTokenPerMessage.selector));
        _send(address(receiver), "hello", twoTokens, "");
    }

    function test_zeroAmountToken_reverts() public {
        BasicMessageReceiver receiver = new BasicMessageReceiver(address(s_router));
        Client.EVMTokenAmount[] memory tokens = _oneBnM(0);

        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.CannotSendZeroTokens.selector));
        _send(address(receiver), "hello", tokens, "");
    }

    /// @dev Production treats extraArgs shorter than 4 bytes as empty (default gas limit and finality), it does not
    ///      revert `InvalidExtraArgsTag` (see `FeeQuoter._parseUnvalidatedEVMExtraArgsFromBytes`).
    function test_shortExtraArgs_treatedAsEmpty() public {
        BasicMessageReceiver receiver = new BasicMessageReceiver(address(s_router));
        bytes32 messageId = _send(address(receiver), "hello", new Client.EVMTokenAmount[](0), hex"010203");
        assertEq(receiver.latestMessageId(), messageId);
    }

    /// @dev Production (FeeQuoter) compares the full uint256 V1/V2 gas limit against the lane's `maxPerMsgGasLimit`
    ///      (a uint32) and reverts `MessageGasLimitTooHigh`; it never truncates. Above uint32 every lane cap is exceeded.
    function test_legacyGasLimitAboveUint32_reverts() public {
        BasicMessageReceiver receiver = new BasicMessageReceiver(address(s_router));
        bytes memory extraArgs = Client._argsToBytes(
            Client.GenericExtraArgsV2({gasLimit: uint256(type(uint32).max) + 300_000, allowOutOfOrderExecution: true})
        );

        vm.expectRevert(bytes4(keccak256("MessageGasLimitTooHigh()")));
        _send(address(receiver), "hello", new Client.EVMTokenAmount[](0), extraArgs);
    }

    function test_legacyEvmExtraArgsV1GasLimitAboveUint32_reverts() public {
        BasicMessageReceiver receiver = new BasicMessageReceiver(address(s_router));
        bytes memory extraArgs = Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: uint256(type(uint32).max) + 1}));

        vm.expectRevert(bytes4(keccak256("MessageGasLimitTooHigh()")));
        _send(address(receiver), "hello", new Client.EVMTokenAmount[](0), extraArgs);
    }
}
