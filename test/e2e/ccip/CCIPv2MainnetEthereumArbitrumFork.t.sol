// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {FinalityCodec} from "@chainlink/contracts-ccip/contracts/libraries/FinalityCodec.sol";

import {BasicMessageReceiver} from "../../../src/test/ccip/BasicMessageReceiver.sol";
import {EncodeExtraArgsOffchain} from "../../../src/test/ccip/utils/EncodeExtraArgsOffchain.sol";

interface ITypeAndVersion {
    function typeAndVersion() external view returns (string memory);
}

interface IRouterOnRamp {
    function getOnRamp(uint64 destChainSelector) external view returns (address);
}

/// @dev Mainnet CCIP 2.0 lane Ethereum -> Arbitrum One (default `OFFRAMP_DERIVED` mode, no lane CCV mocking). The
///      Arbitrum router lists EVM2EVMOffRamp 1.2.0 / 1.5.0 and OffRamp 1.6.0 / 2.0.0 for Ethereum, so routing also
///      exercises the mixed-era OffRamp lookup on production contracts.
///      Token transfers are not covered here: as of Sep 2026 the Ethereum LINK pool rejects Arbitrum on this lane
///      (`ChainNotAllowed`), which is live pool configuration rather than simulator behaviour.
contract CCIPv2MainnetEthereumArbitrumForkTest is Test {
    CCIPLocalSimulatorFork internal s_forkSimulator;
    EncodeExtraArgsOffchain internal s_encoder;
    uint256 internal s_ethereumFork;
    uint256 internal s_arbitrumFork;

    Register.NetworkDetails internal s_ethereum;
    Register.NetworkDetails internal s_arbitrum;

    address internal s_alice;

    function setUp() public {
        s_ethereumFork = vm.createSelectFork(vm.envString("ETHEREUM_MAINNET_RPC_URL"));
        s_arbitrumFork = vm.createFork(vm.envString("ARBITRUM_MAINNET_RPC_URL"));

        s_forkSimulator = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(s_forkSimulator));
        s_encoder = new EncodeExtraArgsOffchain();
        vm.makePersistent(address(s_encoder));

        vm.selectFork(s_arbitrumFork);
        s_arbitrum = s_forkSimulator.getNetworkDetails(block.chainid);

        vm.selectFork(s_ethereumFork);
        s_ethereum = s_forkSimulator.getNetworkDetails(block.chainid);
        address onRamp = IRouterOnRamp(s_ethereum.routerAddress).getOnRamp(s_arbitrum.chainSelector);
        assertEq(ITypeAndVersion(onRamp).typeAndVersion(), "OnRamp 2.0.0", "Ethereum -> Arbitrum is not CCIP 2.0");

        s_alice = makeAddr("alice");
        vm.deal(s_alice, 10 ether);
    }

    function test_mainnet_message_ethereumToArbitrum_fork() external {
        vm.selectFork(s_arbitrumFork);
        BasicMessageReceiver receiver = new BasicMessageReceiver(s_arbitrum.routerAddress);

        bytes memory payload = bytes("Hello mainnet CCIP 2.0");
        bytes32 messageId = _send(
            address(receiver),
            payload,
            new Client.EVMTokenAmount[](0),
            s_encoder.encodeV3Basic(200_000, FinalityCodec.WAIT_FOR_FINALITY_FLAG)
        );

        s_forkSimulator.switchChainAndRouteMessage(s_arbitrumFork);

        vm.selectFork(s_arbitrumFork);
        assertEq(receiver.latestMessageId(), messageId);
        assertEq(receiver.latestSourceChainSelector(), s_ethereum.chainSelector);
        assertEq(receiver.latestSender(), s_alice);
        assertEq(receiver.latestMessage(), payload);
    }

    function _send(
        address receiver,
        bytes memory data,
        Client.EVMTokenAmount[] memory tokenAmounts,
        bytes memory extraArgs
    ) internal returns (bytes32 messageId) {
        vm.selectFork(s_ethereumFork);
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: data,
            tokenAmounts: tokenAmounts,
            extraArgs: extraArgs,
            feeToken: address(0)
        });

        vm.startPrank(s_alice);
        uint256 fee = IRouterClient(s_ethereum.routerAddress).getFee(s_arbitrum.chainSelector, message);
        messageId = IRouterClient(s_ethereum.routerAddress).ccipSend{value: fee}(s_arbitrum.chainSelector, message);
        vm.stopPrank();
    }
}
