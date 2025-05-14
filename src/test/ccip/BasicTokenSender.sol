// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract BasicTokenSender {
    using SafeERC20 for IERC20;

    address immutable i_router;

    event MessageSent(bytes32 messageId);

    constructor(address router) {
        i_router = router;
    }

    receive() external payable {}

    function send(uint64 destinationChainSelector, address receiver, Client.EVMTokenAmount[] memory tokensToSendDetails)
        external
        payable
    {
        uint256 length = tokensToSendDetails.length;

        for (uint256 i = 0; i < length;) {
            IERC20(tokensToSendDetails[i].token).safeTransferFrom(
                msg.sender, address(this), tokensToSendDetails[i].amount
            );
            IERC20(tokensToSendDetails[i].token).approve(i_router, tokensToSendDetails[i].amount);

            unchecked {
                ++i;
            }
        }

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: "",
            tokenAmounts: tokensToSendDetails,
            extraArgs: "",
            feeToken: address(0)
        });

        uint256 fee = IRouterClient(i_router).getFee(destinationChainSelector, message);

        bytes32 messageId = IRouterClient(i_router).ccipSend{value: fee}(destinationChainSelector, message);

        emit MessageSent(messageId);
    }
}
