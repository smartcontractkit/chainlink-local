// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {CCIPForkAdapterTypes} from "./CCIPForkAdapterTypes.sol";

interface IOffRampExecutePreV1dot6 {
    function executeSingleMessage(
        CCIPForkAdapterTypes.PreV1dot6Message memory message,
        bytes[] memory offchainTokenData,
        uint32[] memory tokenGasOverrides
    ) external;
}

library CCIPForkAdapterPreV1dot6 {
    event CCIPSendRequested(CCIPForkAdapterTypes.PreV1dot6Message message);

    function eventSelector() internal pure returns (bytes32) {
        return CCIPSendRequested.selector;
    }

    function decodeMessage(bytes memory eventData)
        internal
        pure
        returns (CCIPForkAdapterTypes.PreV1dot6Message memory message)
    {
        return abi.decode(eventData, (CCIPForkAdapterTypes.PreV1dot6Message));
    }

    function execute(address offRamp, CCIPForkAdapterTypes.PreV1dot6Message memory message)
        internal
        returns (bool success, bytes memory returnData)
    {
        uint256 numberOfTokens = message.tokenAmounts.length;
        bytes[] memory offchainTokenData = new bytes[](numberOfTokens);
        uint32[] memory tokenGasOverrides = new uint32[](numberOfTokens);

        for (uint256 i = 0; i < numberOfTokens; ++i) {
            tokenGasOverrides[i] = uint32(message.gasLimit);
        }

        bytes memory callData = abi.encodeWithSelector(
            IOffRampExecutePreV1dot6.executeSingleMessage.selector, message, offchainTokenData, tokenGasOverrides
        );
        (success, returnData) = offRamp.call(callData);
    }
}
