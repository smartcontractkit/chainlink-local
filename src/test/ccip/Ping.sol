// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {IERC20} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";

contract Ping is CCIPReceiver {
    address link;
    address router;

    string public PONG;

    constructor(address _link, address _router) CCIPReceiver(_router) {
        link = _link;
        router = _router;
    }

    function send(address receiver, uint64 destinationChainSelector) external returns (bytes32 messageId) {
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: abi.encode("Ping"),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit
                Client.EVMExtraArgsV1({gasLimit: 500_000})
            ),
            feeToken: link
        });

        uint256 fee = IRouterClient(router).getFee(destinationChainSelector, message);

        IERC20(link).approve(address(router), fee);

        messageId = IRouterClient(router).ccipSend(destinationChainSelector, message);
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        PONG = abi.decode(message.data, (string));
    }
}
