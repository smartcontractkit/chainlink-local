// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, Vm} from "forge-std/Test.sol";
import {CCIPLocalSimulator, IRouterClient} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {CCIPLocalRouter} from "@chainlink/local/src/ccip/CCIPLocalRouter.sol";
import {SvmMessageSender} from "@chainlink/local/src/test/ccip/SvmMessageSender.sol";
import {LinkToken} from "@chainlink/local/src/shared/LinkToken.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts@5.3.0/token/ERC20/IERC20.sol";

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
        vm.deal(address(sender), 10 ether);
        simulator.requestLinkFromFaucet(address(sender), 10 ether);
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

    function _accounts(uint256 n) internal pure returns (bytes32[] memory accounts) {
        accounts = new bytes32[](n);
        for (uint256 i; i < n; ++i) {
            accounts[i] = bytes32(i + 1);
        }
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
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encodePacked(PROGRAM),
            data: hex"c0ffee",
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: extraArgs,
            feeToken: address(0)
        });
        assertEq(returnedId, keccak256(abi.encode(uint256(1), address(sender), SOLANA, message)), "id derivation");
    }

    function test_happyPath_expectEmit() public {
        bytes32[] memory accounts = _accounts(1);
        Client.SVMExtraArgsV1 memory args = _args(1, 1, accounts);
        bytes memory extraArgs = Client._svmArgsToBytes(args);
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encodePacked(PROGRAM),
            data: hex"c0ffee",
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: extraArgs,
            feeToken: address(0)
        });
        bytes32 id = keccak256(abi.encode(uint256(1), address(sender), SOLANA, message));

        vm.expectEmit(true, true, true, true, address(router));
        emit CCIPLocalRouter.SvmMessageSent(id, SOLANA, address(sender), PROGRAM, hex"c0ffee", args, address(0), FEE, 1);
        _send(PROGRAM, extraArgs);
    }

    function test_nonceIncrementsAndIdsAreUnique() public {
        bytes memory extraArgs = Client._svmArgsToBytes(_args(1, 0, new bytes32[](0)));
        assertTrue(_send(PROGRAM, extraArgs) != _send(PROGRAM, extraArgs));
    }

    function test_linkFee() public {
        bytes memory extraArgs = Client._svmArgsToBytes(_args(1, 0, new bytes32[](0)));
        // Fee in LINK is also getFee(): setFee applies to every fee token in this mock.
        uint256 senderBefore = link.balanceOf(address(sender));

        sender.send(SOLANA, PROGRAM, hex"c0ffee", extraArgs, address(link));

        assertEq(link.balanceOf(address(router)), FEE, "router got LINK fee");
        assertEq(link.balanceOf(address(sender)), senderBefore - FEE, "sender paid LINK fee");
    }

    function test_linkFeeEventFields() public {
        bytes memory extraArgs = Client._svmArgsToBytes(_args(1, 0, new bytes32[](0)));
        vm.recordLogs();
        sender.send(SOLANA, PROGRAM, hex"c0ffee", extraArgs, address(link));
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

    function test_zeroReceiverWithZeroComputeUnitsIsAllowed() public {
        _send(bytes32(0), _args(0, 0, new bytes32[](0)));
    }

    function test_maxBoundariesAreAllowed() public {
        // 1,400,000 CU, 64 accounts, bitmap with all 64 bits set.
        _send(PROGRAM, _args(1_400_000, type(uint64).max, _accounts(64)));
    }

    function test_insufficientNativeFeeReverts() public {
        // Call the router directly with too little value.
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encodePacked(PROGRAM),
            data: "",
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._svmArgsToBytes(_args(1, 0, new bytes32[](0))),
            feeToken: address(0)
        });
        vm.expectRevert(IRouterClient.InsufficientFeeTokenAmount.selector);
        router.ccipSend{value: FEE - 1}(SOLANA, message);
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
        bytes memory extraArgs =
            Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 1, allowOutOfOrderExecution: true}));
        vm.expectRevert(CCIPLocalRouter.InvalidExtraArgsTag.selector);
        _send(PROGRAM, extraArgs);
    }

    function test_revert_undecodableExtraArgs() public {
        vm.expectRevert();
        _send(PROGRAM, abi.encodePacked(Client.SVM_EXTRA_ARGS_V1_TAG, hex"1234"));
    }

    function test_revert_computeUnitsTooHigh() public {
        vm.expectRevert(CCIPLocalRouter.MessageComputeUnitLimitTooHigh.selector);
        _send(PROGRAM, _args(1_400_001, 0, new bytes32[](0)));
    }

    function test_revert_receiverNot32Bytes() public {
        bytes memory extraArgs = Client._svmArgsToBytes(_args(1, 0, new bytes32[](0)));
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: hex"1234",
            data: "",
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: extraArgs,
            feeToken: address(0)
        });
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.Invalid32ByteAddress.selector, hex"1234"));
        router.ccipSend{value: FEE}(SOLANA, message);
    }

    function test_revert_zeroReceiverWithComputeUnits() public {
        vm.expectRevert(
            abi.encodeWithSelector(CCIPLocalRouter.Invalid32ByteAddress.selector, abi.encodePacked(bytes32(0)))
        );
        _send(bytes32(0), _args(1, 0, new bytes32[](0)));
    }

    function test_revert_zeroReceiverWithAccounts() public {
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.TooManySVMExtraArgsAccounts.selector, 1, 0));
        _send(bytes32(0), _args(0, 0, _accounts(1)));
    }

    function test_revert_tooManyAccounts() public {
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.TooManySVMExtraArgsAccounts.selector, 65, 64));
        _send(PROGRAM, _args(1, 0, _accounts(65)));
    }

    function test_revert_writableBitmapExceedsAccounts() public {
        // 2 accounts: bits above bit 1 must be unset.
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.InvalidSVMExtraArgsWritableBitmap.selector, 4, 2));
        _send(PROGRAM, _args(1, 4, _accounts(2)));
    }

    function test_revert_writableBitmapWithNoAccounts() public {
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.InvalidSVMExtraArgsWritableBitmap.selector, 1, 0));
        _send(PROGRAM, _args(1, 1, new bytes32[](0)));
    }

    function test_revert_tokenAmounts() public {
        Client.EVMTokenAmount[] memory tokens = new Client.EVMTokenAmount[](1);
        tokens[0] = Client.EVMTokenAmount({token: address(link), amount: 1});
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encodePacked(PROGRAM),
            data: "",
            tokenAmounts: tokens,
            extraArgs: Client._svmArgsToBytes(_args(1, 0, new bytes32[](0))),
            feeToken: address(0)
        });
        vm.expectRevert(CCIPLocalRouter.SvmTokenTransfersNotSupported.selector);
        router.ccipSend{value: FEE}(SOLANA, message);
    }

    function test_allowOutOfOrderExecutionFalseIsAccepted() public {
        Client.SVMExtraArgsV1 memory args = _args(1, 0, new bytes32[](0));
        args.allowOutOfOrderExecution = false;
        _send(PROGRAM, args);
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
