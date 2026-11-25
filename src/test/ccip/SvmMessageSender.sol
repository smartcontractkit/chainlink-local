// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Withdraw, IERC20, SafeERC20} from "./utils/Withdraw.sol";

import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract SvmMessageSender is Withdraw {
    using SafeERC20 for IERC20;

    address immutable i_router;
    address immutable i_link;

    event MessageSent(bytes32 messageId);

    constructor(address router, address link) {
        i_router = router;
        i_link = link;
    }

    receive() external payable {}

    /**
     * @notice Sends a CCIP message without tokens to a Solana program.
     *
     * @param destinationChainSelector CCIP Chain selector of the destination chain - find it at https://docs.chain.link/ccip/directory/
     * @param receiver Receiver's 32-byte address on the destination chain, i.e. the Solana program ID. Pass `bytes32(0)` to send data without invoking a program.
     * @param dataToSend Payload to include in the CCIP message. If you don't want to send any payload, pass 0x => `bytes memory dataToSend = "";`
     * @param extraArgs Raw CCIP extra args, i.e. `Client._svmArgsToBytes(Client.SVMExtraArgsV1({...}))`.
     * @param feeTokenAddress Token address used to pay CCIP fees. If you want to pay in native gas token pass `address(0)`, otherwise pass LINK token address.
     *
     * @return messageId Unique CCIP message ID returned by the router. Use it to monitor your message in real time at https://ccip.chain.link/
     */
    function send(
        uint64 destinationChainSelector,
        bytes32 receiver,
        bytes memory dataToSend,
        bytes memory extraArgs,
        address feeTokenAddress
    ) external returns (bytes32 messageId) {
        return _send(
            destinationChainSelector, receiver, dataToSend, extraArgs, feeTokenAddress, new Client.EVMTokenAmount[](0)
        );
    }

    /**
     * @notice Like `send`, with `amount` of `token` taken from this contract's balance. The router is approved for it.
     * Put the Solana wallet that receives the tokens in `extraArgs.tokenReceiver`.
     */
    function sendToken(
        uint64 destinationChainSelector,
        bytes32 receiver,
        bytes memory dataToSend,
        bytes memory extraArgs,
        address feeTokenAddress,
        address token,
        uint256 amount
    ) external returns (bytes32 messageId) {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: token, amount: amount});
        IERC20(token).forceApprove(i_router, amount);
        return _send(destinationChainSelector, receiver, dataToSend, extraArgs, feeTokenAddress, tokenAmounts);
    }

    function _send(
        uint64 destinationChainSelector,
        bytes32 receiver,
        bytes memory dataToSend,
        bytes memory extraArgs,
        address feeTokenAddress,
        Client.EVMTokenAmount[] memory tokenAmounts
    ) private returns (bytes32 messageId) {
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encodePacked(receiver),
            data: dataToSend,
            tokenAmounts: tokenAmounts,
            extraArgs: extraArgs,
            feeToken: feeTokenAddress
        });

        uint256 fee = IRouterClient(i_router).getFee(destinationChainSelector, message);

        if (feeTokenAddress == address(0)) {
            messageId = IRouterClient(i_router).ccipSend{value: fee}(destinationChainSelector, message);
        } else {
            IERC20(i_link).approve(i_router, fee);
            messageId = IRouterClient(i_router).ccipSend(destinationChainSelector, message);
        }

        emit MessageSent(messageId);
    }
}
