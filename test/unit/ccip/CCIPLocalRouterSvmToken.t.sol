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
import {LinkToken} from "@chainlink/local/src/shared/LinkToken.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {Pool} from "@chainlink/contracts-ccip/contracts/libraries/Pool.sol";

/// @notice One token (any ERC20) sent to Solana by a contract. The test contract is the sender: it holds CCIP-BnM from
///         the simulator and approves the router. Shared by both lane versions; the subclasses only fill in what
///         differs between OnRamp 2.0 and 1.6.
abstract contract CCIPLocalRouterSvmTokenBase is Test {
    uint64 constant SOLANA = 16423721717087811551;
    uint64 constant LOCAL_EVM = 16015286601757825753;
    bytes32 constant PROGRAM = keccak256("solana-program");
    bytes32 constant TOKEN_RECEIVER = bytes32(uint256(0xbeef));
    uint256 constant FEE = 0.01 ether;
    uint256 constant AMOUNT = 5e17;

    CCIPLocalSimulator simulator;
    CCIPLocalRouter router;
    CCIPLocalSvmLane lane;
    LinkToken link;
    BurnMintERC677Helper bnm;

    function _version() internal pure virtual returns (CCIPLocalRouter.SvmLaneVersion);
    /// @dev The revert for two tokens: OnRamp 2.0 `CanOnlySendOneTokenPerMessage`, FeeQuoter 1.6
    ///      `UnsupportedNumberOfTokens(2, 1)`.
    function _twoTokensRevert() internal pure virtual returns (bytes memory);

    function setUp() public {
        simulator = new CCIPLocalSimulator();
        BurnMintERC677Helper ccipBnM;
        (,,,, link, ccipBnM,) = simulator.configuration();
        bnm = ccipBnM;
        (, IRouterClient sourceRouter,,,,,) = simulator.configuration();
        router = CCIPLocalRouter(address(sourceRouter));
        router.setFee(FEE);
        lane = new CCIPLocalSvmLane(address(router));
        router.setSvmLane(address(lane));
        router.setSvmLaneVersion(_version());
        bnm.drip(address(this)); // 1e18 CCIP-BnM
        simulator.requestLinkFromFaucet(address(this), 10 ether);
        bnm.approve(address(router), type(uint256).max);
        link.approve(address(router), type(uint256).max);
    }

    // ---------------------------------------------------------------- helpers

    function _extraArgs(bytes32 tokenReceiver) internal pure returns (bytes memory) {
        return Client._svmArgsToBytes(
            Client.SVMExtraArgsV1({
                computeUnits: 1,
                accountIsWritableBitmap: 0,
                allowOutOfOrderExecution: true,
                tokenReceiver: tokenReceiver,
                accounts: new bytes32[](0)
            })
        );
    }

    function _tokens(address token, uint256 amount) internal pure returns (Client.EVMTokenAmount[] memory tokens) {
        tokens = new Client.EVMTokenAmount[](1);
        tokens[0] = Client.EVMTokenAmount({token: token, amount: amount});
    }

    function _message(bytes memory data, bytes32 tokenReceiver, address feeToken)
        internal
        view
        returns (Client.EVM2AnyMessage memory)
    {
        return Client.EVM2AnyMessage({
            receiver: abi.encodePacked(PROGRAM),
            data: data,
            tokenAmounts: _tokens(address(bnm), AMOUNT),
            extraArgs: _extraArgs(tokenReceiver),
            feeToken: feeToken
        });
    }

    function _send(Client.EVM2AnyMessage memory message) internal returns (bytes32) {
        return router.ccipSend{value: message.feeToken == address(0) ? FEE : 0}(SOLANA, message);
    }

    /// @dev The non-indexed event fields, in order, plus the id. As a struct so the decode does not run out of stack.
    struct Sent {
        bytes32 receiver;
        bytes data;
        Client.SVMExtraArgsV1 extraArgs;
        address feeToken;
        uint256 feeAmount;
        uint256 nonce;
        address token;
        uint256 tokenAmount;
    }

    /// @dev Decodes the last `SvmMessageSent` of the router and checks its indexed fields.
    function _lastEvent() internal returns (Sent memory sent, bytes32 messageId) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = logs.length; i > 0; --i) {
            Vm.Log memory log = logs[i - 1];
            if (log.emitter == address(router) && log.topics[0] == CCIPLocalRouter.SvmMessageSent.selector) {
                assertEq(uint256(log.topics[2]), SOLANA, "destinationChainSelector");
                assertEq(address(uint160(uint256(log.topics[3]))), address(this), "sender");
                // A dynamic struct is encoded behind a 32-byte offset; the event data has none.
                sent = abi.decode(abi.encodePacked(uint256(32), log.data), (Sent));
                assertEq(sent.nonce, 1, "nonce");
                return (sent, log.topics[1]);
            }
        }
        revert("SvmMessageSent not emitted");
    }

    // ------------------------------------------------------------- happy path

    function test_token_nativeFee_balanceDownAndEveryEventField() public {
        Client.EVM2AnyMessage memory message = _message(hex"c0ffee", TOKEN_RECEIVER, address(0));
        uint256 senderBefore = bnm.balanceOf(address(this));

        vm.recordLogs();
        bytes32 returnedId = _send(message);
        (Sent memory sent, bytes32 messageId) = _lastEvent();

        assertEq(bnm.balanceOf(address(this)), senderBefore - AMOUNT, "sender balance down");
        assertEq(bnm.balanceOf(address(lane)), AMOUNT, "lane holds the token");
        assertEq(messageId, returnedId, "messageId");
        assertEq(returnedId, keccak256(abi.encode(uint256(1), address(this), SOLANA, message)), "id derivation");
        assertEq(sent.token, address(bnm), "token");
        assertEq(sent.tokenAmount, AMOUNT, "tokenAmount");
        assertEq(sent.extraArgs.tokenReceiver, TOKEN_RECEIVER, "tokenReceiver");
        assertEq(sent.receiver, PROGRAM, "receiver");
        assertEq(sent.data, hex"c0ffee", "data");
        assertEq(sent.feeToken, address(0), "feeToken");
        assertEq(sent.feeAmount, FEE, "fee");
        assertEq(address(router).balance, FEE, "native fee collected");
    }

    function test_token_expectEmit() public {
        Client.EVM2AnyMessage memory message = _message(hex"c0ffee", TOKEN_RECEIVER, address(0));
        bytes32 id = keccak256(abi.encode(uint256(1), address(this), SOLANA, message));
        Client.SVMExtraArgsV1 memory args = Client.SVMExtraArgsV1({
            computeUnits: 1,
            accountIsWritableBitmap: 0,
            allowOutOfOrderExecution: true,
            tokenReceiver: TOKEN_RECEIVER,
            accounts: new bytes32[](0)
        });

        vm.expectEmit(true, true, true, true, address(router));
        emit CCIPLocalRouter.SvmMessageSent(
            id, SOLANA, address(this), PROGRAM, hex"c0ffee", args, address(0), FEE, 1, address(bnm), AMOUNT
        );
        _send(message);
    }

    function test_token_withoutData() public {
        Client.EVM2AnyMessage memory message = _message("", TOKEN_RECEIVER, address(0));
        // Token-only transfer: no instruction to invoke, so the receiver is zero.
        message.receiver = abi.encodePacked(bytes32(0));
        message.extraArgs = Client._svmArgsToBytes(
            Client.SVMExtraArgsV1({
                computeUnits: 0,
                accountIsWritableBitmap: 0,
                allowOutOfOrderExecution: true,
                tokenReceiver: TOKEN_RECEIVER,
                accounts: new bytes32[](0)
            })
        );

        vm.recordLogs();
        _send(message);
        (Sent memory sent,) = _lastEvent();

        assertEq(sent.data.length, 0, "no data");
        assertEq(sent.token, address(bnm), "token");
        assertEq(sent.tokenAmount, AMOUNT, "tokenAmount");
        assertEq(bnm.balanceOf(address(lane)), AMOUNT, "lane holds the token");
    }

    function test_token_linkFee() public {
        Client.EVM2AnyMessage memory message = _message(hex"c0ffee", TOKEN_RECEIVER, address(link));
        uint256 bnmBefore = bnm.balanceOf(address(this));
        uint256 linkBefore = link.balanceOf(address(this));

        vm.recordLogs();
        _send(message);
        (Sent memory sent,) = _lastEvent();

        assertEq(bnm.balanceOf(address(this)), bnmBefore - AMOUNT, "token pulled");
        assertEq(link.balanceOf(address(this)), linkBefore - FEE, "LINK fee pulled");
        assertEq(link.balanceOf(address(router)), FEE, "router got LINK fee");
        assertEq(sent.feeToken, address(link), "feeToken");
        assertEq(sent.feeAmount, FEE, "fee");
        assertEq(sent.token, address(bnm), "token");
        assertEq(sent.tokenAmount, AMOUNT, "tokenAmount");
    }

    /// @dev The token may be the fee token itself; both transfers are separate.
    function test_token_sameAsFeeToken() public {
        Client.EVM2AnyMessage memory message = _message(hex"c0ffee", TOKEN_RECEIVER, address(link));
        message.tokenAmounts = _tokens(address(link), AMOUNT);
        uint256 linkBefore = link.balanceOf(address(this));

        _send(message);

        assertEq(link.balanceOf(address(this)), linkBefore - FEE - AMOUNT, "fee and token pulled");
        assertEq(link.balanceOf(address(router)), FEE, "the router keeps the fee");
        assertEq(link.balanceOf(address(lane)), AMOUNT, "the lane escrows the token");
    }

    function test_noToken_eventTokenFieldsAreZero() public {
        Client.EVM2AnyMessage memory message = _message(hex"c0ffee", TOKEN_RECEIVER, address(0));
        message.tokenAmounts = new Client.EVMTokenAmount[](0);

        vm.recordLogs();
        _send(message);
        (Sent memory sent,) = _lastEvent();

        assertEq(sent.token, address(0), "token");
        assertEq(sent.tokenAmount, 0, "tokenAmount");
    }

    // ---------------------------------------------------------------- reverts

    function test_revert_twoTokens() public {
        Client.EVM2AnyMessage memory message = _message(hex"c0ffee", TOKEN_RECEIVER, address(0));
        message.tokenAmounts = new Client.EVMTokenAmount[](2);
        message.tokenAmounts[0] = Client.EVMTokenAmount({token: address(bnm), amount: 1});
        message.tokenAmounts[1] = Client.EVMTokenAmount({token: address(link), amount: 1});
        vm.expectRevert(_twoTokensRevert());
        _send(message);
    }

    /// @dev Production rejects a zero amount in `_lockOrBurnSingleToken`, after the fee is paid.
    function test_revert_zeroAmount() public {
        Client.EVM2AnyMessage memory message = _message(hex"c0ffee", TOKEN_RECEIVER, address(0));
        message.tokenAmounts = _tokens(address(bnm), 0);
        vm.expectRevert(CCIPLocalRouter.CannotSendZeroTokens.selector);
        _send(message);
    }

    function test_order_insufficientNativeFeeBeforeZeroAmount() public {
        Client.EVM2AnyMessage memory message = _message(hex"c0ffee", TOKEN_RECEIVER, address(0));
        message.tokenAmounts = _tokens(address(bnm), 0);
        vm.expectRevert(IRouterClient.InsufficientFeeTokenAmount.selector);
        router.ccipSend{value: FEE - 1}(SOLANA, message);
    }

    function test_revert_zeroAmountWithLinkFeeUndoesTheFee() public {
        Client.EVM2AnyMessage memory message = _message(hex"c0ffee", TOKEN_RECEIVER, address(link));
        message.tokenAmounts = _tokens(address(bnm), 0);
        uint256 linkBefore = link.balanceOf(address(this));
        vm.expectRevert(CCIPLocalRouter.CannotSendZeroTokens.selector);
        _send(message);
        assertEq(link.balanceOf(address(this)), linkBefore, "revert undoes the LINK fee");
    }

    function test_revert_noAllowance() public {
        bnm.approve(address(router), AMOUNT - 1);
        Client.EVM2AnyMessage memory message = _message(hex"c0ffee", TOKEN_RECEIVER, address(0));
        vm.expectRevert();
        _send(message);
    }

    function test_revert_insufficientTokenBalance() public {
        Client.EVM2AnyMessage memory message = _message(hex"c0ffee", TOKEN_RECEIVER, address(0));
        message.tokenAmounts = _tokens(address(bnm), bnm.balanceOf(address(this)) + 1);
        vm.expectRevert();
        _send(message);
    }

    // ------------------------------------------------------ EVM destinations

    function test_evmDestination_tokenGoesToReceiverNotRouter() public {
        address receiver = address(0xBEEF); // EOA: delivered as a token-only transfer
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: "",
            tokenAmounts: _tokens(address(bnm), AMOUNT),
            extraArgs: "",
            feeToken: address(0)
        });
        uint256 senderBefore = bnm.balanceOf(address(this));

        vm.recordLogs();
        router.ccipSend{value: FEE}(LOCAL_EVM, message);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(bnm.balanceOf(address(this)), senderBefore - AMOUNT);
        assertEq(bnm.balanceOf(receiver), AMOUNT, "receiver got the token");
        assertEq(bnm.balanceOf(address(lane)), 0, "lane escrow is Solana only");
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != CCIPLocalRouter.SvmMessageSent.selector, "no Solana event");
        }
    }
}

/// @notice OnRamp 2.0 + FeeQuoter 2.0.
contract CCIPLocalRouterSvmToken20Test is CCIPLocalRouterSvmTokenBase {
    function _version() internal pure override returns (CCIPLocalRouter.SvmLaneVersion) {
        return CCIPLocalRouter.SvmLaneVersion.V2_0;
    }

    function _twoTokensRevert() internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(CCIPLocalRouter.CanOnlySendOneTokenPerMessage.selector);
    }

    /// @dev Live Ethereum Sepolia -> Solana devnet OnRamp 2.0.0 (0x8dcf17f2...) has `tokenReceiverAllowed = true`, and
    ///      `OnRamp._parseExtraArgsWithDefaults` only checks that flag, so a zero token receiver passes at send time
    ///      (it fails on Solana).
    function test_zeroTokenReceiverIsAllowed() public {
        vm.recordLogs();
        _send(_message(hex"c0ffee", bytes32(0), address(0)));
        (Sent memory sent,) = _lastEvent();

        assertEq(sent.extraArgs.tokenReceiver, bytes32(0), "tokenReceiver");
        assertEq(sent.token, address(bnm), "token");
        assertEq(sent.tokenAmount, AMOUNT, "tokenAmount");
        assertEq(bnm.balanceOf(address(lane)), AMOUNT, "custody taken");
    }

    /// @dev OnRamp.forwardFromRouter validates the receiver before `_lockOrBurnSingleToken`.
    function test_order_receiverLengthBeforeZeroAmount() public {
        Client.EVM2AnyMessage memory message = _message(hex"c0ffee", TOKEN_RECEIVER, address(0));
        message.receiver = hex"1234";
        message.tokenAmounts = _tokens(address(bnm), 0);
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.InvalidDestChainAddress.selector, hex"1234"));
        _send(message);
    }

    /// @dev Only the payload is checked locally; token overhead is a 1.6 rule here.
    function test_dataLimitIgnoresTokenOverhead() public {
        _send(_message(new bytes(30_000), TOKEN_RECEIVER, address(0)));
    }
}

/// @notice OnRamp 1.6.0 + FeeQuoter 2.0.0.
contract CCIPLocalRouterSvmToken16Test is CCIPLocalRouterSvmTokenBase {
    function _version() internal pure override returns (CCIPLocalRouter.SvmLaneVersion) {
        return CCIPLocalRouter.SvmLaneVersion.V1_6;
    }

    function _twoTokensRevert() internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(CCIPLocalRouter.UnsupportedNumberOfTokens.selector, 2, 1);
    }

    function test_revert_zeroTokenReceiver() public {
        vm.expectRevert(CCIPLocalRouter.InvalidTokenReceiver.selector);
        _send(_message(hex"c0ffee", bytes32(0), address(0)));
    }

    /// @dev FeeQuoter adds `SVM_TOKEN_TRANSFER_DATA_OVERHEAD` (300) + `CCIP_LOCK_OR_BURN_V1_RET_BYTES` (32) per token
    ///      to the payload and the two messaging accounts (2 * 32), against 1,280.
    function test_sizeLimitIncludesTokenOverhead() public {
        assertEq(Client.SVM_TOKEN_TRANSFER_DATA_OVERHEAD, 300);
        assertEq(Pool.CCIP_LOCK_OR_BURN_V1_RET_BYTES, 32);
        uint256 maxData = 1_280 - 2 * 32 - (300 + 32);

        _send(_message(new bytes(maxData), TOKEN_RECEIVER, address(0)));

        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.MessageTooLarge.selector, 1_280, 1_281));
        _send(_message(new bytes(maxData + 1), TOKEN_RECEIVER, address(0)));
    }

    /// @dev Without the token the same payload fits, so the overhead is what tips it over.
    function test_sizeLimit_sameDataFitsWithoutToken() public {
        Client.EVM2AnyMessage memory message = _message(new bytes(1_280 - 2 * 32 - 300), TOKEN_RECEIVER, address(0));
        message.tokenAmounts = new Client.EVMTokenAmount[](0);
        _send(message);
    }
}
