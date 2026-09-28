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
        // Zero overrides: EVM2EVMOffRamp 1.5 only replaces a token's `destGasAmount` when its override is non-zero, so
        // the release/mint keeps the gas the source OnRamp stamped (the message gas limit is not a token pool budget).
        uint32[] memory tokenGasOverrides = new uint32[](numberOfTokens);

        bytes memory callData = abi.encodeWithSelector(
            IOffRampExecutePreV1dot6.executeSingleMessage.selector, message, offchainTokenData, tokenGasOverrides
        );
        (success, returnData) = offRamp.call(callData);
    }
}
