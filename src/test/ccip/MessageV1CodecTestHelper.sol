// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MessageV1Codec} from "@chainlink/contracts-ccip/contracts/libraries/MessageV1Codec.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
/// @notice Test-only wrapper that exposes the pinned `MessageV1Codec._encodeMessageV1` (an internal library function)
/// as an external call, so the JavaScript helper's offline tests can build a real MessageV1 wire-format
/// `encodedMessage` (matching exactly what a real CCIP 2.0 OnRamp emits) without re-implementing the codec by hand.
contract MessageV1CodecTestHelper {
    function encodeMessageV1(MessageV1Codec.MessageV1 memory message) external pure returns (bytes memory) {
        return MessageV1Codec._encodeMessageV1(message);
    }
}
