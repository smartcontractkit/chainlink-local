// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {ExtraArgsCodec} from "@chainlink/contracts-ccip/contracts/libraries/ExtraArgsCodec.sol";
import {Internal} from "@chainlink/contracts-ccip/contracts/libraries/Internal.sol";
import {Pool} from "@chainlink/contracts-ccip/contracts/libraries/Pool.sol";

import {ICCIPLocalSvmLane} from "./interfaces/ICCIPLocalSvmLane.sol";

/// @title CCIPLocalSvmLane
/// @notice Stateless Solana send rules for `CCIPLocalRouter`. Deploy it and register it to enable Solana-bound sends:
///         `router.setSvmLane(address(new CCIPLocalSvmLane()))`. It is separate from the router so that EVM-only users
///         do not carry its code in the `CCIPLocalSimulator` initcode.
/// @dev Applies the checks of a send on a CCIP 2.0 lane (Router 1.2 `ccipSend`, then OnRamp 2.0 `getFee`) or on a
///      CCIP 1.6 lane, with the same errors, so a message with several problems reports the same one it would on
///      Ethereum Sepolia -> Solana devnet (2.0) or Ethereum -> Solana mainnet (1.6). The router runs the checks that
///      need state (fee payment) or come after it.
contract CCIPLocalSvmLane is ICCIPLocalSvmLane {
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
        // No token pool for Solana exists locally, so every token is unregistered on this lane.
        if (message.tokenAmounts.length == 1) revert UnsupportedToken(message.tokenAmounts[0].token);
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
}
