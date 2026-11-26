// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, Vm} from "forge-std/Test.sol";
import {CCIPLocalSimulator, IRouterClient} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {CCIPLocalRouter} from "@chainlink/local/src/ccip/CCIPLocalRouter.sol";
import {CCIPLocalSvmLane} from "@chainlink/local/src/ccip/CCIPLocalSvmLane.sol";
import {SvmMessageSender} from "@chainlink/local/src/test/ccip/SvmMessageSender.sol";
import {LinkToken} from "@chainlink/local/src/shared/LinkToken.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {ExtraArgsCodec} from "@chainlink/contracts-ccip/contracts/libraries/ExtraArgsCodec.sol";

/// @notice Solana sends through `CCIPLocalRouter` must behave like a send on a CCIP 2.0 lane (Router 1.2 + OnRamp 2.0 +
///         FeeQuoter 2.0): same checks, same errors, same order.
contract CCIPLocalRouterSvmTest is Test {
    uint64 constant SOLANA = 16423721717087811551;
    uint64 constant LOCAL_EVM = 16015286601757825753;
    bytes32 constant PROGRAM = keccak256("solana-program");
    uint256 constant FEE = 0.01 ether;

    CCIPLocalSimulator simulator;
    CCIPLocalRouter router;
    LinkToken link;
    SvmMessageSender sender;

    function setUp() public {
        simulator = new CCIPLocalSimulator();
        (, IRouterClient sourceRouter,,, LinkToken linkToken,,) = simulator.configuration();
        router = CCIPLocalRouter(address(sourceRouter));
        link = linkToken;
        sender = new SvmMessageSender(address(router), address(link));
        router.setFee(FEE);
        router.setSvmLane(address(new CCIPLocalSvmLane(address(router))));
        vm.deal(address(sender), 10 ether);
        simulator.requestLinkFromFaucet(address(sender), 10 ether);
        simulator.requestLinkFromFaucet(address(this), 10 ether);
        link.approve(address(router), type(uint256).max);
    }

    // ---------------------------------------------------------------- helpers

    function _args(uint32 computeUnits, uint64 bitmap, bytes32[] memory accounts)
        internal
        pure
        returns (Client.SVMExtraArgsV1 memory)
    {
        return Client.SVMExtraArgsV1({
            computeUnits: computeUnits,
            accountIsWritableBitmap: bitmap,
            allowOutOfOrderExecution: true,
            tokenReceiver: bytes32(0),
            accounts: accounts
        });
    }

    function _validArgs() internal pure returns (bytes memory) {
        return Client._svmArgsToBytes(_args(1, 0, new bytes32[](0)));
    }

    function _wrongTagArgs() internal pure returns (bytes memory) {
        return Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 1, allowOutOfOrderExecution: true}));
    }

    function _accounts(uint256 n) internal pure returns (bytes32[] memory accounts) {
        accounts = new bytes32[](n);
        for (uint256 i; i < n; ++i) {
            accounts[i] = bytes32(i + 1);
        }
    }

    function _tokens(uint256 n) internal view returns (Client.EVMTokenAmount[] memory tokens) {
        tokens = new Client.EVMTokenAmount[](n);
        for (uint256 i; i < n; ++i) {
            tokens[i] = Client.EVMTokenAmount({token: address(link), amount: 1});
        }
    }

    function _message(
        bytes memory receiver,
        Client.EVMTokenAmount[] memory tokens,
        bytes memory extraArgs,
        address feeToken
    ) internal pure returns (Client.EVM2AnyMessage memory) {
        return Client.EVM2AnyMessage({
            receiver: receiver, data: hex"c0ffee", tokenAmounts: tokens, extraArgs: extraArgs, feeToken: feeToken
        });
    }

    function _send(bytes32 receiver, bytes memory extraArgs) internal returns (bytes32) {
        return sender.send(SOLANA, receiver, hex"c0ffee", extraArgs, address(0));
    }

    function _send(bytes32 receiver, Client.SVMExtraArgsV1 memory args) internal returns (bytes32) {
        return _send(receiver, Client._svmArgsToBytes(args));
    }

    // ------------------------------------------------------------- happy path

    function test_happyPath_nativeFee_emitsEveryField() public {
        Client.SVMExtraArgsV1 memory args = _args(200_000, 3, _accounts(2));
        args.tokenReceiver = bytes32(uint256(0xbeef));
        bytes memory extraArgs = Client._svmArgsToBytes(args);
        uint256 routerBalanceBefore = address(router).balance;

        // messageId is derived from the nonce, so first read it via the recorded log.
        vm.recordLogs();
        bytes32 returnedId = sender.send(SOLANA, PROGRAM, hex"c0ffee", extraArgs, address(0));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        Vm.Log memory log;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == CCIPLocalRouter.SvmMessageSent.selector) log = logs[i];
        }
        assertEq(log.emitter, address(router));
        assertEq(log.topics[1], returnedId, "messageId");
        assertEq(uint256(log.topics[2]), SOLANA, "destinationChainSelector");
        assertEq(address(uint160(uint256(log.topics[3]))), address(sender), "sender");

        (
            bytes32 receiver,
            bytes memory data,
            Client.SVMExtraArgsV1 memory decoded,
            address feeToken,
            uint256 feeAmount,
            uint256 nonce
        ) = abi.decode(log.data, (bytes32, bytes, Client.SVMExtraArgsV1, address, uint256, uint256));
        assertEq(receiver, PROGRAM, "receiver");
        assertEq(data, hex"c0ffee", "data");
        assertEq(decoded.computeUnits, 200_000, "computeUnits");
        assertEq(decoded.accountIsWritableBitmap, 3, "bitmap");
        assertTrue(decoded.allowOutOfOrderExecution, "ooo");
        assertEq(decoded.tokenReceiver, bytes32(uint256(0xbeef)), "tokenReceiver");
        assertEq(decoded.accounts.length, 2, "accounts length");
        assertEq(decoded.accounts[0], bytes32(uint256(1)));
        assertEq(decoded.accounts[1], bytes32(uint256(2)));
        assertEq(feeToken, address(0), "feeToken");
        assertEq(feeAmount, FEE, "fee");
        assertEq(nonce, 1, "nonce");
        assertEq(address(router).balance, routerBalanceBefore + FEE, "native fee collected");

        // Same derivation as the EVM path.
        Client.EVM2AnyMessage memory message =
            _message(abi.encodePacked(PROGRAM), new Client.EVMTokenAmount[](0), extraArgs, address(0));
        assertEq(returnedId, keccak256(abi.encode(uint256(1), address(sender), SOLANA, message)), "id derivation");
    }

    function test_happyPath_expectEmit() public {
        Client.SVMExtraArgsV1 memory args = _args(1, 1, _accounts(1));
        bytes memory extraArgs = Client._svmArgsToBytes(args);
        Client.EVM2AnyMessage memory message =
            _message(abi.encodePacked(PROGRAM), new Client.EVMTokenAmount[](0), extraArgs, address(0));
        bytes32 id = keccak256(abi.encode(uint256(1), address(sender), SOLANA, message));

        vm.expectEmit(true, true, true, true, address(router));
        emit CCIPLocalRouter.SvmMessageSent(
            id, SOLANA, address(sender), PROGRAM, hex"c0ffee", args, address(0), FEE, 1, address(0), 0
        );
        _send(PROGRAM, extraArgs);
    }

    function test_nonceIncrementsAndIdsAreUnique() public {
        assertTrue(_send(PROGRAM, _validArgs()) != _send(PROGRAM, _validArgs()));
    }

    function test_linkFee() public {
        // Fee in LINK is also getFee(): setFee applies to every fee token in this mock.
        uint256 senderBefore = link.balanceOf(address(sender));

        sender.send(SOLANA, PROGRAM, hex"c0ffee", _validArgs(), address(link));

        assertEq(link.balanceOf(address(router)), FEE, "router got LINK fee");
        assertEq(link.balanceOf(address(sender)), senderBefore - FEE, "sender paid LINK fee");
    }

    function test_linkFeeEventFields() public {
        vm.recordLogs();
        sender.send(SOLANA, PROGRAM, hex"c0ffee", _validArgs(), address(link));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(router) && logs[i].topics[0] == CCIPLocalRouter.SvmMessageSent.selector) {
                (,,, address feeToken, uint256 feeAmount,) =
                    abi.decode(logs[i].data, (bytes32, bytes, Client.SVMExtraArgsV1, address, uint256, uint256));
                assertEq(feeToken, address(link));
                assertEq(feeAmount, FEE);
                return;
            }
        }
        revert("SvmMessageSent not emitted");
    }

    /// @dev Router 1.2 keeps the whole msg.value when paying in native, so the recorded fee is the overpaid amount.
    function test_nativeOverpaymentIsKeptAndRecorded() public {
        Client.EVM2AnyMessage memory message =
            _message(abi.encodePacked(PROGRAM), new Client.EVMTokenAmount[](0), _validArgs(), address(0));
        uint256 routerBefore = address(router).balance;

        vm.recordLogs();
        router.ccipSend{value: FEE + 1}(SOLANA, message);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (,,,, uint256 feeAmount,) =
            abi.decode(logs[logs.length - 1].data, (bytes32, bytes, Client.SVMExtraArgsV1, address, uint256, uint256));
        assertEq(feeAmount, FEE + 1, "recorded fee");
        assertEq(address(router).balance, routerBefore + FEE + 1, "whole msg.value kept");
    }

    function test_insufficientNativeFeeReverts() public {
        Client.EVM2AnyMessage memory message =
            _message(abi.encodePacked(PROGRAM), new Client.EVMTokenAmount[](0), _validArgs(), address(0));
        vm.expectRevert(IRouterClient.InsufficientFeeTokenAmount.selector);
        router.ccipSend{value: FEE - 1}(SOLANA, message);
    }

    // ------------------------------------------- allowed on CCIP 2.0 at send time
    // These fail on a CCIP 1.6 lane (mainnet today) but pass the 2.0 send path; problems surface on Solana instead.

    function test_maxBoundariesAreAllowed() public {
        // 3,000,000 CU (lane limit), 255 accounts (one-byte length), every bitmap bit set.
        _send(PROGRAM, _args(3_000_000, type(uint64).max, _accounts(255)));
    }

    function test_zeroReceiverWithComputeUnitsAndAccountsIsAllowed() public {
        _send(bytes32(0), _args(200_000, 1, _accounts(1)));
    }

    function test_writableBitmapBeyondAccountsIsAllowed() public {
        _send(PROGRAM, _args(1, 4, _accounts(2)));
    }

    function test_allowOutOfOrderExecutionFalseIsAccepted() public {
        Client.SVMExtraArgsV1 memory args = _args(1, 0, new bytes32[](0));
        args.allowOutOfOrderExecution = false;
        _send(PROGRAM, args);
    }

    // ---------------------------------------------------------------- reverts

    function test_revert_extraArgsTooShort() public {
        vm.expectRevert(CCIPLocalRouter.InvalidExtraArgsData.selector);
        _send(PROGRAM, hex"1f3b3a");
    }

    function test_revert_emptyExtraArgs() public {
        vm.expectRevert(CCIPLocalRouter.InvalidExtraArgsData.selector);
        _send(PROGRAM, "");
    }

    function test_revert_wrongTag() public {
        // An EVM tag is not valid for Solana.
        vm.expectRevert(CCIPLocalRouter.InvalidExtraArgsTag.selector);
        _send(PROGRAM, _wrongTagArgs());
    }

    /// @dev Production decodes with a plain `abi.decode`, which reverts with no data. The local router must match.
    function test_revert_undecodableExtraArgsHasEmptyRevertData() public {
        Client.EVM2AnyMessage memory message = _message(
            abi.encodePacked(PROGRAM),
            new Client.EVMTokenAmount[](0),
            abi.encodePacked(Client.SVM_EXTRA_ARGS_V1_TAG, hex"1234"),
            address(0)
        );
        (bool success, bytes memory revertData) =
            address(router).call{value: FEE}(abi.encodeCall(router.ccipSend, (SOLANA, message)));
        assertFalse(success, "must revert");
        assertEq(revertData.length, 0, "empty revert data");
    }

    function test_revert_computeUnitsTooHigh() public {
        vm.expectRevert(CCIPLocalRouter.MessageComputeUnitLimitTooHigh.selector);
        _send(PROGRAM, _args(3_000_001, 0, new bytes32[](0)));
    }

    function test_revert_moreThan255Accounts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ExtraArgsCodec.InvalidDataLength.selector,
                ExtraArgsCodec.EncodingErrorLocation.ENCODE_SVM_ACCOUNTS_LENGTH,
                0
            )
        );
        _send(PROGRAM, _args(1, 0, _accounts(256)));
    }

    function test_revert_dataTooLarge() public {
        bytes memory data = new bytes(30_001);
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.MessageTooLarge.selector, 30_000, 30_001));
        sender.send(SOLANA, PROGRAM, data, _validArgs(), address(0));
    }

    function test_revert_receiverNot32Bytes() public {
        Client.EVM2AnyMessage memory message =
            _message(hex"1234", new Client.EVMTokenAmount[](0), _validArgs(), address(0));
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.InvalidDestChainAddress.selector, hex"1234"));
        router.ccipSend{value: FEE}(SOLANA, message);
    }

    /// @dev A token is accepted now; it is pulled from the sender (details in CCIPLocalRouterSvmToken.t.sol).
    function test_oneTokenIsAccepted() public {
        Client.EVM2AnyMessage memory message = _message(abi.encodePacked(PROGRAM), _tokens(1), _validArgs(), address(0));
        uint256 before = link.balanceOf(address(this));
        router.ccipSend{value: FEE}(SOLANA, message);
        assertEq(link.balanceOf(address(this)), before - 1, "token pulled");
    }

    function test_revert_twoTokens() public {
        Client.EVM2AnyMessage memory message = _message(abi.encodePacked(PROGRAM), _tokens(2), _validArgs(), address(0));
        vm.expectRevert(CCIPLocalRouter.CanOnlySendOneTokenPerMessage.selector);
        router.ccipSend{value: FEE}(SOLANA, message);
    }

    // ----------------------------------------- error order (production order)

    /// @dev Router checks msg.value on a fee-token payment before quoting the fee, so it wins over bad extra args.
    function test_order_invalidMsgValueBeforeValidation() public {
        Client.EVM2AnyMessage memory message =
            _message(abi.encodePacked(PROGRAM), new Client.EVMTokenAmount[](0), _wrongTagArgs(), address(link));
        vm.expectRevert(IRouterClient.InvalidMsgValue.selector);
        router.ccipSend{value: 1}(SOLANA, message);
    }

    /// @dev OnRamp.getFee validates before the Router checks the native amount.
    function test_order_validationBeforeInsufficientNativeFee() public {
        Client.EVM2AnyMessage memory message =
            _message(abi.encodePacked(PROGRAM), new Client.EVMTokenAmount[](0), _wrongTagArgs(), address(0));
        vm.expectRevert(CCIPLocalRouter.InvalidExtraArgsTag.selector);
        router.ccipSend{value: FEE - 1}(SOLANA, message);
    }

    /// @dev OnRamp.getFee validates before the Router transfers the fee token.
    function test_order_validationBeforeFeeTokenTransfer() public {
        link.approve(address(router), 0);
        Client.EVM2AnyMessage memory message =
            _message(abi.encodePacked(PROGRAM), new Client.EVMTokenAmount[](0), _wrongTagArgs(), address(link));
        vm.expectRevert(CCIPLocalRouter.InvalidExtraArgsTag.selector);
        router.ccipSend(SOLANA, message);
    }

    /// @dev getFee parses extra args before anything token-related.
    function test_order_extraArgsBeforeToken() public {
        Client.EVM2AnyMessage memory message =
            _message(abi.encodePacked(PROGRAM), _tokens(1), _wrongTagArgs(), address(0));
        vm.expectRevert(CCIPLocalRouter.InvalidExtraArgsTag.selector);
        router.ccipSend{value: FEE}(SOLANA, message);
    }

    /// @dev getFee rejects more than one token before it parses extra args.
    function test_order_tokenCountBeforeExtraArgs() public {
        Client.EVM2AnyMessage memory message =
            _message(abi.encodePacked(PROGRAM), _tokens(2), _wrongTagArgs(), address(0));
        vm.expectRevert(CCIPLocalRouter.CanOnlySendOneTokenPerMessage.selector);
        router.ccipSend{value: FEE}(SOLANA, message);
    }

    /// @dev Token custody is in OnRamp.forwardFromRouter, after the fee, so an insufficient native fee wins and no
    ///      token moves.
    function test_order_insufficientNativeFeeBeforeTokenCustody() public {
        Client.EVM2AnyMessage memory message = _message(abi.encodePacked(PROGRAM), _tokens(1), _validArgs(), address(0));
        uint256 before = link.balanceOf(address(this));
        vm.expectRevert(IRouterClient.InsufficientFeeTokenAmount.selector);
        router.ccipSend{value: FEE - 1}(SOLANA, message);
        assertEq(link.balanceOf(address(this)), before, "no token moved");
    }

    /// @dev The receiver is validated in OnRamp.forwardFromRouter, after the fee is paid.
    function test_order_insufficientNativeFeeBeforeReceiver() public {
        Client.EVM2AnyMessage memory message =
            _message(hex"1234", new Client.EVMTokenAmount[](0), _validArgs(), address(0));
        vm.expectRevert(IRouterClient.InsufficientFeeTokenAmount.selector);
        router.ccipSend{value: FEE - 1}(SOLANA, message);
    }

    // --------------------------------------------------------------- simulator

    function test_isChainSupportedForBothSelectors() public view {
        assertTrue(simulator.isChainSupported(LOCAL_EVM));
        assertTrue(simulator.isChainSupported(SOLANA));
        assertFalse(simulator.isChainSupported(1));
    }

    function test_getSupportedTokensEmptyForSolana() public view {
        assertEq(simulator.getSupportedTokens(SOLANA).length, 0);
        assertEq(simulator.getSupportedTokens(LOCAL_EVM).length, 2);
    }
}
