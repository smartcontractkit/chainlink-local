// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {CCIPForkAdapterTypes} from "./CCIPForkAdapterTypes.sol";

interface IOffRampExecuteV1dot6 {
    function executeSingleMessage(
        CCIPForkAdapterTypes.V1dot6Any2EVMRampMessage memory message,
        bytes[] calldata offchainTokenData,
        uint32[] calldata tokenGasOverrides
    ) external;
}

library CCIPForkAdapterV1dot6 {
    error InvalidExtraArgsTag(bytes4 extraArgsTag);
    error InvalidAddressEncoding(bytes encodedAddress);

    uint32 internal constant DEFAULT_GAS_LIMIT = 200_000;

    event CCIPMessageSent(
        uint64 indexed destChainSelector,
        uint64 indexed sequenceNumber,
        CCIPForkAdapterTypes.V1dot6EVM2AnyRampMessage message
    );

    function eventSelector() internal pure returns (bytes32) {
        return CCIPMessageSent.selector;
    }

    function decodeMessage(bytes memory eventData)
        internal
        pure
        returns (CCIPForkAdapterTypes.V1dot6EVM2AnyRampMessage memory message)
    {
        return abi.decode(eventData, (CCIPForkAdapterTypes.V1dot6EVM2AnyRampMessage));
    }

    function execute(CCIPForkAdapterTypes.V1dot6EVM2AnyRampMessage memory message, address offRamp)
        internal
        returns (bool success, bytes memory returnData)
    {
        uint256 gasLimit = _decodeGasLimit(message.extraArgs);
        CCIPForkAdapterTypes.V1dot6Any2EVMRampMessage memory any2EVMMessage = _toAny2EVMMessage(message, gasLimit);

        uint256 numberOfTokens = message.tokenAmounts.length;
        bytes[] memory offchainTokenData = new bytes[](numberOfTokens);
        uint32[] memory tokenGasOverrides = new uint32[](numberOfTokens);

        for (uint256 i = 0; i < numberOfTokens; ++i) {
            tokenGasOverrides[i] = uint32(gasLimit);
        }

        bytes memory callData = abi.encodeWithSelector(
            IOffRampExecuteV1dot6.executeSingleMessage.selector, any2EVMMessage, offchainTokenData, tokenGasOverrides
        );
        (success, returnData) = offRamp.call(callData);
    }

    function _toAny2EVMMessage(CCIPForkAdapterTypes.V1dot6EVM2AnyRampMessage memory message, uint256 gasLimit)
        internal
        pure
        returns (CCIPForkAdapterTypes.V1dot6Any2EVMRampMessage memory any2EVMMessage)
    {
        uint256 numberOfTokens = message.tokenAmounts.length;
        CCIPForkAdapterTypes.V1dot6Any2EVMTokenTransfer[] memory tokenAmounts =
            new CCIPForkAdapterTypes.V1dot6Any2EVMTokenTransfer[](numberOfTokens);

        for (uint256 i = 0; i < numberOfTokens; ++i) {
            tokenAmounts[i] = CCIPForkAdapterTypes.V1dot6Any2EVMTokenTransfer({
                sourcePoolAddress: abi.encodePacked(message.tokenAmounts[i].sourcePoolAddress),
                destTokenAddress: _decodeEVMAddress(message.tokenAmounts[i].destTokenAddress),
                destGasAmount: abi.decode(message.tokenAmounts[i].destExecData, (uint32)),
                extraData: message.tokenAmounts[i].extraData,
                amount: message.tokenAmounts[i].amount
            });
        }

        any2EVMMessage = CCIPForkAdapterTypes.V1dot6Any2EVMRampMessage({
            header: message.header,
            sender: abi.encodePacked(message.sender),
            data: message.data,
            receiver: _decodeEVMAddress(message.receiver),
            gasLimit: gasLimit,
            tokenAmounts: tokenAmounts
        });
    }

    function _decodeGasLimit(bytes memory extraArgs) internal pure returns (uint256 gasLimit) {
        if (extraArgs.length == 0) {
            return DEFAULT_GAS_LIMIT;
        }

        // disable-next-line(unsafe-typecast)
        bytes4 extraArgsTag = bytes4(extraArgs);
        bytes memory argsData = new bytes(extraArgs.length - 4);
        for (uint256 i = 4; i < extraArgs.length; ++i) {
            argsData[i - 4] = extraArgs[i];
        }

        if (extraArgsTag == Client.GENERIC_EXTRA_ARGS_V2_TAG) {
            Client.GenericExtraArgsV2 memory decodedArgs = abi.decode(argsData, (Client.GenericExtraArgsV2));
            return decodedArgs.gasLimit;
        }

        if (extraArgsTag == Client.EVM_EXTRA_ARGS_V1_TAG) {
            return abi.decode(argsData, (uint256));
        }

        revert InvalidExtraArgsTag(extraArgsTag);
    }

    function _decodeEVMAddress(bytes memory encodedAddress) internal pure returns (address decodedAddress) {
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
}
