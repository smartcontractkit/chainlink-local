// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts@4.8.3/token/ERC20/IERC20.sol";

import {BasicMessageReceiver} from "../../../src/test/ccip/BasicMessageReceiver.sol";

interface ITypeAndVersion {
    function typeAndVersion() external view returns (string memory);
}

/// @dev CCIP 1.6 regression. The live Sepolia -> Arbitrum Sepolia lane has been migrated to CCIP 2.0, so both forks
///      are pinned to blocks where it was still a 1.6 lane (needs archive RPCs):
///      - Sepolia 11_500_000: Register router `getOnRamp(arbSepolia)` is OnRamp 1.6.0 0x23a5084F...
///      - Arbitrum Sepolia 298_680_335 (L2 block, same timestamp): the router lists EVM2EVMOffRamp 1.2.0 and 1.5.0 plus
///        OffRamp 1.6.0 0xF4EbCC2c... for Sepolia, so routing also exercises the mixed-era OffRamp lookup.
contract CCIPv1dot6PinnedBlockForkTest is Test {
    uint256 internal constant SEPOLIA_V1_6_BLOCK = 11_500_000;
    uint256 internal constant ARB_SEPOLIA_V1_6_BLOCK = 298_680_335;

    CCIPLocalSimulatorFork internal s_forkSimulator;
    uint256 internal s_sourceFork;
    uint256 internal s_destinationFork;

    Register.NetworkDetails internal s_sourceNetwork;
    Register.NetworkDetails internal s_destinationNetwork;

    address internal s_alice;

    function setUp() public {
        s_sourceFork = vm.createSelectFork(vm.envString("ETHEREUM_SEPOLIA_RPC_URL"), SEPOLIA_V1_6_BLOCK);
        s_destinationFork = vm.createFork(vm.envString("ARBITRUM_SEPOLIA_RPC_URL"), ARB_SEPOLIA_V1_6_BLOCK);

        s_forkSimulator = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(s_forkSimulator));

        vm.selectFork(s_destinationFork);
        s_destinationNetwork = s_forkSimulator.getNetworkDetails(block.chainid);

        vm.selectFork(s_sourceFork);
        s_sourceNetwork = s_forkSimulator.getNetworkDetails(block.chainid);

        address onRamp = IRouterClient(s_sourceNetwork.routerAddress)
            .isChainSupported(s_destinationNetwork.chainSelector)
            ? _onRamp()
            : address(0);
        assertEq(ITypeAndVersion(onRamp).typeAndVersion(), "OnRamp 1.6.0", "pinned block is not a 1.6 lane");

        s_alice = makeAddr("alice");
        vm.deal(s_alice, 10 ether);
    }

    function test_v1dot6_message_deliversAbiEncodedSender_fork() external {
        vm.selectFork(s_destinationFork);
        BasicMessageReceiver receiver = new BasicMessageReceiver(s_destinationNetwork.routerAddress);

        bytes memory payload = bytes("Hello 1.6");
        bytes32 messageId = _send(address(receiver), payload, new Client.EVMTokenAmount[](0), 200_000);

        s_forkSimulator.switchChainAndRouteMessage(s_destinationFork);

        vm.selectFork(s_destinationFork);
        assertEq(receiver.latestMessageId(), messageId);
        assertEq(receiver.latestSourceChainSelector(), s_sourceNetwork.chainSelector);
        // `abi.decode(message.sender, (address))` in the receiver only succeeds for the 32-byte encoding (#62 / #65).
        assertEq(receiver.latestSender(), s_alice);
        assertEq(receiver.latestMessage(), payload);
    }

    function test_v1dot6_tokenTransfer_fork() external {
        address bob = makeAddr("bob");
        uint256 amount = 1 ether;
        (bool dripped,) = s_sourceNetwork.ccipBnMAddress.call(abi.encodeWithSignature("drip(address)", s_alice));
        require(dripped, "drip(address) failed");

        vm.selectFork(s_destinationFork);
        uint256 balanceBefore = IERC20(s_destinationNetwork.ccipBnMAddress).balanceOf(bob);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: s_sourceNetwork.ccipBnMAddress, amount: amount});
        _send(bob, "", tokenAmounts, 0);

        s_forkSimulator.switchChainAndRouteMessage(s_destinationFork);

        vm.selectFork(s_destinationFork);
        assertEq(IERC20(s_destinationNetwork.ccipBnMAddress).balanceOf(bob), balanceBefore + amount);
    }

    /// @dev 1.6 OnRamps serve every destination from one address, so a 1.6 message must only execute on the fork of
    ///      its destination chain. Base Sepolia is listed first: without the destination filter, its 1.6 OffRamp for
    ///      Sepolia (bound to the same OnRamp) executed the Arbitrum-bound message there and marked it processed, and
    ///      Arbitrum Sepolia never received it. Needs BASE_SEPOLIA_RPC_URL (archive).
    function test_v1dot6_multiDestination_executesOnlyOnDestinationFork() external {
        uint256 sourceTimestamp = block.timestamp;
        uint256 baseFork = _forkAtTimestamp(vm.envString("BASE_SEPOLIA_RPC_URL"), sourceTimestamp + 60);

        vm.selectFork(s_destinationFork);
        BasicMessageReceiver receiver = new BasicMessageReceiver(s_destinationNetwork.routerAddress);

        bytes32 messageId = _send(address(receiver), bytes("only Arbitrum"), new Client.EVMTokenAmount[](0), 200_000);

        uint256[] memory forks = new uint256[](2);
        forks[0] = baseFork;
        forks[1] = s_destinationFork;
        vm.selectFork(s_sourceFork);
        s_forkSimulator.switchChainAndRouteMessage(forks);

        vm.selectFork(s_destinationFork);
        assertEq(receiver.latestMessageId(), messageId);
        (CCIPLocalSimulatorFork.MessageStatus status,) = s_forkSimulator.getMessageStatus(messageId);
        assertEq(uint8(status), uint8(CCIPLocalSimulatorFork.MessageStatus.SUCCESS));
    }

    /// @dev The single-fork overload leaves the destination fork selected, even when nothing was captured.
    function test_switchChainAndRouteMessage_selectsDestinationForkWithoutMessages_fork() external {
        vm.selectFork(s_sourceFork);
        s_forkSimulator.switchChainAndRouteMessage(s_destinationFork);
        assertEq(vm.activeFork(), s_destinationFork);
    }

    /// @dev Routing one destination fork per call: a message to a chain that is not in `forkIds` is kept (QUEUED, not a
    ///      strict-mode failure) and routed by the later call for its destination. Before, the first call reverted with
    ///      MessageNotRouted in strict mode (or dropped the message in non-strict mode, as the logs were consumed).
    ///      Needs BASE_SEPOLIA_RPC_URL (archive).
    function test_v1dot6_routesEachDestinationInItsOwnCall_fork() external {
        uint256 sourceTimestamp = block.timestamp;
        uint256 baseFork = _forkAtTimestamp(vm.envString("BASE_SEPOLIA_RPC_URL"), sourceTimestamp + 60);
        Register.NetworkDetails memory baseNetwork = s_forkSimulator.getNetworkDetails(block.chainid);
        BasicMessageReceiver baseReceiver = new BasicMessageReceiver(baseNetwork.routerAddress);

        vm.selectFork(s_destinationFork);
        BasicMessageReceiver arbReceiver = new BasicMessageReceiver(s_destinationNetwork.routerAddress);

        bytes32 arbMessageId =
            _send(address(arbReceiver), bytes("to Arbitrum"), new Client.EVMTokenAmount[](0), 200_000);
        bytes32 baseMessageId = _sendTo(
            baseNetwork.chainSelector, address(baseReceiver), bytes("to Base"), new Client.EVMTokenAmount[](0), 200_000
        );

        vm.selectFork(s_sourceFork);
        s_forkSimulator.switchChainAndRouteMessage(s_destinationFork);

        assertEq(vm.activeFork(), s_destinationFork);
        assertEq(arbReceiver.latestMessageId(), arbMessageId);
        (CCIPLocalSimulatorFork.MessageStatus status,) = s_forkSimulator.getMessageStatus(baseMessageId);
        assertEq(uint8(status), uint8(CCIPLocalSimulatorFork.MessageStatus.QUEUED));

        s_forkSimulator.switchChainAndRouteMessage(baseFork);

        assertEq(vm.activeFork(), baseFork);
        assertEq(baseReceiver.latestMessageId(), baseMessageId);
        assertEq(baseReceiver.latestSourceChainSelector(), s_sourceNetwork.chainSelector);
        (status,) = s_forkSimulator.getMessageStatus(baseMessageId);
        assertEq(uint8(status), uint8(CCIPLocalSimulatorFork.MessageStatus.SUCCESS));
    }

    /// @dev Forks `rpcUrl` at the last block whose timestamp is <= `timestamp` (binary search, archive RPC).
    function _forkAtTimestamp(string memory rpcUrl, uint256 timestamp) internal returns (uint256 forkId) {
        forkId = vm.createSelectFork(rpcUrl);
        uint256 high = block.number;
        uint256 low = 1;
        while (high - low > 1) {
            uint256 mid = (low + high) / 2;
            vm.rollFork(mid);
            if (block.timestamp <= timestamp) low = mid;
            else high = mid;
        }
        vm.rollFork(low);
    }

    function _onRamp() internal view returns (address) {
        (bool ok, bytes memory data) = s_sourceNetwork.routerAddress
            .staticcall(abi.encodeWithSignature("getOnRamp(uint64)", s_destinationNetwork.chainSelector));
        require(ok, "getOnRamp failed");
        return abi.decode(data, (address));
    }

    function _send(address receiver, bytes memory data, Client.EVMTokenAmount[] memory tokenAmounts, uint256 gasLimit)
        internal
        returns (bytes32 messageId)
    {
        return _sendTo(s_destinationNetwork.chainSelector, receiver, data, tokenAmounts, gasLimit);
    }

    function _sendTo(
        uint64 destinationChainSelector,
        address receiver,
        bytes memory data,
        Client.EVMTokenAmount[] memory tokenAmounts,
        uint256 gasLimit
    ) internal returns (bytes32 messageId) {
        vm.selectFork(s_sourceFork);
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: data,
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({gasLimit: gasLimit, allowOutOfOrderExecution: true})
            ),
            feeToken: address(0)
        });

        vm.startPrank(s_alice);
        for (uint256 i; i < tokenAmounts.length; ++i) {
            IERC20(tokenAmounts[i].token).approve(s_sourceNetwork.routerAddress, tokenAmounts[i].amount);
        }
        uint256 fee = IRouterClient(s_sourceNetwork.routerAddress).getFee(destinationChainSelector, message);
        messageId = IRouterClient(s_sourceNetwork.routerAddress).ccipSend{value: fee}(destinationChainSelector, message);
        vm.stopPrank();
    }
}
