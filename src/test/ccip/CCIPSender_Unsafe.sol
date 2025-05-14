// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {IERC20} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract CCIPSender_Unsafe {
    address link;
    address router;

    constructor(address _link, address _router) {
        link = _link;
        router = _router;
    }

    function send(
        address receiver,
        string memory someText,
        uint64 destinationChainSelector,
        address _token,
        uint256 _amount
    ) external returns (bytes32 messageId) {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount = Client.EVMTokenAmount({token: _token, amount: _amount});
        tokenAmounts[0] = tokenAmount;

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: abi.encode(someText),
            tokenAmounts: tokenAmounts,
            extraArgs: "",
            feeToken: link
        });

        IERC20(_token).approve(address(router), _amount);

        uint256 fee = IRouterClient(router).getFee(destinationChainSelector, message);
        IERC20(link).approve(address(router), fee);

        messageId = IRouterClient(router).ccipSend(destinationChainSelector, message);
    }
}
