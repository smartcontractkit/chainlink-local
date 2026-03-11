// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {MessageV1Codec} from "@chainlink/contracts-ccip/contracts/libraries/MessageV1Codec.sol";
import {CCIPForkAdapterTypes} from "./CCIPForkAdapterTypes.sol";

interface IMessageV1Decoder {
    function decodeMessageV1(bytes calldata encodedMessage)
        external
        view
        returns (MessageV1Codec.MessageV1 memory message);
}

interface IOffRampExecuteV2 {
    function getCCVsForMessage(bytes calldata encodedMessage)
        external
        view
        returns (address[] memory requiredCCVs, address[] memory optionalCCVs, uint8 threshold);

    function executeSingleMessage(
        MessageV1Codec.MessageV1 calldata message,
        bytes32 messageId,
        address[] calldata ccvs,
        bytes[] calldata verifierResults,
        uint32 gasLimitOverride
    ) external;
}

library CCIPForkAdapterV2 {
    error MissingMessageIdTopic();
    error InvalidAddressEncoding(bytes encodedAddress);
    error MissingVerifierBlobForCCV(address ccv);
    error InvalidVerifierReceiptCount(uint256 receiptsLength, uint256 verifierBlobLength);

    struct DecodedMessage {
        bytes32 messageId;
        bytes encodedMessage;
        CCIPForkAdapterTypes.V2Receipt[] receipts;
        bytes[] verifierBlobs;
        MessageV1Codec.MessageV1 message;
    }

    event CCIPMessageSent(
        uint64 indexed destChainSelector,
        address indexed sender,
        bytes32 indexed messageId,
        address feeToken,
        uint256 tokenAmountBeforeTokenPoolFees,
        bytes encodedMessage,
        CCIPForkAdapterTypes.V2Receipt[] receipts,
        bytes[] verifierBlobs
    );

    function eventSelector() internal pure returns (bytes32) {
        return CCIPMessageSent.selector;
    }

    function decodeMessage(bytes32[] memory topics, bytes memory eventData, IMessageV1Decoder decoder)
        internal
        view
        returns (DecodedMessage memory decodedMessage)
    {
        if (topics.length < 4) {
            revert MissingMessageIdTopic();
        }

        decodedMessage.messageId = topics[3];

        (,, decodedMessage.encodedMessage, decodedMessage.receipts, decodedMessage.verifierBlobs) =
            abi.decode(eventData, (address, uint256, bytes, CCIPForkAdapterTypes.V2Receipt[], bytes[]));
        decodedMessage.message = decoder.decodeMessageV1(decodedMessage.encodedMessage);
    }

    function extractOffRampAddress(DecodedMessage memory decodedMessage) internal pure returns (address offRampAddress) {
        return _decodeEVMAddress(decodedMessage.message.offRampAddress);
    }

    function deriveVerificationInputs(address offRamp, DecodedMessage memory decodedMessage)
        internal
        view
        returns (address[] memory ccvs, bytes[] memory verifierResults)
    {
        (address[] memory requiredCCVs, address[] memory optionalCCVs, uint8 threshold) =
            IOffRampExecuteV2(offRamp).getCCVsForMessage(decodedMessage.encodedMessage);

        uint256 totalAvailable = requiredCCVs.length + optionalCCVs.length;
        uint256 targetLength = requiredCCVs.length;

        if (targetLength < threshold) {
            targetLength = threshold;
        }
        if (targetLength > totalAvailable) {
            targetLength = totalAvailable;
        }

        ccvs = new address[](targetLength);
        verifierResults = _resolveVerifierResults(decodedMessage, targetLength);

        uint256 ccvCount;
        for (uint256 i = 0; i < requiredCCVs.length && ccvCount < targetLength; ++i) {
            ccvs[ccvCount++] = requiredCCVs[i];
        }
        for (uint256 i = 0; i < optionalCCVs.length && ccvCount < targetLength; ++i) {
            ccvs[ccvCount++] = optionalCCVs[i];
        }

        for (uint256 i = 0; i < targetLength; ++i) {
            verifierResults[i] = _findVerifierResultForCCV(decodedMessage, ccvs[i]);
        }
    }

    function execute(
        address offRamp,
        MessageV1Codec.MessageV1 memory message,
        bytes32 messageId,
        address[] memory ccvs,
        bytes[] memory verifierResults
    ) internal returns (bool success, bytes memory returnData) {
        bytes memory callData = abi.encodeWithSelector(
            IOffRampExecuteV2.executeSingleMessage.selector, message, messageId, ccvs, verifierResults, uint32(0)
        );
        (success, returnData) = offRamp.call(callData);
    }

    function _decodeEVMAddress(bytes memory encodedAddress) private pure returns (address decodedAddress) {
        if (encodedAddress.length == 32) {
            return abi.decode(encodedAddress, (address));
        }

        if (encodedAddress.length == 20) {
            assembly {
                decodedAddress := shr(96, mload(add(encodedAddress, 0x20)))
            }
            return decodedAddress;
        }

        revert InvalidAddressEncoding(encodedAddress);
    }

    function _resolveVerifierResults(DecodedMessage memory decodedMessage, uint256 targetLength)
        private
        pure
        returns (bytes[] memory verifierResults)
    {
        uint256 verifierBlobLength = decodedMessage.verifierBlobs.length;
        if (decodedMessage.receipts.length < verifierBlobLength) {
            revert InvalidVerifierReceiptCount(decodedMessage.receipts.length, verifierBlobLength);
        }

        verifierResults = new bytes[](targetLength);
    }

    function _findVerifierResultForCCV(DecodedMessage memory decodedMessage, address ccv)
        private
        pure
        returns (bytes memory verifierResult)
    {
        uint256 verifierBlobLength = decodedMessage.verifierBlobs.length;
        for (uint256 i = 0; i < verifierBlobLength; ++i) {
            if (decodedMessage.receipts[i].issuer == ccv) {
                return decodedMessage.verifierBlobs[i];
            }
        }

        revert MissingVerifierBlobForCCV(ccv);
    }
}
