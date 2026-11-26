// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/contracts/interfaces/IAny2EVMMessageReceiver.sol";
import {IAny2EVMMessageReceiverV2} from "@chainlink/contracts-ccip/contracts/interfaces/IAny2EVMMessageReceiverV2.sol";
import {IRouter} from "@chainlink/contracts-ccip/contracts/interfaces/IRouter.sol";
import {CCVConfigValidation} from "@chainlink/contracts-ccip/contracts/libraries/CCVConfigValidation.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {ExtraArgsCodec} from "@chainlink/contracts-ccip/contracts/libraries/ExtraArgsCodec.sol";
import {FinalityCodec} from "@chainlink/contracts-ccip/contracts/libraries/FinalityCodec.sol";
import {Internal} from "@chainlink/contracts-ccip/contracts/libraries/Internal.sol";
import {Pool} from "@chainlink/contracts-ccip/contracts/libraries/Pool.sol";

import {IERC20} from "@openzeppelin/contracts@5.3.0/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts@5.3.0/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts@5.3.0/token/ERC20/utils/SafeERC20.sol";
import {ERC165Checker} from "@openzeppelin/contracts@5.3.0/utils/introspection/ERC165Checker.sol";

import {ICCIPLocalRouterLaneVersion, ICCIPLocalSvmLane} from "./interfaces/ICCIPLocalSvmLane.sol";

/// @title CCIPLocalSvmLane
/// @notice The Solana side of `CCIPLocalRouter`: send rules, token escrow and Solana -> EVM delivery. Deploy it and
///         register it to enable Solana: `router.setSvmLane(address(new CCIPLocalSvmLane(address(router))))`. It is
///         separate from the router so that EVM-only users do not carry its code in the `CCIPLocalSimulator` initcode.
/// @dev `validate` is stateless (`pure`, reached by STATICCALL). The only state is the execution state of Solana ->
///      EVM messages and the token balances: tokens sent to Solana are escrowed here (the router moves them in) and
///      `execute` releases them, in place of the Solana pool and the EVM token pool of production.
/// @dev Applies the checks of a send on a CCIP 2.0 lane (Router 1.2 `ccipSend`, then OnRamp 2.0 `getFee`) or on a
///      CCIP 1.6 lane, with the same errors, so a message with several problems reports the same one it would on
///      Ethereum Sepolia -> Solana devnet (2.0) or Ethereum -> Solana mainnet (1.6). The router runs the checks that
///      need state (fee payment, token custody) or come after it. Exactly one token (any ERC20, no pool registry
///      locally) is accepted on both versions.
contract CCIPLocalSvmLane is ICCIPLocalSvmLane {
    using SafeERC20 for IERC20;
    using ERC165Checker for address;

    /// @notice CCIP chain selector of Solana (solana-devnet), the only accepted source of `execute`.
    uint64 public constant SOLANA_CHAIN_SELECTOR = 16423721717087811551;
    /// @dev Same as `CCIPLocalRouter.GAS_FOR_CALL_EXACT_CHECK`.
    uint16 internal constant GAS_FOR_CALL_EXACT_CHECK = 5_000;

    /// @notice The `CCIPLocalRouter` that registered this lane; it applies the token-only rule and calls receivers.
    address public immutable ROUTER;

    mapping(bytes32 messageId => Internal.MessageExecutionState state) internal s_executionStates;

    constructor(address router) {
        ROUTER = router;
    }

    /// @notice Compute unit limit of the Ethereum Sepolia -> Solana devnet lane (`FeeQuoter 2.0.0`
    ///         `DestChainConfig.maxPerMsgGasLimit`, read on 18 Nov 2026).
    uint32 public constant SVM_MAX_COMPUTE_UNITS = 3_000_000;
    /// @notice Payload limit of the same lane (`DestChainConfig.maxDataBytes`). Production compares it against the
    ///         payload plus verifier and executor overhead; local mode checks the payload alone, a lower bound.
    uint32 public constant SVM_MAX_DATA_BYTES = 30_000;

    /// @dev Limits of the CCIP 1.6 Ethereum -> Solana mainnet lane (`FeeQuoter 2.0.0` `DestChainConfig`, read at
    ///      Ethereum block 26449551). FeeQuoter 2.0.0 hard-codes one token per message.
    uint32 internal constant SVM_MAX_COMPUTE_UNITS_V1_6 = 1_400_000;
    uint32 internal constant SVM_MAX_DATA_BYTES_V1_6 = 1_280;
    uint256 internal constant SVM_MAX_TOKENS_PER_MSG_V1_6 = 1;

    /// @inheritdoc ICCIPLocalSvmLane
    function validate(SvmLaneVersion version, Client.EVM2AnyMessage calldata message)
        external
        pure
        returns (Client.SVMExtraArgsV1 memory)
    {
        if (version == SvmLaneVersion.V1_6) return _validateV1_6(message);
        return _validateV2_0(message);
    }

    /// @dev CCIP 2.0 order: OnRamp.getFee checks, up to the payload limit.
    function _validateV2_0(Client.EVM2AnyMessage calldata message)
        internal
        pure
        returns (Client.SVMExtraArgsV1 memory svmExtraArgs)
    {
        if (message.tokenAmounts.length > 1) revert CanOnlySendOneTokenPerMessage();
        svmExtraArgs = _parseSvmExtraArgs(message.extraArgs, SVM_MAX_COMPUTE_UNITS);
        // FeeQuoter.resolveLegacyArgs re-encodes the accounts with a one-byte length.
        if (svmExtraArgs.accounts.length > type(uint8).max) {
            revert ExtraArgsCodec.InvalidDataLength(ExtraArgsCodec.EncodingErrorLocation.ENCODE_SVM_ACCOUNTS_LENGTH, 0);
        }
        // A token needs no check here: the Sepolia -> Solana devnet OnRamp allows `tokenReceiver` (read 20 Nov 2026,
        // `DestChainConfig.tokenReceiverAllowed` is true), and OnRamp 2.0 does not reject a zero one. There is no pool
        // registry locally, so every ERC20 counts as registered; a zero amount is rejected by the router after the fee.
        if (message.data.length > SVM_MAX_DATA_BYTES) revert MessageTooLarge(SVM_MAX_DATA_BYTES, message.data.length);
    }

    /// @dev Mirrors FeeQuoter 2.0.0 `_validateMessageAndResolveGasLimitForDestination` for an SVM destination
    ///      (FeeQuoter.sol:767-900), check for check and in the same order. The send order on a CCIP 1.6 lane is
    ///      (Router 1.2.0 and OnRamp 1.6.0 from contracts-ccip-v1.6.0, commit e9476e99; FeeQuoter 2.0.0 from
    ///      lib/chainlink-ccip, as the mainnet OnRamp 1.6.0 uses it):
    ///      1. Router.ccipSend (Router.sol:134): fee-token payment with native value, `InvalidMsgValue` (router).
    ///      2. OnRamp.getFee -> FeeQuoter.getValidatedFee (FeeQuoter.sol:692) -> this function
    ///         (_validateMessageAndResolveGasLimitForDestination, FeeQuoter.sol:761, SVM branch from 848).
    ///      3. Router.ccipSend (Router.sol:127): native fee payment, `InsufficientFeeTokenAmount` (router).
    ///      4. OnRamp.forwardFromRouter (OnRamp.sol:161) -> `_lockOrBurnSingleToken` (OnRamp.sol:279): the token
    ///         checks (router).
    ///      FeeQuoter 2.0.0 always treats messages as out-of-order, so there is no out-of-order check. The lane limits
    ///      are constants, as local mode has no lane config.
    function _validateV1_6(Client.EVM2AnyMessage calldata message)
        internal
        pure
        returns (Client.SVMExtraArgsV1 memory svmExtraArgs)
    {
        uint256 dataLength = message.data.length;
        uint256 numberOfTokens = message.tokenAmounts.length;

        // FeeQuoter.sol:770-775.
        if (dataLength > SVM_MAX_DATA_BYTES_V1_6) revert MessageTooLarge(SVM_MAX_DATA_BYTES_V1_6, dataLength);
        if (numberOfTokens > SVM_MAX_TOKENS_PER_MSG_V1_6) {
            revert UnsupportedNumberOfTokens(numberOfTokens, SVM_MAX_TOKENS_PER_MSG_V1_6);
        }

        // FeeQuoter.sol:850, _parseSVMExtraArgsFromBytes (442-461).
        svmExtraArgs = _parseSvmExtraArgs(message.extraArgs, SVM_MAX_COMPUTE_UNITS_V1_6);

        // _validateDestFamilyAddress: 32 bytes, non-zero when compute units are set.
        if (message.receiver.length != 32 || (svmExtraArgs.computeUnits > 0 && bytes32(message.receiver) == bytes32(0)))
        {
            revert Internal.Invalid32ByteAddress(message.receiver);
        }

        // FeeQuoter.sol:856-884.
        uint256 accountsLength = svmExtraArgs.accounts.length;
        uint256 svmExpandedDataLength = dataLength;
        if (bytes32(message.receiver) == bytes32(0)) {
            // The CCIP receiver is not invoked on SVM for a zero receiver, so it takes no accounts.
            if (accountsLength > 0) revert TooManySVMExtraArgsAccounts(accountsLength, 0);
        } else {
            svmExpandedDataLength += (accountsLength + Client.SVM_MESSAGING_ACCOUNTS_OVERHEAD)
                * Client.SVM_ACCOUNT_BYTE_SIZE;
        }
        if (numberOfTokens > 0 && svmExtraArgs.tokenReceiver == bytes32(0)) revert InvalidTokenReceiver();
        if (accountsLength > Client.SVM_EXTRA_ARGS_MAX_ACCOUNTS) {
            revert TooManySVMExtraArgsAccounts(accountsLength, Client.SVM_EXTRA_ARGS_MAX_ACCOUNTS);
        }
        if (svmExtraArgs.accountIsWritableBitmap >> accountsLength != 0) {
            revert InvalidSVMExtraArgsWritableBitmap(svmExtraArgs.accountIsWritableBitmap, accountsLength);
        }

        // No per-token `destBytesOverhead` override exists locally, so the pool default applies.
        svmExpandedDataLength += numberOfTokens
            * (Client.SVM_TOKEN_TRANSFER_DATA_OVERHEAD + Pool.CCIP_LOCK_OR_BURN_V1_RET_BYTES);
        if (svmExpandedDataLength > SVM_MAX_DATA_BYTES_V1_6) {
            revert MessageTooLarge(SVM_MAX_DATA_BYTES_V1_6, svmExpandedDataLength);
        }
    }

    /// @dev Mirrors `FeeQuoter._parseSVMExtraArgsFromBytes` (2.0.0), which both lane versions use. An undecodable body
    ///      reverts with empty data, as in production. The 2.0 lane has no account-count (beyond 255), writable-bitmap
    ///      or zero-receiver check at send time; those fail on Solana.
    function _parseSvmExtraArgs(bytes calldata extraArgs, uint256 maxComputeUnits)
        internal
        pure
        returns (Client.SVMExtraArgsV1 memory)
    {
        if (extraArgs.length < 4) revert InvalidExtraArgsData();
        if (bytes4(extraArgs) != Client.SVM_EXTRA_ARGS_V1_TAG) revert InvalidExtraArgsTag();

        Client.SVMExtraArgsV1 memory svmExtraArgs = abi.decode(extraArgs[4:], (Client.SVMExtraArgsV1));
        if (svmExtraArgs.computeUnits > maxComputeUnits) revert MessageComputeUnitLimitTooHigh();
        return svmExtraArgs;
    }

    // ================================================================
    // │                  Solana -> EVM delivery                      │
    // ================================================================

    /// @inheritdoc ICCIPLocalSvmLane
    /// @dev Mirrors OffRamp 2.0 `execute` (OffRamp.sol:188-262) and 1.6.0 `executeSingleMessage` + `_trialExecute`: the
    ///      state check allows UNTOUCHED and FAILURE only (:230-240, so IN_PROGRESS also blocks reentrancy on the same
    ///      message), the attempt runs in a self-call so a revert undoes the token release too (:308, `CanOnlySelfCall`),
    ///      and the outcome is recorded (:255-260). A first failure is recorded and returned, not reverted; a retry of a
    ///      FAILURE message that fails again reverts, as both OffRamps do: `NoStateProgressMade` on 2.0 (:248-252),
    ///      `ExecutionError` on 1.6.0 (manual execution, OffRamp.sol:509-515). Difference: no commit/verifier or RMN
    ///      checks (nothing to verify locally).
    function execute(SvmToEvmMessage calldata message) external returns (bool success, bytes memory retData) {
        if (message.sourceChainSelector != SOLANA_CHAIN_SELECTOR) {
            revert InvalidSourceChainSelector(message.sourceChainSelector);
        }
        Internal.MessageExecutionState originalState = s_executionStates[message.messageId];
        if (
            originalState != Internal.MessageExecutionState.UNTOUCHED
                && originalState != Internal.MessageExecutionState.FAILURE
        ) revert SkippedAlreadyExecutedMessage(message.messageId);

        s_executionStates[message.messageId] = Internal.MessageExecutionState.IN_PROGRESS;

        try this.executeSingleMessage(message) {
            success = true;
        } catch (bytes memory err) {
            retData = err;
            // OffRamp._callWithGasBuffer keeps at most MAX_RET_BYTES of the revert data.
            if (retData.length > Internal.MAX_RET_BYTES) {
                uint256 maxRetBytes = Internal.MAX_RET_BYTES;
                assembly ("memory-safe") {
                    mstore(retData, maxRetBytes)
                }
            }
        }

        // No progress on a retry: revert, which also keeps the state at FAILURE.
        if (!success && originalState == Internal.MessageExecutionState.FAILURE) {
            if (ICCIPLocalRouterLaneVersion(ROUTER).getSvmLaneVersion() == uint8(SvmLaneVersion.V1_6)) {
                revert ExecutionError(message.messageId, retData);
            }
            revert NoStateProgressMade(message.messageId, retData);
        }

        s_executionStates[message.messageId] =
            success ? Internal.MessageExecutionState.SUCCESS : Internal.MessageExecutionState.FAILURE;
        emit SvmMessageExecuted(message.messageId, message.sourceChainSelector, message.receiver, success, retData);
    }

    /// @inheritdoc ICCIPLocalSvmLane
    function getExecutionState(bytes32 messageId) external view returns (Internal.MessageExecutionState) {
        return s_executionStates[messageId];
    }

    /// @notice One delivery attempt. External only so that `execute` can try/catch it; reverts for any other caller.
    /// @dev Mirrors OffRamp 2.0 `executeSingleMessage` (OffRamp.sol:308-390), in its order: receiver finality rule
    ///      (the CCV quorum step, :339-342), token release (:362), then the receiver call through the router (:381,
    ///      `_callReceiver` :393 reverts with `ReceiverError` when the router reports failure).
    function executeSingleMessage(SvmToEvmMessage calldata message) external {
        if (msg.sender != address(this)) revert CanOnlySelfCall();

        bool isTokenOnlyTransfer = _isTokenOnlyTransfer(message.data.length, message.gasLimit, message.receiver);
        bool isV2_0 = ICCIPLocalRouterLaneVersion(ROUTER).getSvmLaneVersion() == uint8(SvmLaneVersion.V2_0);
        // 1.6 has no finality: the requested finality is ignored.
        if (isV2_0) _ensureReceiverAllowsFinality(message, isTokenOnlyTransfer);

        Client.EVMTokenAmount[] memory destTokenAmounts;
        if (message.destToken == address(0)) {
            destTokenAmounts = new Client.EVMTokenAmount[](0);
        } else {
            destTokenAmounts = new Client.EVMTokenAmount[](1);
            destTokenAmounts[0] = _releaseToken(message);
        }

        // The router applies the token-only rule itself and returns success without calling the receiver.
        (bool success, bytes memory retData,) = IRouter(ROUTER)
            .routeMessage(
                Client.Any2EVMMessage({
                    messageId: message.messageId,
                    sourceChainSelector: message.sourceChainSelector,
                    sender: message.sender,
                    data: message.data,
                    destTokenAmounts: destTokenAmounts
                }),
                GAS_FOR_CALL_EXACT_CHECK,
                message.gasLimit,
                message.receiver
            );
        if (!success) revert ReceiverError(retData);
    }

    /// @dev Stands in for `OffRamp._releaseOrMintSingleToken` and the pool's `releaseOrMint`: converts the amount like
    ///      `TokenPool._calculateLocalAmount` and pays it to the receiver from the escrow. There is no pool registry,
    ///      so any ERC20 the lane holds can be released.
    function _releaseToken(SvmToEvmMessage calldata message) internal returns (Client.EVMTokenAmount memory) {
        uint8 localDecimals = IERC20Metadata(message.destToken).decimals();
        uint256 localAmount = _calculateLocalAmount(
            message.amount, _parseRemoteDecimals(message.extraData, localDecimals), localDecimals
        );

        uint256 held = IERC20(message.destToken).balanceOf(address(this));
        if (held < localAmount) revert InsufficientEscrow(message.destToken, held, localAmount);
        IERC20(message.destToken).safeTransfer(message.receiver, localAmount);
        return Client.EVMTokenAmount({token: message.destToken, amount: localAmount});
    }

    /// @dev `TokenPool._parseRemoteDecimals` (TokenPool.sol:529-543).
    function _parseRemoteDecimals(bytes calldata sourcePoolData, uint8 localDecimals) internal pure returns (uint8) {
        if (sourcePoolData.length == 0) return localDecimals;
        if (sourcePoolData.length != 32) revert InvalidRemoteChainDecimals(sourcePoolData);
        uint256 remoteDecimals = abi.decode(sourcePoolData, (uint256));
        if (remoteDecimals > type(uint8).max) revert InvalidRemoteChainDecimals(sourcePoolData);
        return uint8(remoteDecimals);
    }

    /// @dev `TokenPool._calculateLocalAmount` (TokenPool.sol:552-580), including its overflow checks.
    function _calculateLocalAmount(uint256 remoteAmount, uint8 remoteDecimals, uint8 localDecimals)
        internal
        pure
        returns (uint256)
    {
        if (remoteDecimals == localDecimals) return remoteAmount;
        if (remoteDecimals > localDecimals) {
            uint8 decimalsDiff = remoteDecimals - localDecimals;
            if (decimalsDiff > 77) revert OverflowDetected(remoteDecimals, localDecimals, remoteAmount);
            // Rounds down, so the receiver never gets more than Solana burned.
            return remoteAmount / (10 ** decimalsDiff);
        }
        uint8 diffDecimals = localDecimals - remoteDecimals;
        if (diffDecimals > 77 || remoteAmount > type(uint256).max / (10 ** diffDecimals)) {
            revert OverflowDetected(remoteDecimals, localDecimals, remoteAmount);
        }
        return remoteAmount * (10 ** diffDecimals);
    }

    /// @dev Same token-only rule as OffRamp 2.0 `_isTokenOnlyTransfer` (OffRamp.sol:421) and `CCIPLocalRouter`.
    function _isTokenOnlyTransfer(uint256 dataLength, uint256 gasLimit, address receiver) internal view returns (bool) {
        return (dataLength == 0 && gasLimit == 0) || receiver.code.length == 0
            || !receiver.supportsInterface(type(IAny2EVMMessageReceiver).interfaceId);
    }

    /// @dev The same rule `CCIPLocalRouter._ensureReceiverAllowsFinality` applies to EVM receives, i.e. OffRamp 2.0
    ///      `_getCCVsFromReceiver` (OffRamp.sol:695): skipped for token-only transfers; a receiver without
    ///      `IAny2EVMMessageReceiverV2` accepts finalized messages only; otherwise its CCV config is validated and its
    ///      allowed finality must cover the requested one. Kept in sync by hand (the router's is internal and its
    ///      size budget does not allow exposing it).
    function _ensureReceiverAllowsFinality(SvmToEvmMessage calldata message, bool isTokenOnlyTransfer) internal view {
        if (isTokenOnlyTransfer) return;

        bytes4 allowedFinality = FinalityCodec.WAIT_FOR_FINALITY_FLAG;
        if (message.receiver.supportsInterface(type(IAny2EVMMessageReceiverV2).interfaceId)) {
            (
                address[] memory requiredCCVs,
                address[] memory optionalCCVs,
                uint8 optionalThreshold,
                bytes4 receiverFinality
            ) = IAny2EVMMessageReceiverV2(message.receiver)
                .getCCVsAndFinalityConfig(message.sourceChainSelector, message.sender);

            CCVConfigValidation._assertNoDuplicates(requiredCCVs);
            CCVConfigValidation._assertNoDuplicates(optionalCCVs);

            if (optionalThreshold > optionalCCVs.length) {
                revert InvalidOptionalThreshold(optionalThreshold, optionalCCVs.length);
            }
            allowedFinality = receiverFinality;
        }
        FinalityCodec._ensureRequestedFinalityAllowed(message.finality, allowedFinality);
    }
}
