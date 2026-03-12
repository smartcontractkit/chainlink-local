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
contract BasicMessageSender is Withdraw {
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
     * @notice Sends a CCIP message.
     *
     * @param destinationChainSelector CCIP Chain selector of the destination chain - find it at https://docs.chain.link/ccip/directory/
     * @param receiver Receiver's address on the destination chain.
     * @param dataToSend ABI-encoded payload to include in the CCIP message. If you don't want to send any payload, pass 0x => `bytes memory dataToSend = "";`
     * @param tokensToSend Token amounts to send with the message. If you don't want to send any tokens, pass empty array => `Client.EVMTokenAmount[] memory tokensToSend = new Client.EVMTokenAmount[](0);`
     * @param extraArgs Encoded CCIP extra args (use EncodeExtraArgsOffchain helper if needed).
     * @param feeTokenAddress Token address used to pay CCIP fees. If you want to pay in native gas token pass `address(0)`, otherwise pass LINK token address.
     *
     * @return messageId Unique CCIP message ID returned by the router. Use it to monitor your message in real time at https://ccip.chain.link/
     */
    function send(
        uint64 destinationChainSelector,
        address receiver,
        bytes memory dataToSend,
        Client.EVMTokenAmount[] memory tokensToSend,
        bytes memory extraArgs,
        address feeTokenAddress
    ) external returns (bytes32 messageId) {
        if (tokensToSend.length > 0) {
            // Only one token can be send per message
            IERC20(tokensToSend[0].token).safeTransferFrom(msg.sender, address(this), tokensToSend[0].amount);
            IERC20(tokensToSend[0].token).approve(i_router, tokensToSend[0].amount);
        }

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: dataToSend,
            tokenAmounts: tokensToSend,
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
