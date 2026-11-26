// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, Vm} from "forge-std/Test.sol";
import {
    CCIPLocalSimulator,
    IRouterClient,
    BurnMintERC677Helper
} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {CCIPLocalRouter} from "@chainlink/local/src/ccip/CCIPLocalRouter.sol";
import {CCIPLocalSvmLane} from "@chainlink/local/src/ccip/CCIPLocalSvmLane.sol";
import {ICCIPLocalSvmLane} from "@chainlink/local/src/ccip/interfaces/ICCIPLocalSvmLane.sol";
import {ConfigurableCCVMessageReceiver} from "@chainlink/local/src/test/ccip/ConfigurableCCVMessageReceiver.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {FinalityCodec} from "@chainlink/contracts-ccip/contracts/libraries/FinalityCodec.sol";
import {Internal} from "@chainlink/contracts-ccip/contracts/libraries/Internal.sol";
import {ERC20} from "@openzeppelin/contracts@5.3.0/token/ERC20/ERC20.sol";

/// @dev ERC20 with chosen decimals, to test the Solana (9) -> EVM (18) conversion.
contract DecimalsToken is ERC20 {
    uint8 private immutable i_decimals;

    constructor(uint8 tokenDecimals) ERC20("Decimals", "DEC") {
        i_decimals = tokenDecimals;
    }

    function decimals() public view override returns (uint8) {
        return i_decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Records what `ccipReceive` sees, including the token balance it already holds, and can be made to revert.
contract RecordingReceiver is CCIPReceiver {
    bytes32 public messageId;
    uint64 public sourceChainSelector;
    bytes public sender;
    bytes public data;
    uint256 public tokenAmounts;
    address public token;
    uint256 public tokenAmount;
    uint256 public tokenBalanceSeen;
    uint256 public calls;
    bool public shouldRevert;

    constructor(address router) CCIPReceiver(router) {}

    function setRevert(bool value) external {
        shouldRevert = value;
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        if (shouldRevert) revert("boom");
        ++calls;
        messageId = message.messageId;
        sourceChainSelector = message.sourceChainSelector;
        sender = message.sender;
        data = message.data;
        tokenAmounts = message.destTokenAmounts.length;
        if (tokenAmounts == 1) {
            token = message.destTokenAmounts[0].token;
            tokenAmount = message.destTokenAmounts[0].amount;
            tokenBalanceSeen = ERC20(token).balanceOf(address(this));
        }
    }
}

/// @notice `CCIPLocalSvmLane.execute`: Solana -> EVM delivery on both lane versions. The subclasses fix the version.
abstract contract CCIPLocalSvmLaneExecuteBase is Test {
    uint64 constant SOLANA = 16423721717087811551;
    uint64 constant LOCAL_EVM = 16015286601757825753;
    bytes32 constant SOLANA_SENDER = keccak256("solana-sender");
    bytes32 constant PROGRAM = keccak256("solana-program");
    uint256 constant AMOUNT = 5e17;

    CCIPLocalSimulator simulator;
    CCIPLocalRouter router;
    CCIPLocalSvmLane lane;
    BurnMintERC677Helper bnm;
    RecordingReceiver receiver;
    DecimalsToken sol9; // a 9-decimal token, as a Solana mint usually is

    event SvmMessageExecuted(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address indexed receiver,
        bool success,
        bytes retData
    );

    function _version() internal pure virtual returns (CCIPLocalRouter.SvmLaneVersion);

    function setUp() public {
        simulator = new CCIPLocalSimulator();
        IRouterClient sourceRouter;
        BurnMintERC677Helper ccipBnM;
        (, sourceRouter,,,, ccipBnM,) = simulator.configuration();
        bnm = ccipBnM;
        router = CCIPLocalRouter(address(sourceRouter));
        lane = new CCIPLocalSvmLane(address(router));
        router.setSvmLane(address(lane));
        router.setSvmLaneVersion(_version());
        receiver = new RecordingReceiver(address(router));
        sol9 = new DecimalsToken(9);
    }

    // ---------------------------------------------------------------- helpers

    function _message(bytes32 id) internal view returns (ICCIPLocalSvmLane.SvmToEvmMessage memory message) {
        message.messageId = id;
        message.sourceChainSelector = SOLANA;
        message.sequenceNumber = 1;
        message.sender = abi.encodePacked(SOLANA_SENDER);
        message.receiver = address(receiver);
        message.data = hex"c0ffee";
        message.gasLimit = 1_000_000; // the recording receiver writes ~9 cold slots
        message.finality = FinalityCodec.WAIT_FOR_FINALITY_FLAG;
    }

    function _withToken(
        ICCIPLocalSvmLane.SvmToEvmMessage memory message,
        address token,
        uint256 amount,
        uint8 sourceDecimals
    ) internal pure returns (ICCIPLocalSvmLane.SvmToEvmMessage memory) {
        message.destToken = token;
        message.amount = amount;
        message.extraData = abi.encode(sourceDecimals);
        return message;
    }

    function _escrow(uint256 amount) internal {
        bnm.drip(address(this));
        bnm.transfer(address(lane), amount);
    }

    function _state(bytes32 id) internal view returns (Internal.MessageExecutionState) {
        return lane.getExecutionState(id);
    }

    // ------------------------------------------------------------------- data

    function test_dataToReceiver() public {
        ICCIPLocalSvmLane.SvmToEvmMessage memory message = _message("id-data");

        vm.expectEmit(true, true, true, true, address(lane));
        emit SvmMessageExecuted("id-data", SOLANA, address(receiver), true, "");
        (bool success, bytes memory retData) = lane.execute(message);

        assertTrue(success);
        assertEq(retData.length, 0);
        assertEq(receiver.calls(), 1);
        assertEq(receiver.messageId(), "id-data");
        assertEq(receiver.sourceChainSelector(), SOLANA, "source is Solana");
        assertEq(receiver.sender(), abi.encodePacked(SOLANA_SENDER), "sender is the 32 raw Solana bytes");
        assertEq(receiver.sender().length, 32);
        assertEq(receiver.data(), hex"c0ffee");
        assertEq(receiver.tokenAmounts(), 0);
        assertEq(uint8(_state("id-data")), uint8(Internal.MessageExecutionState.SUCCESS));
    }

    function test_routerEmitsMessageExecutedForTheLane() public {
        vm.expectEmit(false, false, false, false, address(router));
        emit CCIPLocalRouter.MessageExecuted("", SOLANA, address(lane), "");
        lane.execute(_message("id-router"));
    }

    // ------------------------------------------------------------------ token

    function test_tokenOnlyToEoa() public {
        _escrow(AMOUNT);
        address eoa = makeAddr("eoa");
        ICCIPLocalSvmLane.SvmToEvmMessage memory message = _withToken(_message("id-eoa"), address(bnm), AMOUNT, 18);
        message.receiver = eoa;
        message.data = "";
        message.gasLimit = 0;

        (bool success,) = lane.execute(message);

        assertTrue(success);
        assertEq(bnm.balanceOf(eoa), AMOUNT, "eoa got the token");
        assertEq(bnm.balanceOf(address(lane)), 0, "escrow released");
    }

    function test_tokenOnlyToContract() public {
        _escrow(AMOUNT);
        ICCIPLocalSvmLane.SvmToEvmMessage memory message = _withToken(_message("id-contract"), address(bnm), AMOUNT, 18);
        message.data = "";
        message.gasLimit = 0;

        (bool success,) = lane.execute(message);

        assertTrue(success);
        assertEq(bnm.balanceOf(address(receiver)), AMOUNT);
        assertEq(receiver.calls(), 0, "token-only does not call the receiver");
    }

    function test_tokenAndData() public {
        _escrow(AMOUNT);

        (bool success,) = lane.execute(_withToken(_message("id-both"), address(bnm), AMOUNT, 18));

        assertTrue(success);
        assertEq(receiver.calls(), 1);
        assertEq(receiver.data(), hex"c0ffee");
        assertEq(receiver.tokenAmounts(), 1);
        assertEq(receiver.token(), address(bnm));
        assertEq(receiver.tokenAmount(), AMOUNT);
        assertEq(receiver.tokenBalanceSeen(), AMOUNT, "token is delivered before the receiver runs");
        assertEq(bnm.balanceOf(address(lane)), 0);
    }

    function test_decimalsScaling_9To18() public {
        DecimalsToken evm18 = new DecimalsToken(18);
        evm18.mint(address(lane), 10e18);

        // 1.5 tokens in Solana's 9 decimals.
        (bool success,) = lane.execute(_withToken(_message("id-9-18"), address(evm18), 1_500_000_000, 9));

        assertTrue(success);
        assertEq(evm18.balanceOf(address(receiver)), 1.5e18, "scaled up to 18 decimals");
        assertEq(receiver.tokenAmount(), 1.5e18, "the receiver sees the local amount");
    }

    function test_decimalsScaling_18To18() public {
        _escrow(AMOUNT);
        (bool success,) = lane.execute(_withToken(_message("id-18-18"), address(bnm), AMOUNT, 18));
        assertTrue(success);
        assertEq(bnm.balanceOf(address(receiver)), AMOUNT);
    }

    function test_decimalsScaling_18To9RoundsDown() public {
        sol9.mint(address(lane), 10e9);
        // 1.999999999999999999 tokens in 18 decimals is 1.999999999 in 9.
        (bool success,) = lane.execute(_withToken(_message("id-18-9"), address(sol9), 1_999_999_999_999_999_999, 18));
        assertTrue(success);
        assertEq(sol9.balanceOf(address(receiver)), 1_999_999_999);
    }

    function test_emptyExtraDataMeansLocalDecimals() public {
        _escrow(AMOUNT);
        ICCIPLocalSvmLane.SvmToEvmMessage memory message = _withToken(_message("id-empty"), address(bnm), AMOUNT, 0);
        message.extraData = "";
        (bool success,) = lane.execute(message);
        assertTrue(success);
        assertEq(bnm.balanceOf(address(receiver)), AMOUNT);
    }

    function test_decimalsOverflowFailsTheMessage() public {
        _escrow(AMOUNT);
        // 18 -> from 0 decimals: amount * 10^18 overflows uint256.
        (bool success, bytes memory retData) =
            lane.execute(_withToken(_message("id-overflow"), address(bnm), type(uint256).max, 0));
        assertFalse(success);
        assertEq(bytes4(retData), ICCIPLocalSvmLane.OverflowDetected.selector);
    }

    function test_malformedExtraDataFailsTheMessage() public {
        _escrow(AMOUNT);
        ICCIPLocalSvmLane.SvmToEvmMessage memory message = _withToken(_message("id-bad"), address(bnm), AMOUNT, 18);
        message.extraData = hex"1234";
        (bool success, bytes memory retData) = lane.execute(message);
        assertFalse(success);
        assertEq(bytes4(retData), ICCIPLocalSvmLane.InvalidRemoteChainDecimals.selector);
    }

    function test_escrowTooSmall() public {
        _escrow(AMOUNT - 1);
        ICCIPLocalSvmLane.SvmToEvmMessage memory message = _withToken(_message("id-small"), address(bnm), AMOUNT, 18);

        (bool success, bytes memory retData) = lane.execute(message);

        assertFalse(success);
        assertEq(
            retData,
            abi.encodeWithSelector(ICCIPLocalSvmLane.InsufficientEscrow.selector, address(bnm), AMOUNT - 1, AMOUNT)
        );
        assertEq(uint8(_state("id-small")), uint8(Internal.MessageExecutionState.FAILURE));
        assertEq(bnm.balanceOf(address(lane)), AMOUNT - 1, "nothing moved");

        // Fund the lane and retry.
        bnm.transfer(address(lane), 1);
        (success,) = lane.execute(message);
        assertTrue(success);
        assertEq(bnm.balanceOf(address(receiver)), AMOUNT);
    }

    // ------------------------------------------------------- failure and retry

    function test_receiverRevertRecordsFailureRollsBackTokenAndRetrySucceeds() public {
        _escrow(AMOUNT);
        receiver.setRevert(true);
        ICCIPLocalSvmLane.SvmToEvmMessage memory message = _withToken(_message("id-retry"), address(bnm), AMOUNT, 18);

        (bool success, bytes memory retData) = lane.execute(message);

        assertFalse(success, "a receiver failure does not revert execute");
        assertEq(bytes4(retData), ICCIPLocalSvmLane.ReceiverError.selector);
        assertLe(retData.length, Internal.MAX_RET_BYTES);
        assertEq(uint8(_state("id-retry")), uint8(Internal.MessageExecutionState.FAILURE));
        assertEq(bnm.balanceOf(address(receiver)), 0, "token release rolled back with the failed call");
        assertEq(bnm.balanceOf(address(lane)), AMOUNT);

        receiver.setRevert(false);
        vm.expectEmit(true, true, true, true, address(lane));
        emit SvmMessageExecuted("id-retry", SOLANA, address(receiver), true, "");
        (success,) = lane.execute(message);

        assertTrue(success);
        assertEq(uint8(_state("id-retry")), uint8(Internal.MessageExecutionState.SUCCESS));
        assertEq(bnm.balanceOf(address(receiver)), AMOUNT);
        assertEq(receiver.calls(), 1);
    }

    function test_failureEmitsEventWithRevertData() public {
        receiver.setRevert(true);
        vm.recordLogs();
        (, bytes memory retData) = lane.execute(_message("id-event"));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(lane) && logs[i].topics[0] == SvmMessageExecuted.selector) {
                (bool success, bytes memory emitted) = abi.decode(logs[i].data, (bool, bytes));
                assertFalse(success);
                assertEq(emitted, retData);
                found = true;
            }
        }
        assertTrue(found);
    }

    /// @dev A retry that fails again makes no progress, so it reverts like the real OffRamp of each version.
    function test_failedAgainReverts() public {
        receiver.setRevert(true);
        ICCIPLocalSvmLane.SvmToEvmMessage memory message = _message("id-twice");
        (bool success,) = lane.execute(message);
        assertFalse(success);
        vm.expectPartialRevert(
            _version() == CCIPLocalRouter.SvmLaneVersion.V1_6
                ? ICCIPLocalSvmLane.ExecutionError.selector
                : ICCIPLocalSvmLane.NoStateProgressMade.selector
        );
        lane.execute(message);
        assertEq(uint8(_state("id-twice")), uint8(Internal.MessageExecutionState.FAILURE));
    }

    function test_reExecutingASuccessReverts() public {
        ICCIPLocalSvmLane.SvmToEvmMessage memory message = _message("id-once");
        lane.execute(message);
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPLocalSvmLane.SkippedAlreadyExecutedMessage.selector, bytes32("id-once"))
        );
        lane.execute(message);
        assertEq(receiver.calls(), 1);
    }

    function test_untouchedByDefault() public view {
        assertEq(uint8(_state("never")), uint8(Internal.MessageExecutionState.UNTOUCHED));
    }

    function test_revert_wrongSourceChainSelector() public {
        ICCIPLocalSvmLane.SvmToEvmMessage memory message = _message("id-wrong");
        message.sourceChainSelector = LOCAL_EVM;
        vm.expectRevert(abi.encodeWithSelector(ICCIPLocalSvmLane.InvalidSourceChainSelector.selector, LOCAL_EVM));
        lane.execute(message);
    }

    function test_executeSingleMessageIsSelfCallOnly() public {
        vm.expectRevert(ICCIPLocalSvmLane.CanOnlySelfCall.selector);
        lane.executeSingleMessage(_message("id-self"));
    }

    // -------------------------------------------------------------- round trip

    /// @dev An EVM -> Solana send escrows the token in the lane; a Solana -> EVM execute of the same token releases it.
    function test_roundTrip_sendEscrowsAndExecuteReleases() public {
        bnm.drip(address(this));
        bnm.approve(address(router), AMOUNT);
        Client.EVMTokenAmount[] memory tokens = new Client.EVMTokenAmount[](1);
        tokens[0] = Client.EVMTokenAmount({token: address(bnm), amount: AMOUNT});
        router.ccipSend(
            SOLANA,
            Client.EVM2AnyMessage({
                receiver: abi.encodePacked(PROGRAM),
                data: "",
                tokenAmounts: tokens,
                extraArgs: Client._svmArgsToBytes(
                    Client.SVMExtraArgsV1({
                        computeUnits: 1,
                        accountIsWritableBitmap: 0,
                        allowOutOfOrderExecution: true,
                        tokenReceiver: SOLANA_SENDER,
                        accounts: new bytes32[](0)
                    })
                ),
                feeToken: address(0)
            })
        );
        assertEq(bnm.balanceOf(address(lane)), AMOUNT, "the send escrowed the token in the lane");
        assertEq(bnm.balanceOf(address(router)), 0);

        address back = makeAddr("back");
        ICCIPLocalSvmLane.SvmToEvmMessage memory message = _withToken(_message("id-round"), address(bnm), AMOUNT, 18);
        message.receiver = back;
        message.data = "";
        message.gasLimit = 0;
        (bool success,) = lane.execute(message);

        assertTrue(success);
        assertEq(bnm.balanceOf(back), AMOUNT, "the execute released it");
        assertEq(bnm.balanceOf(address(lane)), 0);
    }
}

/// @notice CCIP 2.0 lane: the receiver finality rule applies.
contract CCIPLocalSvmLaneExecute20Test is CCIPLocalSvmLaneExecuteBase {
    function _version() internal pure override returns (CCIPLocalRouter.SvmLaneVersion) {
        return CCIPLocalRouter.SvmLaneVersion.V2_0;
    }

    function test_finalityNotAllowedByReceiverFailsThenRetrySucceeds() public {
        ConfigurableCCVMessageReceiver ccvReceiver = new ConfigurableCCVMessageReceiver(address(router));
        ccvReceiver.setCCVConfig(new address[](0), new address[](0), 0, FinalityCodec.WAIT_FOR_FINALITY_FLAG);
        ICCIPLocalSvmLane.SvmToEvmMessage memory message = _message("id-ftf");
        message.receiver = address(ccvReceiver);
        message.finality = FinalityCodec.WAIT_FOR_SAFE_FLAG;

        (bool success, bytes memory retData) = lane.execute(message);

        assertFalse(success);
        assertEq(
            retData,
            abi.encodeWithSelector(
                FinalityCodec.InvalidRequestedFinality.selector,
                FinalityCodec.WAIT_FOR_SAFE_FLAG,
                FinalityCodec.WAIT_FOR_FINALITY_FLAG
            )
        );
        assertEq(ccvReceiver.latestMessageId(), bytes32(0), "receiver not called");

        ccvReceiver.setCCVConfig(new address[](0), new address[](0), 0, FinalityCodec.WAIT_FOR_SAFE_FLAG);
        (success,) = lane.execute(message);
        assertTrue(success);
        assertEq(ccvReceiver.latestMessageId(), "id-ftf");
    }

    function test_finalizedMessageIsAlwaysAllowed() public {
        (bool success,) = lane.execute(_message("id-final"));
        assertTrue(success);
    }

    function test_tokenOnlySkipsTheFinalityRule() public {
        _escrow(AMOUNT);
        ICCIPLocalSvmLane.SvmToEvmMessage memory message =
            _withToken(_message("id-ftf-token"), address(bnm), AMOUNT, 18);
        message.data = "";
        message.gasLimit = 0;
        message.finality = FinalityCodec.WAIT_FOR_SAFE_FLAG;
        (bool success,) = lane.execute(message);
        assertTrue(success);
    }

    function test_invalidOptionalThresholdFailsTheMessage() public {
        ConfigurableCCVMessageReceiver ccvReceiver = new ConfigurableCCVMessageReceiver(address(router));
        ccvReceiver.setCCVConfig(new address[](0), new address[](0), 1, FinalityCodec.WAIT_FOR_FINALITY_FLAG);
        ICCIPLocalSvmLane.SvmToEvmMessage memory message = _message("id-threshold");
        message.receiver = address(ccvReceiver);

        (bool success, bytes memory retData) = lane.execute(message);

        assertFalse(success);
        assertEq(retData, abi.encodeWithSelector(ICCIPLocalSvmLane.InvalidOptionalThreshold.selector, 1, 0));
    }
}

/// @notice CCIP 1.6 lane: there is no finality, so the requested finality is ignored.
contract CCIPLocalSvmLaneExecute16Test is CCIPLocalSvmLaneExecuteBase {
    function _version() internal pure override returns (CCIPLocalRouter.SvmLaneVersion) {
        return CCIPLocalRouter.SvmLaneVersion.V1_6;
    }

    function test_finalityIsIgnored() public {
        ConfigurableCCVMessageReceiver ccvReceiver = new ConfigurableCCVMessageReceiver(address(router));
        ccvReceiver.setCCVConfig(new address[](0), new address[](0), 0, FinalityCodec.WAIT_FOR_FINALITY_FLAG);
        ICCIPLocalSvmLane.SvmToEvmMessage memory message = _message("id-ftf16");
        message.receiver = address(ccvReceiver);
        message.finality = FinalityCodec.WAIT_FOR_SAFE_FLAG;

        (bool success,) = lane.execute(message);

        assertTrue(success, "the same message that fails on 2.0 is delivered");
        assertEq(ccvReceiver.latestMessageId(), "id-ftf16");
    }
}
