// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {Ping} from "../../../src/test/ccip/Ping.sol";
import {Pong} from "../../../src/test/ccip/Pong.sol";
import {CCIPLocalSimulator, IRouterClient, LinkToken} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";

contract PingPongTest is Test {
    CCIPLocalSimulator public ccipLocalSimulator;

    Ping public ping;
    Pong public pong;

    uint64 chainSelector;

    function setUp() public {
        ccipLocalSimulator = new CCIPLocalSimulator();
        (
            uint64 chainSelector_,
            IRouterClient sourceRouter,
            IRouterClient destinationRouter,
            ,
            LinkToken linkToken,
            ,

        ) = ccipLocalSimulator.configuration();

        ping = new Ping(address(linkToken), address(sourceRouter));
        pong = new Pong(address(linkToken), address(destinationRouter));

        chainSelector = chainSelector_;
    }

    function test_pingPong() external {
        uint256 amountForFees = 1 ether;
        ccipLocalSimulator.requestLinkFromFaucet(address(ping), amountForFees);
        ccipLocalSimulator.requestLinkFromFaucet(address(pong), amountForFees);

        ping.send(address(pong), chainSelector);

        console2.log(pong.PING());
        console2.log(ping.PONG());
    }
}
