// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

/// @title ICCIPLocalSvmLane
/// @notice The Solana send rules of `CCIPLocalRouter`, kept in a separate contract so that EVM-only users do not pay
///         for them in the `CCIPLocalSimulator` initcode (EIP-3860 limit: 49,152 bytes).
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
    /// @dev Mirrors `OnRamp.UnsupportedToken` (2.0).
    error UnsupportedToken(address token);
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
