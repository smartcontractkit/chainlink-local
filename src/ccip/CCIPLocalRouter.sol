// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/contracts/interfaces/IAny2EVMMessageReceiver.sol";
import {IAny2EVMMessageReceiverV2} from "@chainlink/contracts-ccip/contracts/interfaces/IAny2EVMMessageReceiverV2.sol";
import {IRouter} from "@chainlink/contracts-ccip/contracts/interfaces/IRouter.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {CCVConfigValidation} from "@chainlink/contracts-ccip/contracts/libraries/CCVConfigValidation.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {ExtraArgsCodec} from "@chainlink/contracts-ccip/contracts/libraries/ExtraArgsCodec.sol";
import {FinalityCodec} from "@chainlink/contracts-ccip/contracts/libraries/FinalityCodec.sol";
import {Internal} from "@chainlink/contracts-ccip/contracts/libraries/Internal.sol";
import {CallWithExactGas} from "@chainlink/contracts/src/v0.8/shared/call/CallWithExactGas.sol";

import {IERC20} from "@openzeppelin/contracts@5.3.0/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts@5.3.0/token/ERC20/utils/SafeERC20.sol";
import {ERC165Checker} from "@openzeppelin/contracts@5.3.0/utils/introspection/ERC165Checker.sol";

/// @title CCIPLocalRouter
/// @notice Local-mode router used by `CCIPLocalSimulator`. Mirrors `MockCCIPRouter` from `@chainlink/contracts-ccip`
///         2.0.0 (same ABI, events and behaviour) and additionally applies the CCIP 2.0 finality rules of the OnRamp and
///         OffRamp, so a test that passes locally does not fail on a fork or in production:
///         - the requested finality of `GenericExtraArgsV3` must use a single mode (OnRamp check at send time);
///         - a Faster-Than-Finality message that is not a token-only transfer is only delivered to a receiver whose
///           `getCCVsAndFinalityConfig` allows the requested finality (OffRamp check). Receivers without
///           `IAny2EVMMessageReceiverV2` accept finalized messages only.
/// @dev `MockCCIPRouter.ccipSend` is not virtual, and wrapping it would change `msg.sender`, hence the mirror.
contract CCIPLocalRouter is IRouter, IRouterClient {
    using SafeERC20 for IERC20;
    using ERC165Checker for address;

    error InvalidAddress(bytes encodedAddress);
    error InvalidExtraArgsTag();
    error ReceiverError(bytes err);
    /// @dev Mirrors `OnRamp.TokenReceiverNotAllowed`: `GenericExtraArgsV3.tokenReceiver` is rejected on all EVM lanes
    ///      (`DestChainConfig.tokenReceiverAllowed` is always false for EVM per its NatSpec).
    error TokenReceiverNotAllowed(uint64 destChainSelector);
    /// @dev Mirrors `FeeQuoter.MessageGasLimitTooHigh`.
    error MessageGasLimitTooHigh();
    /// @dev Mirrors `OnRamp.CanOnlySendOneTokenPerMessage`.
    error CanOnlySendOneTokenPerMessage();
    /// @dev Mirrors `OnRamp.CannotSendZeroTokens`.
    error CannotSendZeroTokens();
    /// @dev Mirrors `OffRamp.InvalidOptionalThreshold`.
    error InvalidOptionalThreshold(uint8 wanted, uint256 got);

    event MessageExecuted(bytes32 messageId, uint64 sourceChainSelector, address offRamp, bytes32 calldataHash);
    event MsgExecuted(bool success, bytes retData, uint256 gasUsed);

    uint16 public constant GAS_FOR_CALL_EXACT_CHECK = 5_000;
    uint32 public constant DEFAULT_GAS_LIMIT = 200_000;
    /// @dev Source chain selector stamped on local messages (Ethereum Sepolia), as in `MockCCIPRouter`.
    uint64 internal constant SOURCE_CHAIN_SELECTOR = 16015286601757825753;

    uint256 internal s_mockFeeTokenAmount; //use setFee() to change to non-zero to test fees
    /// @dev Nonce used to guarantee a unique messageId per send, see `ccipSend`.
    uint256 internal s_nonce;

    function routeMessage(
        Client.Any2EVMMessage calldata message,
        uint16 gasForCallExactCheck,
        uint256 gasLimit,
        address receiver
    ) external returns (bool success, bytes memory retData, uint256 gasUsed) {
        return _routeMessage(message, gasForCallExactCheck, gasLimit, receiver);
    }

    function _routeMessage(
        Client.Any2EVMMessage memory message,
        uint16 gasForCallExactCheck,
        uint256 gasLimit,
        address receiver
    ) internal returns (bool success, bytes memory retData, uint256 gasUsed) {
        if (_isTokenOnlyTransfer(message.data.length, gasLimit, receiver)) {
            return (true, "", 0);
        }

        bytes memory data = abi.encodeWithSelector(IAny2EVMMessageReceiver.ccipReceive.selector, message);

        (success, retData, gasUsed) = CallWithExactGas._callWithExactGasSafeReturnData(
            data, receiver, gasLimit, gasForCallExactCheck, Internal.MAX_RET_BYTES
        );

        // Event to assist testing, does not exist on real deployments
        emit MsgExecuted(success, retData, gasUsed);

        // Real router event
        emit MessageExecuted(message.messageId, message.sourceChainSelector, msg.sender, keccak256(data));
        return (success, retData, gasUsed);
    }

    /// @notice Sends the tx locally to the receiver instead of on the destination chain.
    /// @dev Ignores destinationChainSelector
    /// @dev Returns a mock message ID, which is not calculated from the message contents in the
    /// same way as the real message ID.
    function ccipSend(uint64 destinationChainSelector, Client.EVM2AnyMessage calldata message)
        external
        payable
        returns (bytes32)
    {
        if (message.receiver.length != 32) revert InvalidAddress(message.receiver);
        uint256 decodedReceiver = abi.decode(message.receiver, (uint256));
        // We want to disallow sending to address(0) and to precompiles, which exist on address(1) through address(9).
        if (decodedReceiver > type(uint160).max || decodedReceiver < 10) revert InvalidAddress(message.receiver);

        uint256 feeTokenAmount = getFee(destinationChainSelector, message);
        if (message.feeToken == address(0)) {
            if (msg.value < feeTokenAmount) revert InsufficientFeeTokenAmount();
        } else {
            if (msg.value > 0) revert InvalidMsgValue();
            IERC20(message.feeToken).safeTransferFrom(msg.sender, address(this), feeTokenAmount);
        }

        address receiver = address(uint160(decodedReceiver));
        (uint256 gasLimit, bytes4 requestedFinality) = _parseExtraArgs(destinationChainSelector, message.extraArgs);

        // Mirrors OnRamp 2.0: more than one token per message, or a zero-amount token, are rejected at send time.
        if (message.tokenAmounts.length > 1) revert CanOnlySendOneTokenPerMessage();
        if (message.tokenAmounts.length == 1 && message.tokenAmounts[0].amount == 0) revert CannotSendZeroTokens();

        // Unique per send: distinguishes otherwise-identical messages (same sender/receiver/data/dest) that would
        // otherwise collide on `keccak256(abi.encode(message))`.
        bytes32 mockMsgId = keccak256(abi.encode(++s_nonce, msg.sender, destinationChainSelector, message));

        Client.Any2EVMMessage memory executableMsg = Client.Any2EVMMessage({
            messageId: mockMsgId,
            sourceChainSelector: SOURCE_CHAIN_SELECTOR,
            sender: abi.encode(msg.sender),
            data: message.data,
            destTokenAmounts: message.tokenAmounts
        });

        _ensureReceiverAllowsFinality(receiver, executableMsg, gasLimit, requestedFinality);

        for (uint256 i = 0; i < message.tokenAmounts.length; ++i) {
            IERC20(message.tokenAmounts[i].token).safeTransferFrom(msg.sender, receiver, message.tokenAmounts[i].amount);
        }

        (bool success, bytes memory retData,) =
            _routeMessage(executableMsg, GAS_FOR_CALL_EXACT_CHECK, gasLimit, receiver);

        if (!success) revert ReceiverError(retData);

        return mockMsgId;
    }

    /// @dev Same token-only rule as OffRamp 2.0 `_isTokenOnlyTransfer`, which also decides whether the receiver is called.
    function _isTokenOnlyTransfer(uint256 dataLength, uint256 gasLimit, address receiver) internal view returns (bool) {
        return (dataLength == 0 && gasLimit == 0) || receiver.code.length == 0
            || !receiver.supportsInterface(type(IAny2EVMMessageReceiver).interfaceId);
    }

    /// @dev Mirrors OffRamp 2.0 `_getCCVsFromReceiver`, which is called for every message that is not a token-only
    ///      transfer regardless of requested finality (including fully finalized messages, not only Faster-Than-
    ///      Finality ones). Token-only transfers skip it entirely, as the pool enforces finality for them in
    ///      production (pools are not simulated in local mode).
    /// @dev Local mode has no CCV verifiers to query for quorum, so this only reproduces the validation and finality
    ///      parts of `_getCCVsFromReceiver`: duplicate required/optional CCVs and `optionalThreshold >
    ///      optionalCCVs.length` are rejected the same way, and the receiver's allowed finality is enforced.
    /// @dev If `getCCVsAndFinalityConfig` reverts, that revert is bubbled as-is (not wrapped in `ReceiverError`).
    ///      In production the OffRamp does not distinguish this from any other revert during message execution: it
    ///      simply records `ExecutionStateChanged(..., FAILURE, returnData)` with the getter's raw revert data.
    ///      `ReceiverError` is reserved for the narrower case of the receiver's own `ccipReceive` call failing (see
    ///      `_routeMessage`/`OffRamp._callReceiver`), so bubbling here (rather than wrapping) keeps that error
    ///      meaning precise while still failing the local send, consistent with this contract's "fails in
    ///      production" -> "ccipSend reverts locally" mapping.
    function _ensureReceiverAllowsFinality(
        address receiver,
        Client.Any2EVMMessage memory message,
        uint256 gasLimit,
        bytes4 requestedFinality
    ) internal view {
        if (_isTokenOnlyTransfer(message.data.length, gasLimit, receiver)) {
            return;
        }

        bytes4 allowedFinality = FinalityCodec.WAIT_FOR_FINALITY_FLAG;
        if (receiver.supportsInterface(type(IAny2EVMMessageReceiverV2).interfaceId)) {
            (
                address[] memory requiredCCVs,
                address[] memory optionalCCVs,
                uint8 optionalThreshold,
                bytes4 receiverFinality
            ) = IAny2EVMMessageReceiverV2(receiver)
                .getCCVsAndFinalityConfig(message.sourceChainSelector, message.sender);

            CCVConfigValidation._assertNoDuplicates(requiredCCVs);
            CCVConfigValidation._assertNoDuplicates(optionalCCVs);

            if (optionalThreshold > optionalCCVs.length) {
                revert InvalidOptionalThreshold(optionalThreshold, optionalCCVs.length);
            }

            allowedFinality = receiverFinality;
        }
        FinalityCodec._ensureRequestedFinalityAllowed(requestedFinality, allowedFinality);
    }

    /// @param destinationChainSelector Destination chain selector, used only for the `TokenReceiverNotAllowed` error.
    /// @return gasLimit Callback gas limit.
    /// @return requestedFinality `GenericExtraArgsV3.requestedFinalityConfig`, or WAIT_FOR_FINALITY for older tags.
    function _parseExtraArgs(uint64 destinationChainSelector, bytes calldata extraArgs)
        internal
        pure
        returns (uint256 gasLimit, bytes4 requestedFinality)
    {
        // Mirrors FeeQuoter._parseUnvalidatedEVMExtraArgsFromBytes/_parseSVMExtraArgsFromBytes etc.: extraArgs
        // shorter than 4 bytes (including empty) are treated as unset, not as an invalid tag.
        if (extraArgs.length < 4) {
            return (DEFAULT_GAS_LIMIT, FinalityCodec.WAIT_FOR_FINALITY_FLAG);
        }

        bytes4 extraArgsTag = bytes4(extraArgs);
        if (extraArgsTag == ExtraArgsCodec.GENERIC_EXTRA_ARGS_V3_TAG) {
            ExtraArgsCodec.GenericExtraArgsV3 memory decoded = ExtraArgsCodec._decodeGenericExtraArgsV3(extraArgs);
            // Mirrors OnRamp 2.0 `_parseExtraArgsWithDefaults`: tokenReceiver is rejected on all EVM lanes.
            if (decoded.tokenReceiver.length != 0) {
                revert TokenReceiverNotAllowed(destinationChainSelector);
            }
            // OnRamp 2.0 validates the wire shape of the requested finality at send time.
            FinalityCodec._validateRequestedFinality(decoded.requestedFinalityConfig);
            return (decoded.gasLimit, decoded.requestedFinalityConfig);
        } else if (extraArgsTag == Client.GENERIC_EXTRA_ARGS_V2_TAG) {
            return (
                _legacyGasLimit(abi.decode(extraArgs[4:], (Client.GenericExtraArgsV2)).gasLimit),
                FinalityCodec.WAIT_FOR_FINALITY_FLAG
            );
        } else if (extraArgsTag == Client.EVM_EXTRA_ARGS_V1_TAG) {
            return (_legacyGasLimit(abi.decode(extraArgs[4:], (uint256))), FinalityCodec.WAIT_FOR_FINALITY_FLAG);
        }

        revert InvalidExtraArgsTag();
    }

    /// @dev FeeQuoter compares the full uint256 V1/V2 gas limit against the lane's uint32 `maxPerMsgGasLimit` and reverts
    ///      `MessageGasLimitTooHigh`, so a value above uint32 is rejected everywhere; the upstream mock truncated it.
    ///      Local mode has no lane config, so lower lane caps are not enforced.
    function _legacyGasLimit(uint256 gasLimit) internal pure returns (uint256) {
        if (gasLimit > type(uint32).max) revert MessageGasLimitTooHigh();
        return gasLimit;
    }

    /// @notice Always returns true to make sure this check can be performed on any chain.
    function isChainSupported(uint64) external pure returns (bool supported) {
        return true;
    }

    /// @notice Returns an empty array.
    function getSupportedTokens(uint64) external pure returns (address[] memory tokens) {
        return new address[](0);
    }

    /// @notice Returns 0 as the fee is not supported in this mock contract.
    function getFee(uint64, Client.EVM2AnyMessage memory) public view returns (uint256) {
        return s_mockFeeTokenAmount;
    }

    /// @notice Sets the fees returned by getFee but is only checked when using native fee tokens
    function setFee(uint256 feeAmount) external {
        s_mockFeeTokenAmount = feeAmount;
    }

    /// @notice Always returns address(1234567890)
    function getOnRamp(
        uint64 /* destChainSelector */
    )
        external
        pure
        returns (address onRampAddress)
    {
        return address(1234567890);
    }

    /// @notice Always returns true
    function isOffRamp(
        uint64,
        /* sourceChainSelector */
        address /* offRamp */
    )
        external
        pure
        returns (bool)
    {
        return true;
    }
}
