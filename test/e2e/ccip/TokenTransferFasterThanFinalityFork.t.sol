// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts@4.8.3/token/ERC20/IERC20.sol";

import {EncodeExtraArgsOffchain} from "../../../src/test/ccip/utils/EncodeExtraArgsOffchain.sol";

contract TokenTransferFasterThanFinalityForkTest is Test {
    CCIPLocalSimulatorFork internal s_forkSimulator;
    EncodeExtraArgsOffchain internal s_encoder;
    uint256 internal s_sourceFork;
    uint256 internal s_destinationFork;

    Register.NetworkDetails internal s_sourceNetwork;
    Register.NetworkDetails internal s_destinationNetwork;

    address internal s_alice;
    address internal s_bob;

    function setUp() public {
        s_sourceFork = vm.createSelectFork(vm.envString("ETHEREUM_SEPOLIA_RPC_URL"));
        s_destinationFork = vm.createFork(vm.envString("ARBITRUM_SEPOLIA_RPC_URL"));

        s_forkSimulator = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(s_forkSimulator));

        s_encoder = new EncodeExtraArgsOffchain();
        vm.makePersistent(address(s_encoder));

        vm.selectFork(s_sourceFork);
        s_sourceNetwork = s_forkSimulator.getNetworkDetails(block.chainid);

        vm.selectFork(s_destinationFork);
        s_destinationNetwork = s_forkSimulator.getNetworkDetails(block.chainid);

        s_alice = makeAddr("alice");
        s_bob = makeAddr("bob");

        vm.selectFork(s_sourceFork);
        vm.deal(s_alice, 10 ether);
    }

    function test_tokenTransferFasterThanFinality_fork() external {
        vm.selectFork(s_sourceFork);
        _fundSourceTokenViaDrip(s_alice); // drip function mints 1e18 of the token
        uint256 amountToSend = 1 ether;

        uint256 sourceBalanceBefore = IERC20(s_sourceNetwork.ccipBnMAddress).balanceOf(s_alice);

        vm.selectFork(s_destinationFork);
        uint256 destinationBalanceBefore = IERC20(s_destinationNetwork.ccipBnMAddress).balanceOf(s_bob);

        vm.selectFork(s_sourceFork);
        bytes memory extraArgs = s_encoder.encodeV3Basic(0, 1);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: s_sourceNetwork.ccipBnMAddress, amount: amountToSend});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(s_bob),
            data: "",
            tokenAmounts: tokenAmounts,
            extraArgs: extraArgs,
            feeToken: address(0)
        });

        vm.startPrank(s_alice);
        IERC20(s_sourceNetwork.ccipBnMAddress).approve(s_sourceNetwork.routerAddress, amountToSend);
        uint256 fee = IRouterClient(s_sourceNetwork.routerAddress).getFee(s_destinationNetwork.chainSelector, message);
        IRouterClient(s_sourceNetwork.routerAddress).ccipSend{value: fee}(s_destinationNetwork.chainSelector, message);
        vm.stopPrank();

        s_forkSimulator.switchChainAndRouteMessage(s_destinationFork);

        vm.selectFork(s_destinationFork);
        assertEq(IERC20(s_destinationNetwork.ccipBnMAddress).balanceOf(s_bob), destinationBalanceBefore + amountToSend);

        vm.selectFork(s_sourceFork);
        assertEq(IERC20(s_sourceNetwork.ccipBnMAddress).balanceOf(s_alice), sourceBalanceBefore - amountToSend);
    }

    function _fundSourceTokenViaDrip(address to) internal {
        (bool dripSuccess,) = s_sourceNetwork.ccipBnMAddress.call(abi.encodeWithSignature("drip(address)", to));
        require(dripSuccess, "drip(address) failed");
    }
}
