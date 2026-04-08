// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {ExtraArgsCodec} from "@chainlink/contracts-ccip/contracts/libraries/ExtraArgsCodec.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */

/// @title EncodeExtraArgsOffchain
/// @notice This contract is not intended to be deployed on-chain, it is simply a helper contract to encode the extraArgs.
///
/// The purpose of extraArgs is to allow compatibility with future CCIP upgrades.
/// To get this benefit, make sure that extraArgs is mutable in production deployments.
/// This allows you to build it offchain and pass it in a call to a function or store it in a variable that you can update on-demand.
/// Read more here: https://docs.chain.link/ccip/best-practices#using-extraargs
contract EncodeExtraArgsOffchain {
    // Below is a simplistic example (same params for all messages) of using storage to allow for new options without
    // upgrading the dapp. Note that extra args are chain family specific (e.g. gasLimit is EVM specific etc.).
    // and will always be backwards compatible i.e. upgrades are opt-in.
    // Offchain we can compute the V1 extraArgs:
    //    Client.EVMExtraArgsV1 memory extraArgs = Client.EVMExtraArgsV1({gasLimit: 300_000});
    //    bytes memory encodedV1ExtraArgs = Client._argsToBytes(extraArgs);
    // Then later compute V2 extraArgs, for example when allowOutOfOrderExecution was added:
    //    Client.GenericExtraArgsV2 memory extraArgs = Client.GenericExtraArgsV2({gasLimit: 300_000, allowOutOfOrderExecution: true});
    //    bytes memory encodedV2ExtraArgs = Client._argsToBytes(extraArgs);
    // and update storage with the new args.
    // If different options are required for different messages, for example different gas limits,
    // one can simply key based on (chainSelector, messageType) instead of only chainSelector.

    function encodeV1(uint256 gasLimit) public pure returns (bytes memory extraArgsBytes) {
        Client.EVMExtraArgsV1 memory extraArgs = Client.EVMExtraArgsV1({gasLimit: gasLimit});
        extraArgsBytes = Client._argsToBytes(extraArgs);
    }

    function encodeV2(uint256 gasLimit, bool allowOutOfOrderExecution)
        public
        pure
        returns (bytes memory extraArgsBytes)
    {
        Client.GenericExtraArgsV2 memory extraArgs = Client.GenericExtraArgsV2({
            gasLimit: gasLimit, allowOutOfOrderExecution: allowOutOfOrderExecution
        });
        extraArgsBytes = Client._argsToBytes(extraArgs);
    }

    /**
     * @param gasLimit Gas limit allocated for the callback on the destination chain. If `0` **and** the message data length
     *                 is `0`, no callback is executed (useful for token-only transfers or EOA receivers).
     *                 **Note:** The sender is billed for the *specified* gas limit, not actual usage. Unused gas is **not** refunded.
     *                 Estimate gas requirements carefully, as they vary by chain family (refer to chain-specific documentation).
     * @param blockConfirmations Number of block confirmations to wait before execution. `0` uses the default finality
     *                            defined by the CCV. Non-zero values may be rejected by CCVs/Pools/executor if considered too risky.
     * @param ccvs Array of cross-chain verifier (CCV) addresses. If empty, default verifiers are used.
     * @param ccvArgs Optional, uninterpreted arguments for each CCV in `ccvs`. Must match the length of `ccvs`.
     *                 **Format:** Chain/CCV-specific (e.g., encoded structs or raw bytes).
     * @param executor Address of the executor contract on the **source chain**. If `address(0)`, the default executor is used.
     *                 The executor handles message execution on the destination chain after CCV verification.
     * @param executorArgs Chain-family-specific arguments for the executor (e.g., Solana accounts, Sui object IDs).
     *                      **Security:** Incorrect values may cause fund loss. Format is executor/chain-dependent.
     * @param tokenReceiver Destination token receiver address in bytes. If empty, the message receiver address is used.
     *                      **Behavior:**
     *                      - If token transfer exists: Falls back to message receiver.
     *                      - If no token transfer: Must be empty.
     * @param tokenArgs Additional token transfer arguments (e.g., pool-specific metadata). Format depends on the token pool.
     * @return extraArgsBytes Encoded ExtraArgsV3
     */
    function encodeV3(
        uint32 gasLimit,
        uint16 blockConfirmations,
        address[] memory ccvs,
        bytes[] memory ccvArgs,
        address executor,
        bytes memory executorArgs,
        bytes memory tokenReceiver,
        bytes memory tokenArgs
    ) public pure returns (bytes memory extraArgsBytes) {
        ExtraArgsCodec.GenericExtraArgsV3 memory extraArgs = ExtraArgsCodec.GenericExtraArgsV3({
            gasLimit: gasLimit,
            blockConfirmations: blockConfirmations,
            ccvs: ccvs,
            ccvArgs: ccvArgs,
            executor: executor,
            executorArgs: executorArgs,
            tokenReceiver: tokenReceiver,
            tokenArgs: tokenArgs
        });

        extraArgsBytes = ExtraArgsCodec._encodeGenericExtraArgsV3(extraArgs);
    }

    /// @notice Creates a basic encoded GenericExtraArgsV3 with only gasLimit and blockConfirmations set.
    function encodeV3Basic(uint32 gasLimit, uint16 blockConfirmations)
        public
        pure
        returns (bytes memory extraArgsBytes)
    {
        extraArgsBytes = ExtraArgsCodec._getBasicEncodedExtraArgsV3(gasLimit, blockConfirmations);
    }

    /// @notice Get the NO_EXECUTION_ADDRESS for manual execution.
    /// @return The address that signals no automatic execution.
    function getNoExecutionAddress() public pure returns (address) {
        return Client.NO_EXECUTION_ADDRESS;
    }
}
