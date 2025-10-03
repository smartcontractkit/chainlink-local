// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, Vm} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "../../../src/ccip/CCIPLocalSimulatorFork.sol";

import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {IERC20} from "../../../src/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract Looper is CCIPReceiver {
    address internal immutable i_router;
    address internal immutable i_link;
    uint256 public s_messagesReceived;

    constructor(address router, address link) CCIPReceiver(router) {
        i_router = router;
        i_link = link;
    }

    function sendNMessages(address to, uint64 destinationChainSelector, uint256 numberOfMessages) public {
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

    function send(address destinationArb, address destinationOp, uint64 chainSelectorArb, uint64 chainSelectorOp)
        public
    {
        Client.EVM2AnyMessage memory messageA = Client.EVM2AnyMessage({
            receiver: abi.encode(destinationArb),
            data: abi.encode("Hello, World!"),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: i_link
        });

        Client.EVM2AnyMessage memory messageB = Client.EVM2AnyMessage({
            receiver: abi.encode(destinationOp),
            data: abi.encode("Hello, World!"),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: i_link
        });

        Client.EVM2AnyMessage memory messageC = Client.EVM2AnyMessage({
            receiver: abi.encode(destinationArb),
            data: abi.encode("Hello, World!"),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: i_link
        });

        uint256 feeA = IRouterClient(i_router).getFee(chainSelectorArb, messageA);
        IERC20(i_link).approve(address(i_router), feeA);
        IRouterClient(i_router).ccipSend(chainSelectorArb, messageA);

        uint256 feeB = IRouterClient(i_router).getFee(chainSelectorOp, messageB);
        IERC20(i_link).approve(address(i_router), feeB);
        IRouterClient(i_router).ccipSend(chainSelectorOp, messageB);

        uint256 feeC = IRouterClient(i_router).getFee(chainSelectorArb, messageC);
        IERC20(i_link).approve(address(i_router), feeC);
        IRouterClient(i_router).ccipSend(chainSelectorArb, messageC);
    }

    function _ccipReceive(Client.Any2EVMMessage memory /*message*/ ) internal override {
        s_messagesReceived++;
    }
}

contract LooperFork is Test {
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    Looper source;
    Looper destinationArb;
    Looper destinationOp;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;
    Register.NetworkDetails optimismSepoliaNetworkDetails;

    uint256 sepoliaFork;
    uint256 arbSepoliaFork;
    uint256 optimismSepoliaFork;

    function setUp() public {
        string memory ETHEREUM_SEPOLIA_RPC_URL = vm.envString("ETHEREUM_SEPOLIA_RPC_URL");
        string memory ARBITRUM_SEPOLIA_RPC_URL = vm.envString("ARBITRUM_SEPOLIA_RPC_URL");
        string memory OPTIMISM_SEPOLIA_RPC_URL = vm.envString("OPTIMISM_SEPOLIA_RPC_URL");
        sepoliaFork = vm.createSelectFork(ETHEREUM_SEPOLIA_RPC_URL);
        arbSepoliaFork = vm.createFork(ARBITRUM_SEPOLIA_RPC_URL);
        optimismSepoliaFork = vm.createFork(OPTIMISM_SEPOLIA_RPC_URL);

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        source = new Looper(sepoliaNetworkDetails.routerAddress, sepoliaNetworkDetails.linkAddress);
        ccipLocalSimulatorFork.requestLinkFromFaucet(address(source), 10 ether);

        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        destinationArb = new Looper(arbSepoliaNetworkDetails.routerAddress, arbSepoliaNetworkDetails.linkAddress);

        vm.selectFork(optimismSepoliaFork);
        optimismSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        destinationOp =
            new Looper(optimismSepoliaNetworkDetails.routerAddress, optimismSepoliaNetworkDetails.linkAddress);
    }

    function test_sendNMessagesToSingleChain() public {
        vm.selectFork(sepoliaFork);

        uint256 numberOfMessagesToSend = 3;
        source.sendNMessages(address(destinationArb), arbSepoliaNetworkDetails.chainSelector, numberOfMessagesToSend);

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);
        vm.selectFork(arbSepoliaFork);
        uint256 numberOfMessagesReceived = destinationArb.s_messagesReceived();
        assertEq(numberOfMessagesReceived, numberOfMessagesToSend);
    }

    function test_sendNMessagesToMultipleChains() public {
        vm.selectFork(sepoliaFork);

        source.send(
            address(destinationArb),
            address(destinationOp),
            arbSepoliaNetworkDetails.chainSelector,
            optimismSepoliaNetworkDetails.chainSelector
        );

        uint256[] memory forks = new uint256[](2);
        forks[0] = arbSepoliaFork;
        forks[1] = optimismSepoliaFork;
        ccipLocalSimulatorFork.switchChainAndRouteMessage(forks);

        vm.selectFork(arbSepoliaFork);
        uint256 numberOfMessagesReceived = destinationArb.s_messagesReceived();
        assertEq(numberOfMessagesReceived, 2);

        vm.selectFork(optimismSepoliaFork);
        numberOfMessagesReceived = destinationOp.s_messagesReceived();
        assertEq(numberOfMessagesReceived, 1);
    }
}
