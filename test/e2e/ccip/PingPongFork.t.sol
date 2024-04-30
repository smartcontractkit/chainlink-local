// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, Vm} from "forge-std/Test.sol";
import {Ping} from "../../../src/test/ccip/Ping.sol";
import {Pong} from "../../../src/test/ccip/Pong.sol";
import {CCIPLocalSimulatorFork, Register} from "../../../src/ccip/CCIPLocalSimulatorFork.sol";

contract PingPongFork is Test {
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    Ping public ping;
    Pong public pong;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    function setUp() public {
        string memory ETHEREUM_SEPOLIA_RPC_URL = vm.envString("ETHEREUM_SEPOLIA_RPC_URL");
        string memory ARBITRUM_SEPOLIA_RPC_URL = vm.envString("ARBITRUM_SEPOLIA_RPC_URL");
        sepoliaFork = vm.createSelectFork(ETHEREUM_SEPOLIA_RPC_URL);
        arbSepoliaFork = vm.createFork(ARBITRUM_SEPOLIA_RPC_URL);

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        ping = new Ping(sepoliaNetworkDetails.linkAddress, sepoliaNetworkDetails.routerAddress);

        ccipLocalSimulatorFork.requestLinkFromFaucet(address(ping), 1 ether);

        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        pong = new Pong(arbSepoliaNetworkDetails.linkAddress, arbSepoliaNetworkDetails.routerAddress);

        ccipLocalSimulatorFork.requestLinkFromFaucet(address(pong), 1 ether);
    }

    function test_ForkPingPong() public {
        vm.selectFork(sepoliaFork);

        ping.send(address(pong), arbSepoliaNetworkDetails.chainSelector);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork);

        assertEq(ping.PONG(), "Pong");
        vm.selectFork(arbSepoliaFork);
        assertEq(pong.PING(), "Ping");
    }
}
