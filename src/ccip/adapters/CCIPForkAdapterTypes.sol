// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

library CCIPForkAdapterTypes {
    struct RouterOffRamp {
        uint64 sourceChainSelector;
        address offRamp;
    }

    struct PreV1dot6Message {
        uint64 sourceChainSelector;
        address sender;
        address receiver;
        uint64 sequenceNumber;
        uint256 gasLimit;
        bool strict;
        uint64 nonce;
        address feeToken;
        uint256 feeTokenAmount;
        bytes data;
        Client.EVMTokenAmount[] tokenAmounts;
        bytes[] sourceTokenData;
        bytes32 messageId;
    }

    struct V1dot6RampMessageHeader {
        bytes32 messageId;
        uint64 sourceChainSelector;
        uint64 destChainSelector;
        uint64 sequenceNumber;
        uint64 nonce;
    }

    struct V1dot6EVM2AnyTokenTransfer {
        address sourcePoolAddress;
        bytes destTokenAddress;
        bytes extraData;
        uint256 amount;
        bytes destExecData;
    }

    struct V1dot6Any2EVMTokenTransfer {
        bytes sourcePoolAddress;
        address destTokenAddress;
        uint32 destGasAmount;
        bytes extraData;
        uint256 amount;
    }

    struct V1dot6EVM2AnyRampMessage {
        V1dot6RampMessageHeader header;
        address sender;
        bytes data;
        bytes receiver;
        bytes extraArgs;
        address feeToken;
        uint256 feeTokenAmount;
        uint256 feeValueJuels;
        V1dot6EVM2AnyTokenTransfer[] tokenAmounts;
    }

    struct V1dot6Any2EVMRampMessage {
        V1dot6RampMessageHeader header;
        bytes sender;
        bytes data;
        address receiver;
        uint256 gasLimit;
        V1dot6Any2EVMTokenTransfer[] tokenAmounts;
    }

    struct V2Receipt {
        address issuer;
        uint32 destGasLimit;
        uint32 destBytesOverhead;
        uint256 feeTokenAmount;
        bytes extraArgs;
    }
}
