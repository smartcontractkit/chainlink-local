// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 *
 * Ping-pong with a Solana receiver. `start` sends a count to Solana; when a message comes back from Solana,
 * `ccipReceive` decodes the count and, while it is below `maxCount`, sends `count + 1` to the configured Solana
 * receiver. The contract pays the fee in native, so fund it with native tokens.
 */
contract SvmPingPong is CCIPReceiver {
    uint64 public immutable i_solanaChainSelector;

    uint256 public maxCount;
    /// @notice The last count received from Solana.
    uint256 public lastCount;
    uint256 public receivedCount;
    bytes32 public solanaReceiver;
    uint32 public computeUnits;
    uint64 public writableBitmap;
    bytes32[] internal s_accounts;

    event PingSent(bytes32 indexed messageId, uint256 count);

    constructor(address router, uint64 solanaChainSelector) CCIPReceiver(router) {
        i_solanaChainSelector = solanaChainSelector;
    }

    receive() external payable {}

    /// @param receiver The Solana program that receives every leg (use the `test_ccip_receiver` program so the EVM ->
    ///        Solana leg executes on Solana).
    /// @param accounts The accounts the receiver needs after the fixed CCIP ones.
    function configure(
        bytes32 receiver,
        uint256 newMaxCount,
        uint32 newComputeUnits,
        uint64 newWritableBitmap,
        bytes32[] calldata accounts
    ) external {
        solanaReceiver = receiver;
        maxCount = newMaxCount;
        computeUnits = newComputeUnits;
        writableBitmap = newWritableBitmap;
        s_accounts = accounts;
    }

    function start(uint256 count) external returns (bytes32) {
        return _send(count);
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        uint256 count = abi.decode(message.data, (uint256));
        lastCount = count;
        ++receivedCount;
        if (count < maxCount) _send(count + 1);
    }

    function _send(uint256 count) internal returns (bytes32 messageId) {
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encodePacked(solanaReceiver),
            data: abi.encode(count),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._svmArgsToBytes(
                Client.SVMExtraArgsV1({
                    computeUnits: computeUnits,
                    accountIsWritableBitmap: writableBitmap,
                    allowOutOfOrderExecution: true,
                    tokenReceiver: bytes32(0),
                    accounts: s_accounts
                })
            ),
            feeToken: address(0)
        });
        uint256 fee = IRouterClient(i_ccipRouter).getFee(i_solanaChainSelector, message);
        messageId = IRouterClient(i_ccipRouter).ccipSend{value: fee}(i_solanaChainSelector, message);
        emit PingSent(messageId, count);
    }
}
