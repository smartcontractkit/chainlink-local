// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";

contract Pong is CCIPReceiver {
    address link;
    address router;

    string public PING;

    constructor(address _link, address _router) CCIPReceiver(_router) {
        link = _link;
        router = _router;
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal override {
        PING = abi.decode(message.data, (string));

        Client.EVM2AnyMessage memory replyMessage = Client.EVM2AnyMessage({
            receiver: message.sender,
            data: abi.encode("Pong"),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: link
        });

        uint256 fee = IRouterClient(router).getFee(
            message.sourceChainSelector,
            replyMessage
        );
        IERC20(link).approve(address(router), fee);

        IRouterClient(router).ccipSend(
            message.sourceChainSelector,
            replyMessage
        );
    }
}
