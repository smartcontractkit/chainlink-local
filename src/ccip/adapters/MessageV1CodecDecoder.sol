// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {MessageV1Codec} from "@chainlink/contracts-ccip/contracts/libraries/MessageV1Codec.sol";

contract MessageV1CodecDecoder {
    function decodeMessageV1(bytes calldata encodedMessage)
        external
        pure
        returns (MessageV1Codec.MessageV1 memory message)
    {
        return MessageV1Codec._decodeMessageV1(encodedMessage);
    }
}
