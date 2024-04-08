// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, Vm} from "forge-std/Test.sol";
import {Ping} from "../../../src/test/ccip/Ping.sol";
import {Pong} from "../../../src/test/ccip/Pong.sol";
import {IERC20} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {CCIPLocalSimulatorFork, Register} from "../../../src/ccip/CCIPLocalSimulatorFork.sol";

contract PingPongFork is Test {
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    Ping public ping;
    Pong public pong;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails mumbaiNetworkDetails;

    uint256 sepoliaFork;
    uint256 mumbaiFork;

    function setUp() public {
        string memory ETHEREUM_SEPOLIA_RPC_URL = vm.envString("ETHEREUM_SEPOLIA_RPC_URL");
        string memory POLYGON_MUMBAI_RPC_URL = vm.envString("POLYGON_MUMBAI_RPC_URL");
        sepoliaFork = vm.createSelectFork(ETHEREUM_SEPOLIA_RPC_URL);
        mumbaiFork = vm.createFork(POLYGON_MUMBAI_RPC_URL);

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        ping = new Ping(sepoliaNetworkDetails.linkAddress, sepoliaNetworkDetails.routerAddress);

        address linkFaucetSepolia = 0x4281eCF07378Ee595C564a59048801330f3084eE;
        vm.startPrank(linkFaucetSepolia);
        IERC20(sepoliaNetworkDetails.linkAddress).transfer(address(ping), 1 ether);
        vm.stopPrank();

        vm.selectFork(mumbaiFork);
        mumbaiNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        pong = new Pong(mumbaiNetworkDetails.linkAddress, mumbaiNetworkDetails.routerAddress);

        address linkFaucetMumbai = 0x4281eCF07378Ee595C564a59048801330f3084eE;
        vm.startPrank(linkFaucetMumbai);
        IERC20(mumbaiNetworkDetails.linkAddress).transfer(address(pong), 1 ether);
        vm.stopPrank();
    }

    function test_ForkPingPong() public {
        vm.selectFork(sepoliaFork);

        ping.send(address(pong), mumbaiNetworkDetails.chainSelector);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(mumbaiFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork);

        assertEq(ping.PONG(), "Pong");
        vm.selectFork(mumbaiFork);
        assertEq(pong.PING(), "Ping");
    }
}
