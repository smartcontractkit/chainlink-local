// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {Internal} from "@chainlink/contracts-ccip/contracts/libraries/Internal.sol";

/// @dev The one `CCIPLocalRouter` function the lane reads.
interface ICCIPLocalRouterLaneVersion {
    /// @dev Returns `CCIPLocalRouter.SvmLaneVersion`, which has the same members as `ICCIPLocalSvmLane.SvmLaneVersion`.
    function getSvmLaneVersion() external view returns (uint8);
}

/// @title ICCIPLocalSvmLane
/// @notice The Solana rules of `CCIPLocalRouter`, kept in a separate contract so that EVM-only users do not pay for
///         them in the `CCIPLocalSimulator` initcode (EIP-3860 limit: 49,152 bytes): the send rules (`validate`), the
///         escrow of tokens sent to Solana, and delivery of Solana -> EVM messages (`execute`).
/// @dev Solidity does not expose inherited errors or enums through the inheriting contract's name
///      (`CCIPLocalRouter.MessageTooLarge` would not compile), so `CCIPLocalRouter` declares the same enum and errors
///      itself and the lane gets them from here. Keep both in sync: `CCIPLocalSvmLaneTest` compares them.
interface ICCIPLocalSvmLane {
    /// @notice The CCIP version of the lane that Solana-bound sends are validated against.
    /// @dev V2_0: Router 1.2 + OnRamp 2.0.0 + FeeQuoter 2.0.0. V1_6: Router 1.2 + OnRamp 1.6.0 + FeeQuoter 2.0.0, the
    ///      lane mainnet Ethereum -> Solana runs today (OnRamp 0x913814782144864e523C3FdB78E3ca25D2c2aeCa uses
    ///      FeeQuoter 0x93669Cf8EabE869687544De34B453063fb23Bb69, read on 19 Nov 2026).
    enum SvmLaneVersion {
        V2_0,
        V1_6
    }

    error InvalidExtraArgsTag();
    /// @dev Mirrors `OnRamp.CanOnlySendOneTokenPerMessage`.
    error CanOnlySendOneTokenPerMessage();
    /// @dev Mirrors `OnRamp.CannotSendZeroTokens`.
    error CannotSendZeroTokens();

    /// @dev Mirrors `FeeQuoter.InvalidExtraArgsData` (2.0).
    error InvalidExtraArgsData();
    /// @dev Mirrors `FeeQuoter.MessageComputeUnitLimitTooHigh` (2.0).
    error MessageComputeUnitLimitTooHigh();
    /// @dev Mirrors `FeeQuoter.MessageTooLarge` (2.0).
    error MessageTooLarge(uint256 maxSize, uint256 actualSize);
    /// @dev Mirrors `OnRamp.InvalidDestChainAddress` (2.0).
    error InvalidDestChainAddress(bytes destChainAddress);

    /// @dev Mirrors `FeeQuoter.InvalidTokenReceiver` (1.6).
    error InvalidTokenReceiver();
    /// @dev Mirrors `FeeQuoter.TooManySVMExtraArgsAccounts` (1.6).
    error TooManySVMExtraArgsAccounts(uint256 numAccounts, uint256 maxAccounts);
    /// @dev Mirrors `FeeQuoter.InvalidSVMExtraArgsWritableBitmap` (1.6).
    error InvalidSVMExtraArgsWritableBitmap(uint64 accountIsWritableBitmap, uint256 numAccounts);
    /// @dev Mirrors `FeeQuoter.UnsupportedNumberOfTokens` (1.6).
    error UnsupportedNumberOfTokens(uint256 numberOfTokens, uint256 maxNumberOfTokensPerMsg);

    /// @notice A Solana -> EVM message, already decoded from the Solana `CCIPMessage` by the offchain layer.
    /// @param messageId The Solana message id.
    /// @param sourceChainSelector Must be `SOLANA_CHAIN_SELECTOR`.
    /// @param sequenceNumber The Solana sequence number (informational, as `messageNumber` in the OffRamp event).
    /// @param sender The 32-byte Solana sender, passed to the receiver unchanged.
    /// @param receiver The EVM receiver of the message and of the token.
    /// @param data The payload for `ccipReceive`.
    /// @param gasLimit The `ccipReceive` gas limit; 0 with empty `data` makes the message token-only.
    /// @param finality The requested finality (`FinalityCodec`); only applied on a 2.0 lane.
    /// @param sourcePoolAddress The Solana pool, informational (the lane has no pool registry).
    /// @param destToken The EVM token to release from the lane's escrow, `address(0)` when there is none.
    /// @param amount The amount in the source token's decimals.
    /// @param extraData `abi.encode(uint8 sourceDecimals)`, as written by a Solana BurnMint pool; empty means the local
    ///        decimals.
    struct SvmToEvmMessage {
        bytes32 messageId;
        uint64 sourceChainSelector;
        uint64 sequenceNumber;
        bytes sender;
        address receiver;
        bytes data;
        uint256 gasLimit;
        bytes4 finality;
        bytes sourcePoolAddress;
        address destToken;
        uint256 amount;
        bytes extraData;
    }

    /// @notice Emitted by `execute` for every attempt that reaches execution, like the OffRamp's
    ///         `ExecutionStateChanged`.
    /// @param success False when the token release or the receiver reverted; the message is then retryable.
    /// @param retData The revert data on failure (at most `Internal.MAX_RET_BYTES`), empty on success.
    event SvmMessageExecuted(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address indexed receiver,
        bool success,
        bytes retData
    );

    /// @dev Mirrors `OffRamp.SkippedAlreadyExecutedMessage` (2.0) / `SkippedAlreadyExecutedMessage` (1.6).
    error SkippedAlreadyExecutedMessage(bytes32 messageId);
    /// @dev The source chain of a message is not Solana.
    error InvalidSourceChainSelector(uint64 sourceChainSelector);
    /// @dev Mirrors `OffRamp.CanOnlySelfCall`.
    error CanOnlySelfCall();
    /// @dev Mirrors OffRamp 2.0 `NoStateProgressMade`: a retry of a failed message failed again.
    error NoStateProgressMade(bytes32 messageId, bytes err);
    /// @dev Mirrors OffRamp 1.6.0 `ExecutionError`: a manual execution of a failed message failed again.
    error ExecutionError(bytes32 messageId, bytes err);
    /// @dev Mirrors `OffRamp.ReceiverError`.
    error ReceiverError(bytes err);
    /// @dev The lane's escrow holds less of `token` than the message releases. Fund it by sending the token to the
    ///      lane (what an EVM -> Solana send does) or transferring it there in a test.
    error InsufficientEscrow(address token, uint256 held, uint256 needed);
    /// @dev Mirrors `TokenPool.InvalidRemoteChainDecimals`.
    error InvalidRemoteChainDecimals(bytes sourcePoolData);
    /// @dev Mirrors `TokenPool.OverflowDetected`.
    error OverflowDetected(uint8 remoteDecimals, uint8 localDecimals, uint256 remoteAmount);
    /// @dev Mirrors `OffRamp.InvalidOptionalThreshold`.
    error InvalidOptionalThreshold(uint8 wanted, uint256 got);

    /// @notice Delivers a Solana -> EVM message: releases the token from the escrow to the receiver and calls it
    ///         through the router, like the OffRamp. Anyone can call it; the offchain layer does.
    /// @dev A receiver or token failure does not revert: the state becomes FAILURE, `SvmMessageExecuted` carries the
    ///      revert data, and the whole attempt (token release included) is rolled back. A failed message can be
    ///      executed again; a succeeded one cannot.
    /// @return success Whether the message was delivered.
    /// @return retData The revert data of a failed attempt.
    function execute(SvmToEvmMessage calldata message) external returns (bool success, bytes memory retData);

    /// @notice The execution state of a message: UNTOUCHED, SUCCESS or FAILURE (IN_PROGRESS only during `execute`).
    function getExecutionState(bytes32 messageId) external view returns (Internal.MessageExecutionState);

    /// @notice Runs the checks a Solana-bound send goes through before the fee is collected, in production order.
    /// @dev `pure`, so the router calls it with STATICCALL. Reverts with the errors above; the router does not catch
    ///      them, so the revert data, including empty data for an undecodable body, reaches the sender unchanged.
    /// @param version The lane version to validate against.
    /// @param message The message passed to `ccipSend`.
    /// @return The decoded and validated `SVMExtraArgsV1`.
    function validate(SvmLaneVersion version, Client.EVM2AnyMessage calldata message)
        external
        pure
        returns (Client.SVMExtraArgsV1 memory);
}
