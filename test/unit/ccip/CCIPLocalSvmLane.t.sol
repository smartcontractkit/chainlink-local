// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CCIPLocalSimulator, IRouterClient} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {CCIPLocalRouter} from "@chainlink/local/src/ccip/CCIPLocalRouter.sol";
import {CCIPLocalSvmLane} from "@chainlink/local/src/ccip/CCIPLocalSvmLane.sol";
import {ICCIPLocalSvmLane} from "@chainlink/local/src/ccip/interfaces/ICCIPLocalSvmLane.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {ExtraArgsCodec} from "@chainlink/contracts-ccip/contracts/libraries/ExtraArgsCodec.sol";
import {Internal} from "@chainlink/contracts-ccip/contracts/libraries/Internal.sol";

/// @dev Has the selector of `ICCIPLocalSvmLane.validate` but is not `pure`, and writes state: only a STATICCALL stops it.
contract WritingLane {
    uint256 public writes;

    function validate(ICCIPLocalSvmLane.SvmLaneVersion, Client.EVM2AnyMessage calldata)
        external
        returns (Client.SVMExtraArgsV1 memory args)
    {
        ++writes;
        return args;
    }
}

/// @dev Reverts with no data.
contract EmptyRevertLane {
    fallback() external {
        revert();
    }
}

/// @notice The router and `CCIPLocalSvmLane` are separate so EVM-only users do not pay for Solana code. These tests
///         cover the seam between them; the Solana rules themselves are covered by `CCIPLocalRouterSvm*.t.sol`.
contract CCIPLocalSvmLaneTest is Test {
    uint64 constant SOLANA = 16423721717087811551;
    uint64 constant LOCAL_EVM = 16015286601757825753;
    bytes32 constant PROGRAM = keccak256("solana-program");

    CCIPLocalRouter router;

    function setUp() public {
        CCIPLocalSimulator simulator = new CCIPLocalSimulator();
        (, IRouterClient sourceRouter,,,,,) = simulator.configuration();
        router = CCIPLocalRouter(address(sourceRouter));
    }

    function _svmMessage(uint256 dataLength) internal pure returns (Client.EVM2AnyMessage memory) {
        return Client.EVM2AnyMessage({
            receiver: abi.encodePacked(PROGRAM),
            data: new bytes(dataLength),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._svmArgsToBytes(
                Client.SVMExtraArgsV1({
                    computeUnits: 1,
                    accountIsWritableBitmap: 0,
                    allowOutOfOrderExecution: true,
                    tokenReceiver: bytes32(0),
                    accounts: new bytes32[](0)
                })
            ),
            feeToken: address(0)
        });
    }

    // ------------------------------------------------------------ registration

    function test_noLaneByDefault() public view {
        assertEq(router.getSvmLane(), address(0));
    }

    function test_setSvmLane_storesLane() public {
        address lane = address(new CCIPLocalSvmLane(address(router)));
        router.setSvmLane(lane);
        assertEq(router.getSvmLane(), lane);
    }

    function test_setSvmLane_rejectsAddressWithoutCode() public {
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.InvalidSvmLane.selector, address(0)));
        router.setSvmLane(address(0));
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.InvalidSvmLane.selector, address(0xBEEF)));
        router.setSvmLane(address(0xBEEF));
    }

    // ----------------------------------------------------------- no lane set

    function test_revert_solanaSendWithoutLane() public {
        vm.expectRevert(CCIPLocalRouter.SvmLaneNotSet.selector);
        router.ccipSend(SOLANA, _svmMessage(0));
    }

    /// @dev The Router's fee-token-with-value check comes before the lane is needed, as in production order.
    function test_revert_invalidMsgValueBeforeMissingLane() public {
        Client.EVM2AnyMessage memory message = _svmMessage(0);
        message.feeToken = address(1);
        vm.expectRevert(IRouterClient.InvalidMsgValue.selector);
        router.ccipSend{value: 1}(SOLANA, message);
    }

    function test_evmSendWorksWithoutLane() public {
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(0xBEEF)),
            data: "",
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: address(0)
        });
        assertTrue(router.ccipSend(LOCAL_EVM, message) != bytes32(0));
    }

    // ------------------------------------------------------- external call risks

    /// @dev A lane that writes state must fail: the router has to reach it with STATICCALL, so a replaced or malicious
    ///      lane cannot touch router state (the nonce, the fee) or move funds.
    function test_laneCallIsStaticcall() public {
        WritingLane lane = new WritingLane();
        router.setSvmLane(address(lane));

        // A failed write in a static context burns the gas forwarded to the call, so cap it.
        vm.expectRevert();
        router.ccipSend{gas: 2_000_000}(SOLANA, _svmMessage(0));
        assertEq(lane.writes(), 0);

        // Control: the same function does write when it is called without STATICCALL.
        lane.validate(ICCIPLocalSvmLane.SvmLaneVersion.V2_0, _svmMessage(0));
        assertEq(lane.writes(), 1);
    }

    /// @dev The router has no try/catch: whatever the lane reverts with, including nothing, reaches the sender.
    function test_laneEmptyRevertDataBubblesUp() public {
        router.setSvmLane(address(new EmptyRevertLane()));
        (bool success, bytes memory revertData) =
            address(router).call(abi.encodeCall(router.ccipSend, (SOLANA, _svmMessage(0))));
        assertFalse(success);
        assertEq(revertData.length, 0);
    }

    /// @dev Production behaviour of an undecodable `SVMExtraArgsV1` body is a revert with no data (plain `abi.decode`),
    ///      in both lane versions.
    function test_undecodableExtraArgsRevertsWithEmptyDataThroughRouter() public {
        router.setSvmLane(address(new CCIPLocalSvmLane(address(router))));
        Client.EVM2AnyMessage memory message = _svmMessage(0);
        message.extraArgs = abi.encodePacked(Client.SVM_EXTRA_ARGS_V1_TAG, hex"1234");

        for (uint256 i; i < 2; ++i) {
            router.setSvmLaneVersion(CCIPLocalRouter.SvmLaneVersion(i));
            (bool success, bytes memory revertData) =
                address(router).call(abi.encodeCall(router.ccipSend, (SOLANA, message)));
            assertFalse(success);
            assertEq(revertData.length, 0);
        }
    }

    // ------------------------------------------------------------- versions

    /// @dev One lane serves both versions: a 2,000-byte payload fits the 2.0 lane (30,000) but not the 1.6 lane (1,280).
    function test_oneLaneServesBothVersions() public {
        router.setSvmLane(address(new CCIPLocalSvmLane(address(router))));
        Client.EVM2AnyMessage memory message = _svmMessage(2_000);

        router.ccipSend(SOLANA, message);

        router.setSvmLaneVersion(CCIPLocalRouter.SvmLaneVersion.V1_6);
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.MessageTooLarge.selector, 1_280, 2_000));
        router.ccipSend(SOLANA, message);

        router.setSvmLaneVersion(CCIPLocalRouter.SvmLaneVersion.V2_0);
        router.ccipSend(SOLANA, message);
    }

    function test_laneIsCallableDirectly() public {
        CCIPLocalSvmLane lane = new CCIPLocalSvmLane(address(router));
        Client.SVMExtraArgsV1 memory args = lane.validate(ICCIPLocalSvmLane.SvmLaneVersion.V2_0, _svmMessage(0));
        assertEq(args.computeUnits, 1);
        vm.expectRevert(abi.encodeWithSelector(CCIPLocalRouter.MessageTooLarge.selector, 1_280, 2_000));
        lane.validate(ICCIPLocalSvmLane.SvmLaneVersion.V1_6, _svmMessage(2_000));
    }

    // ------------------------------------------------------ declarations in sync

    /// @dev The router and the lane interface each declare the enum and the Solana errors (Solidity cannot share them).
    ///      They must stay identical: the router passes its enum to the lane as a `uint8` and users decode lane reverts
    ///      with the router ABI.
    function test_routerAndLaneDeclarationsMatch() public {
        assertEq(uint8(type(CCIPLocalRouter.SvmLaneVersion).max), uint8(type(ICCIPLocalSvmLane.SvmLaneVersion).max));
        assertEq(uint8(CCIPLocalRouter.SvmLaneVersion.V1_6), uint8(ICCIPLocalSvmLane.SvmLaneVersion.V1_6));

        assertEq(CCIPLocalRouter.InvalidExtraArgsTag.selector, ICCIPLocalSvmLane.InvalidExtraArgsTag.selector);
        assertEq(
            CCIPLocalRouter.CanOnlySendOneTokenPerMessage.selector,
            ICCIPLocalSvmLane.CanOnlySendOneTokenPerMessage.selector
        );
        assertEq(CCIPLocalRouter.CannotSendZeroTokens.selector, ICCIPLocalSvmLane.CannotSendZeroTokens.selector);
        assertEq(CCIPLocalRouter.ReceiverError.selector, ICCIPLocalSvmLane.ReceiverError.selector);
        assertEq(CCIPLocalRouter.InvalidOptionalThreshold.selector, ICCIPLocalSvmLane.InvalidOptionalThreshold.selector);
        assertEq(router.SOLANA_CHAIN_SELECTOR(), new CCIPLocalSvmLane(address(router)).SOLANA_CHAIN_SELECTOR());
        assertEq(CCIPLocalRouter.InvalidExtraArgsData.selector, ICCIPLocalSvmLane.InvalidExtraArgsData.selector);
        assertEq(
            CCIPLocalRouter.MessageComputeUnitLimitTooHigh.selector,
            ICCIPLocalSvmLane.MessageComputeUnitLimitTooHigh.selector
        );
        assertEq(CCIPLocalRouter.MessageTooLarge.selector, ICCIPLocalSvmLane.MessageTooLarge.selector);
        assertEq(CCIPLocalRouter.InvalidDestChainAddress.selector, ICCIPLocalSvmLane.InvalidDestChainAddress.selector);
        assertEq(CCIPLocalRouter.InvalidTokenReceiver.selector, ICCIPLocalSvmLane.InvalidTokenReceiver.selector);
        assertEq(
            CCIPLocalRouter.TooManySVMExtraArgsAccounts.selector, ICCIPLocalSvmLane.TooManySVMExtraArgsAccounts.selector
        );
        assertEq(
            CCIPLocalRouter.InvalidSVMExtraArgsWritableBitmap.selector,
            ICCIPLocalSvmLane.InvalidSVMExtraArgsWritableBitmap.selector
        );
        assertEq(
            CCIPLocalRouter.UnsupportedNumberOfTokens.selector, ICCIPLocalSvmLane.UnsupportedNumberOfTokens.selector
        );
        // Library errors the lane raises, redeclared on the router for its ABI.
        assertEq(CCIPLocalRouter.Invalid32ByteAddress.selector, Internal.Invalid32ByteAddress.selector);
        assertEq(CCIPLocalRouter.InvalidDataLength.selector, ExtraArgsCodec.InvalidDataLength.selector);
    }
}
