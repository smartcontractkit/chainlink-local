// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Ping} from "../../../src/test/ccip/Ping.sol";
import {Pong} from "../../../src/test/ccip/Pong.sol";
import {TokenTransferor} from "../../../src/test/ccip/TokenTransferor.sol";
import {CCVNoOpVerifier} from "../../../src/test/ccip/CCVNoOpVerifier.sol";
import {BurnMintERC677Helper} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {CCIPLocalSimulatorFork, Register, IRouterFork} from "../../../src/ccip/CCIPLocalSimulatorFork.sol";

/// @dev CCIP 2.0 (CCV) fork routing: a Sepolia -> Arbitrum Sepolia lane runs with a no-op default CCV
///      while every other component (validation, quorum walk, token release/mint, receiver call)
///      stays production code. The no-op CCV is the single counterfactual, because the real CCV
///      requires live attestations that cannot exist on a fork.
///      Routing uses `V2VerificationMode.OFFRAMP_DERIVED`, so the required CCV list comes from the
///      destination OffRamp itself and the raw encoded message is executed permissionlessly — no
///      local `MessageV1` codec involvement.
contract CCIPv2Fork is Test {
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;

    Ping public ping;
    Pong public pong;
    TokenTransferor public sender;
    BurnMintERC677Helper public ccipBnM;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    address alice;

    function setUp() public {
        string memory ETHEREUM_SEPOLIA_RPC_URL = vm.envString("ETHEREUM_SEPOLIA_RPC_URL");
        string memory ARBITRUM_SEPOLIA_RPC_URL = vm.envString("ARBITRUM_SEPOLIA_RPC_URL");
        sepoliaFork = vm.createSelectFork(ETHEREUM_SEPOLIA_RPC_URL);
        arbSepoliaFork = vm.createFork(ARBITRUM_SEPOLIA_RPC_URL);

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));
        ccipLocalSimulatorFork.setV2VerificationMode(CCIPLocalSimulatorFork.V2VerificationMode.OFFRAMP_DERIVED);

        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        // Mock the 2.0 lane's default CCV with a no-op verifier (fork-only).
        CCVNoOpVerifier noOpCCV = new CCVNoOpVerifier();
        vm.selectFork(sepoliaFork);
        address sepoliaOnRamp =
            IRouterFork(sepoliaNetworkDetails.routerAddress).getOnRamp(arbSepoliaNetworkDetails.chainSelector);
        address offRamp = ccipLocalSimulatorFork.getOffRampForLane(
            arbSepoliaFork, sepoliaNetworkDetails.chainSelector, sepoliaOnRamp
        );
        require(offRamp != address(0), "destination off-ramp not found");
        ccipLocalSimulatorFork.setLaneDefaultCCVs(
            arbSepoliaFork, offRamp, sepoliaNetworkDetails.chainSelector, address(noOpCCV)
        );

        ping = new Ping(sepoliaNetworkDetails.linkAddress, sepoliaNetworkDetails.routerAddress);
        ccipLocalSimulatorFork.requestLinkFromFaucet(address(ping), 1 ether);

        sender = new TokenTransferor(sepoliaNetworkDetails.routerAddress, sepoliaNetworkDetails.linkAddress);
        ccipLocalSimulatorFork.requestLinkFromFaucet(address(sender), 25 ether);
        ccipBnM = BurnMintERC677Helper(sepoliaNetworkDetails.ccipBnMAddress);

        vm.selectFork(arbSepoliaFork);
        pong = new Pong(arbSepoliaNetworkDetails.linkAddress, arbSepoliaNetworkDetails.routerAddress);
        // Pong replies on receive, so it needs LINK for the reply fee.
        ccipLocalSimulatorFork.requestLinkFromFaucet(address(pong), 1 ether);

        vm.selectFork(sepoliaFork);
        alice = makeAddr("alice");
    }

    function test_forkMessageOverCCIPv2Lane() public {
        ping.send(address(pong), arbSepoliaNetworkDetails.chainSelector);

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        vm.selectFork(arbSepoliaFork);
        assertEq(pong.PING(), "Ping");
    }

    function test_forkTokenTransferOverCCIPv2Lane() public {
        uint256 amountToSend = 100;
        ccipBnM.drip(address(sender));
        sender.allowlistDestinationChain(arbSepoliaNetworkDetails.chainSelector, true);

        uint256 balanceBefore = ccipBnM.balanceOf(address(sender));
        sender.transferTokensPayLINK(arbSepoliaNetworkDetails.chainSelector, alice, address(ccipBnM), amountToSend);
        assertEq(ccipBnM.balanceOf(address(sender)), balanceBefore - amountToSend);

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        vm.selectFork(arbSepoliaFork);
        BurnMintERC677Helper ccipBnMArbSepolia = BurnMintERC677Helper(arbSepoliaNetworkDetails.ccipBnMAddress);
        assertEq(ccipBnMArbSepolia.balanceOf(alice), amountToSend);
    }
}
