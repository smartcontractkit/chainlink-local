// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, Vm} from "forge-std/Test.sol";
import {CCIPLocalSimulator, IRouterClient} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {CCIPLocalRouter} from "@chainlink/local/src/ccip/CCIPLocalRouter.sol";
import {SvmMessageSender} from "@chainlink/local/src/test/ccip/SvmMessageSender.sol";
import {LinkToken} from "@chainlink/local/src/shared/LinkToken.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {Internal} from "@chainlink/contracts-ccip/contracts/libraries/Internal.sol";

/// @notice With `SvmLaneVersion.V1_6`, Solana sends through `CCIPLocalRouter` must follow the CCIP 1.6 lane (Router 1.2 +
///         OnRamp 1.6.0 + FeeQuoter 2.0.0, as on mainnet Ethereum -> Solana): same checks, same errors, same order, and
///         the mainnet lane limits (1,400,000 compute units, 1,280 bytes).
contract CCIPLocalRouterSvm16Test is Test {
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
        router.setSvmLaneVersion(CCIPLocalRouter.SvmLaneVersion.V1_6);
        vm.deal(address(sender), 10 ether);
        simulator.requestLinkFromFaucet(address(sender), 10 ether);
        simulator.requestLinkFromFaucet(address(this), 10 ether);
        link.approve(address(router), type(uint256).max);
    }

    // ---------------------------------------------------------------- helpers

    function _args(uint32 computeUnits, uint64 bitmap, uint256 accountCount)
        internal
        pure
        returns (Client.SVMExtraArgsV1 memory args)
    {
        bytes32[] memory accounts = new bytes32[](accountCount);
        for (uint256 i; i < accountCount; ++i) {
            accounts[i] = bytes32(i + 1);
        }
        args = Client.SVMExtraArgsV1({
            computeUnits: computeUnits,
            accountIsWritableBitmap: bitmap,
            allowOutOfOrderExecution: true,
            tokenReceiver: bytes32(0),
            accounts: accounts
        });
    }

    function _validArgs() internal pure returns (bytes memory) {
        return Client._svmArgsToBytes(_args(1, 0, 0));
    }

    function _tokens(uint256 n, uint256 amount) internal view returns (Client.EVMTokenAmount[] memory tokens) {
        tokens = new Client.EVMTokenAmount[](n);
        for (uint256 i; i < n; ++i) {
            tokens[i] = Client.EVMTokenAmount({token: address(link), amount: amount});
        }
    }

    function _message(bytes memory receiver, bytes memory data, bytes memory extraArgs)
        internal
        pure
        returns (Client.EVM2AnyMessage memory)
    {
        return Client.EVM2AnyMessage({
            receiver: receiver,
            data: data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: extraArgs,
            feeToken: address(0)
        });
    }

    function _message(bytes memory extraArgs) internal pure returns (Client.EVM2AnyMessage memory) {
        return _message(abi.encodePacked(PROGRAM), hex"c0ffee", extraArgs);
    }

    function _send(Client.EVM2AnyMessage memory message) internal returns (bytes32) {
        return router.ccipSend{value: FEE}(SOLANA, message);
    }

    function _send(bytes memory extraArgs) internal returns (bytes32) {
        return _send(_message(extraArgs));
    }

    function _send(Client.SVMExtraArgsV1 memory args) internal returns (bytes32) {
        return _send(Client._svmArgsToBytes(args));
    }

    function _lastSvmMessageSent() internal returns (Vm.Log memory) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = logs.length; i > 0; --i) {
            if (
                logs[i - 1].emitter == address(router)
                    && logs[i - 1].topics[0] == CCIPLocalRouter.SvmMessageSent.selector
            ) {
                return logs[i - 1];
            }
        }
        revert("SvmMessageSent not emitted");
    }

    // ---------------------------------------------------------------- version

    function test_defaultLaneVersionIsV2_0() public {
        CCIPLocalSimulator fresh = new CCIPLocalSimulator();
        (, IRouterClient freshRouter,,,,,) = fresh.configuration();
        assertEq(
            uint8(CCIPLocalRouter(address(freshRouter)).getSvmLaneVersion()), uint8(CCIPLocalRouter.SvmLaneVersion.V2_0)
        );
    }

    function test_setSvmLaneVersionHasNoAccessControl() public {
        assertEq(uint8(router.getSvmLaneVersion()), uint8(CCIPLocalRouter.SvmLaneVersion.V1_6));
        vm.prank(address(0xBEEF));
        router.setSvmLaneVersion(CCIPLocalRouter.SvmLaneVersion.V2_0);
        assertEq(uint8(router.getSvmLaneVersion()), uint8(CCIPLocalRouter.SvmLaneVersion.V2_0));
    }

    /// @dev A rule that only exists on 1.6 stops applying once the lane is set back to 2.0.
    function test_switchingBackToV2_0RestoresTheLooserRules() public {
        Client.SVMExtraArgsV1 memory args = _args(1, 4, 2);
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.InvalidSVMExtraArgsWritableBitmap.selector, 4, 2));
        _send(args);

        router.setSvmLaneVersion(CCIPLocalRouter.SvmLaneVersion.V2_0);
        _send(args);
    }

    function test_evmDestinationIsUnaffectedByTheLaneVersion() public {
        bytes32 receiver = bytes32(uint256(uint160(address(0xBEEF)))); // EOA: delivered as a token-only transfer
        assertTrue(sender.send(LOCAL_EVM, receiver, "", "", address(0)) != bytes32(0));
    }

    // ------------------------------------------------------------- happy path

    function test_happyPath_emitsEveryField() public {
        Client.SVMExtraArgsV1 memory args = _args(200_000, 3, 2);
        args.tokenReceiver = bytes32(uint256(0xbeef));
        bytes memory extraArgs = Client._svmArgsToBytes(args);
        uint256 routerBalanceBefore = address(router).balance;

        vm.recordLogs();
        bytes32 returnedId = sender.send(SOLANA, PROGRAM, hex"c0ffee", extraArgs, address(0));
        Vm.Log memory log = _lastSvmMessageSent();

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

        // Same derivation as the 2.0 path and the EVM path.
        Client.EVM2AnyMessage memory message = _message(abi.encodePacked(PROGRAM), hex"c0ffee", extraArgs);
        assertEq(returnedId, keccak256(abi.encode(uint256(1), address(sender), SOLANA, message)), "id derivation");
    }

    function test_happyPath_linkFee() public {
        uint256 senderBefore = link.balanceOf(address(sender));
        vm.recordLogs();
        sender.send(SOLANA, PROGRAM, hex"c0ffee", _validArgs(), address(link));
        Vm.Log memory log = _lastSvmMessageSent();

        (,,, address feeToken, uint256 feeAmount,) =
            abi.decode(log.data, (bytes32, bytes, Client.SVMExtraArgsV1, address, uint256, uint256));
        assertEq(feeToken, address(link));
        assertEq(feeAmount, FEE);
        assertEq(link.balanceOf(address(router)), FEE, "router got LINK fee");
        assertEq(link.balanceOf(address(sender)), senderBefore - FEE, "sender paid LINK fee");
    }

    function test_happyPath_nativeOverpaymentIsKeptAndRecorded() public {
        vm.recordLogs();
        router.ccipSend{value: FEE + 1}(SOLANA, _message(_validArgs()));
        Vm.Log memory log = _lastSvmMessageSent();
        (,,,, uint256 feeAmount,) =
            abi.decode(log.data, (bytes32, bytes, Client.SVMExtraArgsV1, address, uint256, uint256));
        assertEq(feeAmount, FEE + 1, "recorded fee");
    }

    function test_happyPath_boundaries() public {
        // 1,400,000 CU (the mainnet lane limit) and 37 accounts, all writable: with a 3-byte payload,
        // 3 + (37 + 2) * 32 = 1,251 bytes fits in 1,280. 38 accounts would not (1,283).
        _send(_args(1_400_000, (uint64(1) << 37) - 1, 37));
    }

    /// @dev 64 accounts pass the account-count check, but on this lane's 1,280 bytes they always exceed the size limit.
    function test_revert_sixtyFourAccountsExceedTheLaneSize() public {
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.MessageTooLarge.selector, 1_280, 3 + 66 * 32));
        _send(_args(1, 0, 64));
    }

    /// @dev FeeQuoter 2.0.0 treats every message as out-of-order, so `allowOutOfOrderExecution = false` is accepted.
    function test_happyPath_outOfOrderFalseIsAccepted() public {
        Client.SVMExtraArgsV1 memory args = _args(1, 0, 0);
        args.allowOutOfOrderExecution = false;
        _send(args);
    }

    function test_happyPath_zeroReceiverWithoutComputeUnitsAndAccounts() public {
        vm.recordLogs();
        _send(_message(abi.encodePacked(bytes32(0)), hex"c0ffee", Client._svmArgsToBytes(_args(0, 0, 0))));
        Vm.Log memory log = _lastSvmMessageSent();
        (bytes32 receiver,,,,,) =
            abi.decode(log.data, (bytes32, bytes, Client.SVMExtraArgsV1, address, uint256, uint256));
        assertEq(receiver, bytes32(0));
    }

    function test_happyPath_payloadPlusAccountOverheadExactlyAtTheLimit() public {
        // 2 accounts: (2 + 2) * 32 = 128 bytes of overhead on top of the payload.
        _send(_message(abi.encodePacked(PROGRAM), new bytes(1_280 - 128), Client._svmArgsToBytes(_args(1, 0, 2))));
    }

    // ---------------------------------------------------------------- reverts

    function test_revert_feeTokenPaymentWithNativeValue() public {
        Client.EVM2AnyMessage memory message = _message(_validArgs());
        message.feeToken = address(link);
        vm.expectRevert(IRouterClient.InvalidMsgValue.selector);
        router.ccipSend{value: 1}(SOLANA, message);
    }

    function test_revert_dataTooLarge() public {
        Client.EVM2AnyMessage memory message = _message(abi.encodePacked(PROGRAM), new bytes(1_281), _validArgs());
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.MessageTooLarge.selector, 1_280, 1_281));
        _send(message);
    }

    function test_revert_expandedDataTooLarge() public {
        // The payload alone fits, but the receiver and OffRamp signer accounts push it over: 1_217 + 2 * 32 = 1_281.
        Client.EVM2AnyMessage memory message = _message(abi.encodePacked(PROGRAM), new bytes(1_217), _validArgs());
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.MessageTooLarge.selector, 1_280, 1_281));
        _send(message);
    }

    function test_revert_twoTokens() public {
        Client.EVM2AnyMessage memory message = _message(_validArgs());
        message.tokenAmounts = _tokens(2, 1);
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.UnsupportedNumberOfTokens.selector, 2, 1));
        _send(message);
    }

    function test_revert_emptyExtraArgs() public {
        vm.expectRevert(CCIPLocalRouter.InvalidExtraArgsData.selector);
        _send(hex"");
    }

    /// @dev FeeQuoter 2.0.0 rejects anything shorter than the 4-byte tag with `InvalidExtraArgsData`.
    function test_revert_extraArgsOneToThreeBytes() public {
        bytes memory extraArgs = hex"1f3b3a";
        for (uint256 length = 1; length <= 3; ++length) {
            bytes memory shortArgs = new bytes(length);
            for (uint256 i; i < length; ++i) {
                shortArgs[i] = extraArgs[i];
            }
            vm.expectRevert(CCIPLocalRouter.InvalidExtraArgsData.selector);
            _send(shortArgs);
        }
    }

    function test_revert_wrongTag() public {
        bytes memory extraArgs =
            Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 1, allowOutOfOrderExecution: true}));
        vm.expectRevert(CCIPLocalRouter.InvalidExtraArgsTag.selector);
        _send(extraArgs);
    }

    function test_revert_undecodableExtraArgsHasEmptyRevertData() public {
        bytes memory extraArgs = abi.encodePacked(Client.SVM_EXTRA_ARGS_V1_TAG, hex"1234");
        (bool success, bytes memory revertData) =
            address(router).call{value: FEE}(abi.encodeCall(router.ccipSend, (SOLANA, _message(extraArgs))));
        assertFalse(success, "must revert");
        assertEq(revertData.length, 0, "empty revert data");
    }

    function test_revert_computeUnitsTooHigh() public {
        vm.expectRevert(CCIPLocalRouter.MessageComputeUnitLimitTooHigh.selector);
        _send(_args(1_400_001, 0, 0));
    }

    function test_revert_receiverNot32Bytes() public {
        vm.expectRevert(abi.encodeWithSelector(Internal.Invalid32ByteAddress.selector, hex"1234"));
        _send(_message(hex"1234", hex"c0ffee", _validArgs()));
    }

    function test_revert_zeroReceiverWithComputeUnits() public {
        vm.expectRevert(abi.encodeWithSelector(Internal.Invalid32ByteAddress.selector, abi.encodePacked(bytes32(0))));
        _send(_message(abi.encodePacked(bytes32(0)), hex"c0ffee", _validArgs()));
    }

    function test_revert_zeroReceiverWithAccounts() public {
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.TooManySVMExtraArgsAccounts.selector, 1, 0));
        _send(_message(abi.encodePacked(bytes32(0)), hex"c0ffee", Client._svmArgsToBytes(_args(0, 0, 1))));
    }

    function test_revert_tokenWithoutTokenReceiver() public {
        Client.EVM2AnyMessage memory message = _message(_validArgs());
        message.tokenAmounts = _tokens(1, 1);
        vm.expectRevert(CCIPLocalRouter.InvalidTokenReceiver.selector);
        _send(message);
    }

    function test_revert_moreThan64Accounts() public {
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.TooManySVMExtraArgsAccounts.selector, 65, 64));
        _send(_args(1, 0, 65));
    }

    function test_revert_writableBitmapBeyondAccounts() public {
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.InvalidSVMExtraArgsWritableBitmap.selector, 4, 2));
        _send(_args(1, 4, 2));
    }

    function test_revert_insufficientNativeFee() public {
        vm.expectRevert(IRouterClient.InsufficientFeeTokenAmount.selector);
        router.ccipSend{value: FEE - 1}(SOLANA, _message(_validArgs()));
    }

    function test_revert_oneTokenIsUnsupported() public {
        Client.SVMExtraArgsV1 memory args = _args(1, 0, 0);
        args.tokenReceiver = bytes32(uint256(1));
        Client.EVM2AnyMessage memory message = _message(Client._svmArgsToBytes(args));
        message.tokenAmounts = _tokens(1, 1);
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.UnsupportedToken.selector, address(link)));
        _send(message);
    }

    function test_revert_zeroAmountToken() public {
        Client.SVMExtraArgsV1 memory args = _args(1, 0, 0);
        args.tokenReceiver = bytes32(uint256(1));
        Client.EVM2AnyMessage memory message = _message(Client._svmArgsToBytes(args));
        message.tokenAmounts = _tokens(1, 0);
        vm.expectRevert(CCIPLocalRouter.CannotSendZeroTokens.selector);
        _send(message);
    }

    // ----------------------------------------- error order (FeeQuoter.sol:761)

    /// @dev Router checks msg.value on a fee-token payment before it quotes the fee.
    function test_order_invalidMsgValueBeforeValidation() public {
        Client.EVM2AnyMessage memory message = _message(hex"");
        message.feeToken = address(link);
        vm.expectRevert(IRouterClient.InvalidMsgValue.selector);
        router.ccipSend{value: 1}(SOLANA, message);
    }

    function test_order_dataSizeBeforeTokenCount() public {
        Client.EVM2AnyMessage memory message = _message(abi.encodePacked(PROGRAM), new bytes(1_281), hex"");
        message.tokenAmounts = _tokens(2, 1);
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.MessageTooLarge.selector, 1_280, 1_281));
        _send(message);
    }

    function test_order_tokenCountBeforeExtraArgs() public {
        Client.EVM2AnyMessage memory message = _message(hex"");
        message.tokenAmounts = _tokens(2, 1);
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.UnsupportedNumberOfTokens.selector, 2, 1));
        _send(message);
    }

    function test_order_computeUnitsBeforeReceiver() public {
        vm.expectRevert(CCIPLocalRouter.MessageComputeUnitLimitTooHigh.selector);
        _send(_message(hex"1234", hex"c0ffee", Client._svmArgsToBytes(_args(1_400_001, 0, 0))));
    }

    /// @dev In 1.6 the receiver is validated in getValidatedFee, before the fee is paid (2.0 checks it after).
    function test_order_receiverBeforeInsufficientNativeFee() public {
        vm.expectRevert(abi.encodeWithSelector(Internal.Invalid32ByteAddress.selector, hex"1234"));
        router.ccipSend{value: FEE - 1}(SOLANA, _message(hex"1234", hex"c0ffee", _validArgs()));
    }

    function test_order_receiverBeforeZeroReceiverAccounts() public {
        vm.expectRevert(abi.encodeWithSelector(Internal.Invalid32ByteAddress.selector, abi.encodePacked(bytes32(0))));
        _send(_message(abi.encodePacked(bytes32(0)), hex"c0ffee", Client._svmArgsToBytes(_args(1, 0, 1))));
    }

    function test_order_zeroReceiverAccountsBeforeTokenReceiver() public {
        Client.EVM2AnyMessage memory message =
            _message(abi.encodePacked(bytes32(0)), hex"c0ffee", Client._svmArgsToBytes(_args(0, 0, 1)));
        message.tokenAmounts = _tokens(1, 1);
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.TooManySVMExtraArgsAccounts.selector, 1, 0));
        _send(message);
    }

    function test_order_tokenReceiverBeforeAccountCount() public {
        Client.EVM2AnyMessage memory message = _message(Client._svmArgsToBytes(_args(1, 0, 65)));
        message.tokenAmounts = _tokens(1, 1);
        vm.expectRevert(CCIPLocalRouter.InvalidTokenReceiver.selector);
        _send(message);
    }

    function test_order_bitmapBeforeExpandedSize() public {
        Client.EVM2AnyMessage memory message =
            _message(abi.encodePacked(PROGRAM), new bytes(1_217), Client._svmArgsToBytes(_args(1, 4, 0)));
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.InvalidSVMExtraArgsWritableBitmap.selector, 4, 0));
        _send(message);
    }

    /// @dev The fee is paid before the OnRamp rejects the token.
    function test_order_insufficientNativeFeeBeforeUnsupportedToken() public {
        Client.SVMExtraArgsV1 memory args = _args(1, 0, 0);
        args.tokenReceiver = bytes32(uint256(1));
        Client.EVM2AnyMessage memory message = _message(Client._svmArgsToBytes(args));
        message.tokenAmounts = _tokens(1, 1);
        vm.expectRevert(IRouterClient.InsufficientFeeTokenAmount.selector);
        router.ccipSend{value: FEE - 1}(SOLANA, message);
    }
}
