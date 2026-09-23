// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CCIPLocalSimulator, IRouterClient, BurnMintERC677Helper} from "../../../src/ccip/CCIPLocalSimulator.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {ExtraArgsCodec} from "@chainlink/contracts-ccip/contracts/libraries/ExtraArgsCodec.sol";
import {FinalityCodec} from "@chainlink/contracts-ccip/contracts/libraries/FinalityCodec.sol";
import {MockCCIPRouter} from "@chainlink/contracts-ccip/contracts/test/mocks/MockRouter.sol";

import {BasicMessageReceiver} from "../../../src/test/ccip/BasicMessageReceiver.sol";
import {BasicMessageReceiverWithCCVs} from "../../../src/test/ccip/BasicMessageReceiverWithCCVs.sol";

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
}
