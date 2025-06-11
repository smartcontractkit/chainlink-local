// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, Vm} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "../../../src/ccip/CCIPLocalSimulatorFork.sol";

import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {IERC20} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract Looper is CCIPReceiver {
    address internal immutable i_router;
    address internal immutable i_link;
    uint256 public s_messagesReceived;

    constructor(address router, address link) CCIPReceiver(router) {
        i_router = router;
        i_link = link;
    }

    function send(address to, uint64 destinationChainSelector, uint256 numberOfMessages) public {
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(to),
            data: abi.encode("Hello, World!"),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: i_link
        });

        for (uint256 i; i < numberOfMessages; ++i) {
            uint256 fee = IRouterClient(i_router).getFee(destinationChainSelector, message);
            IERC20(i_link).approve(address(i_router), fee);
            IRouterClient(i_router).ccipSend(destinationChainSelector, message);
        }
    }

    function _ccipReceive(Client.Any2EVMMessage memory /*message*/ ) internal override {
        s_messagesReceived++;
    }
}

contract LooperFork is Test {
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    Looper source;
    Looper destination;

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

        source = new Looper(sepoliaNetworkDetails.routerAddress, sepoliaNetworkDetails.linkAddress);

        ccipLocalSimulatorFork.requestLinkFromFaucet(address(source), 10 ether);

        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        destination = new Looper(arbSepoliaNetworkDetails.routerAddress, arbSepoliaNetworkDetails.linkAddress);
    }

    function test_ForkLooper() public {
        vm.selectFork(sepoliaFork);
        uint256 numberOfMessages = 3;

        source.send(address(destination), arbSepoliaNetworkDetails.chainSelector, numberOfMessages);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        assertEq(destination.s_messagesReceived(), numberOfMessages);
    }
}
