// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {ITokenAdminRegistry} from "@chainlink/contracts-ccip/contracts/interfaces/ITokenAdminRegistry.sol";
import {TokenPool} from "@chainlink/contracts-ccip/contracts/pools/TokenPool.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {FinalityCodec} from "@chainlink/contracts-ccip/contracts/libraries/FinalityCodec.sol";
import {IERC20} from "@openzeppelin/contracts@4.8.3/token/ERC20/IERC20.sol";

import {BasicMessageReceiver} from "../../../src/test/ccip/BasicMessageReceiver.sol";
import {BasicMessageReceiverWithCCVs} from "../../../src/test/ccip/BasicMessageReceiverWithCCVs.sol";
import {EncodeExtraArgsOffchain} from "../../../src/test/ccip/utils/EncodeExtraArgsOffchain.sol";

interface ITypeAndVersion {
    function typeAndVersion() external view returns (string memory);
}

interface IRouterOnRamp {
    function getOnRamp(uint64 destChainSelector) external view returns (address);
}

/// @dev Sepolia <-> Fuji over CCIP 2.0, in the default `OFFRAMP_DERIVED` mode with no lane CCV mocking (the
///      production resolver CCVs are pointed at the synthetic fork verifier by the simulator).
///      - Messages use the dedicated CCIP 2.0 routers (Sepolia 0x784d49a7... <-> Fuji 0x7C9B8B4e...), exposed through
///        `getCCIPV2RouterAddress`.
///      - Token transfers use the Register routers, whose Sepolia <-> Fuji lane is also CCIP 2.0 (asserted below): as of
///        Sep 2026 the dedicated CCIP 2.0 routers reject CCIP-BnM with `UnsupportedToken`.
contract CCIPv2RouterSepoliaFujiForkTest is Test {
    CCIPLocalSimulatorFork internal s_forkSimulator;
    EncodeExtraArgsOffchain internal s_encoder;
    uint256 internal s_sepoliaFork;
    uint256 internal s_fujiFork;

    Register.NetworkDetails internal s_sepolia;
    Register.NetworkDetails internal s_fuji;
    address internal s_sepoliaV2Router;
    address internal s_fujiV2Router;

    address internal s_alice;

    function setUp() public {
        s_sepoliaFork = vm.createSelectFork(vm.envString("ETHEREUM_SEPOLIA_RPC_URL"));
        s_fujiFork = vm.createFork(vm.envString("AVALANCHE_FUJI_RPC_URL"));

        s_forkSimulator = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(s_forkSimulator));
        s_encoder = new EncodeExtraArgsOffchain();
        vm.makePersistent(address(s_encoder));

        vm.selectFork(s_fujiFork);
        s_fuji = s_forkSimulator.getNetworkDetails(block.chainid);
        s_fujiV2Router = s_forkSimulator.getCCIPV2RouterAddress(block.chainid);

        vm.selectFork(s_sepoliaFork);
        s_sepolia = s_forkSimulator.getNetworkDetails(block.chainid);
        s_sepoliaV2Router = s_forkSimulator.getCCIPV2RouterAddress(block.chainid);

        s_alice = makeAddr("alice");
        vm.deal(s_alice, 10 ether);
        vm.selectFork(s_fujiFork);
        vm.deal(s_alice, 10 ether);
    }

    function test_v2Router_message_sepoliaToFuji_fork() external {
        vm.selectFork(s_fujiFork);
        BasicMessageReceiver receiver = new BasicMessageReceiver(s_fujiV2Router);

        bytes memory payload = bytes("Hello CCIP 2.0");
        bytes32 messageId = _send(
            s_sepoliaFork,
            s_sepoliaV2Router,
            s_fuji.chainSelector,
            address(receiver),
            payload,
            new Client.EVMTokenAmount[](0),
            s_encoder.encodeV3Basic(200_000, FinalityCodec.WAIT_FOR_FINALITY_FLAG)
        );

        s_forkSimulator.switchChainAndRouteMessage(s_fujiFork);

        vm.selectFork(s_fujiFork);
        assertEq(receiver.latestMessageId(), messageId);
        assertEq(receiver.latestSourceChainSelector(), s_sepolia.chainSelector);
        assertEq(receiver.latestSender(), s_alice);
        assertEq(receiver.latestMessage(), payload);
    }

    function test_v2Router_message_fujiToSepolia_fork() external {
        vm.selectFork(s_sepoliaFork);
        BasicMessageReceiver receiver = new BasicMessageReceiver(s_sepoliaV2Router);

        bytes memory payload = bytes("Hello back");
        bytes32 messageId = _send(
            s_fujiFork,
            s_fujiV2Router,
            s_sepolia.chainSelector,
            address(receiver),
            payload,
            new Client.EVMTokenAmount[](0),
            s_encoder.encodeV3Basic(200_000, FinalityCodec.WAIT_FOR_FINALITY_FLAG)
        );

        s_forkSimulator.switchChainAndRouteMessage(s_sepoliaFork);

        vm.selectFork(s_sepoliaFork);
        assertEq(receiver.latestMessageId(), messageId);
        assertEq(receiver.latestSourceChainSelector(), s_fuji.chainSelector);
        assertEq(receiver.latestSender(), s_alice);
    }

    function test_v2Lane_tokenTransfer_sepoliaToFuji_fork() external {
        address bob = makeAddr("bob");
        uint256 amount = 1 ether;
        Client.EVMTokenAmount[] memory tokenAmounts = _dripCcipBnM(amount);

        vm.selectFork(s_fujiFork);
        uint256 balanceBefore = IERC20(s_fuji.ccipBnMAddress).balanceOf(bob);

        _send(
            s_sepoliaFork,
            _v2LaneRouter(),
            s_fuji.chainSelector,
            bob,
            "",
            tokenAmounts,
            s_encoder.encodeV3Basic(0, FinalityCodec.WAIT_FOR_FINALITY_FLAG)
        );

        s_forkSimulator.switchChainAndRouteMessage(s_fujiFork);

        vm.selectFork(s_fujiFork);
        assertEq(IERC20(s_fuji.ccipBnMAddress).balanceOf(bob), balanceBefore + amount);
    }

    /// @dev Faster-Than-Finality token transfer: requests the smallest finality the live source pool accepts.
    function test_v2Lane_tokenTransferFasterThanFinality_sepoliaToFuji_fork() external {
        address bob = makeAddr("bob");
        uint256 amount = 1 ether;
        Client.EVMTokenAmount[] memory tokenAmounts = _dripCcipBnM(amount);
        bytes4 finality = _poolAllowedFtfFinality(s_sepolia.ccipBnMAddress);
        assertTrue(finality != FinalityCodec.WAIT_FOR_FINALITY_FLAG);

        vm.selectFork(s_fujiFork);
        uint256 balanceBefore = IERC20(s_fuji.ccipBnMAddress).balanceOf(bob);

        _send(
            s_sepoliaFork,
            _v2LaneRouter(),
            s_fuji.chainSelector,
            bob,
            "",
            tokenAmounts,
            s_encoder.encodeV3Basic(0, finality)
        );

        s_forkSimulator.switchChainAndRouteMessage(s_fujiFork);

        vm.selectFork(s_fujiFork);
        assertEq(IERC20(s_fuji.ccipBnMAddress).balanceOf(bob), balanceBefore + amount);
    }

    /// @dev Faster-Than-Finality message to a receiver that opts in via `getCCVsAndFinalityConfig`.
    function test_v2Router_messageFasterThanFinality_sepoliaToFuji_fork() external {
        uint16 blockDepth = 1;
        vm.selectFork(s_fujiFork);
        BasicMessageReceiverWithCCVs receiver = new BasicMessageReceiverWithCCVs(s_fujiV2Router);
        receiver.setAllowedFinalityConfig(s_sepolia.chainSelector, FinalityCodec._encodeBlockDepth(blockDepth));

        bytes memory payload = bytes("Fast hello");
        bytes32 messageId = _send(
            s_sepoliaFork,
            s_sepoliaV2Router,
            s_fuji.chainSelector,
            address(receiver),
            payload,
            new Client.EVMTokenAmount[](0),
            s_encoder.encodeV3BasicBlockDepth(200_000, blockDepth)
        );

        s_forkSimulator.switchChainAndRouteMessage(s_fujiFork);

        vm.selectFork(s_fujiFork);
        assertEq(receiver.latestMessageId(), messageId);
        assertEq(receiver.latestMessage(), payload);
    }

    /// @dev Register router of Sepolia, after asserting its lane to Fuji is served by a CCIP 2.0 OnRamp.
    function _v2LaneRouter() internal returns (address router) {
        vm.selectFork(s_sepoliaFork);
        router = s_sepolia.routerAddress;
        address onRamp = IRouterOnRamp(router).getOnRamp(s_fuji.chainSelector);
        assertEq(ITypeAndVersion(onRamp).typeAndVersion(), "OnRamp 2.0.0", "Sepolia -> Fuji is not a CCIP 2.0 lane");
    }

    function _dripCcipBnM(uint256 amount) internal returns (Client.EVMTokenAmount[] memory tokenAmounts) {
        vm.selectFork(s_sepoliaFork);
        (bool dripped,) = s_sepolia.ccipBnMAddress.call(abi.encodeWithSignature("drip(address)", s_alice));
        require(dripped, "drip(address) failed");
        tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: s_sepolia.ccipBnMAddress, amount: amount});
    }

    function _poolAllowedFtfFinality(address token) internal returns (bytes4 finality) {
        vm.selectFork(s_sepoliaFork);
        address pool = ITokenAdminRegistry(s_sepolia.tokenAdminRegistryAddress).getPool(token);
        bytes4 allowed = TokenPool(pool).getAllowedFinalityConfig();
        uint16 blockDepth = uint16(uint32(allowed & FinalityCodec.BLOCK_DEPTH_MASK));
        if (blockDepth != 0) {
            return FinalityCodec._encodeBlockDepth(blockDepth);
        }
        require(allowed & FinalityCodec.WAIT_FOR_SAFE_FLAG != 0, "source pool does not allow Faster-Than-Finality");
        return FinalityCodec.WAIT_FOR_SAFE_FLAG;
    }

    function _send(
        uint256 sourceFork,
        address router,
        uint64 destChainSelector,
        address receiver,
        bytes memory data,
        Client.EVMTokenAmount[] memory tokenAmounts,
        bytes memory extraArgs
    ) internal returns (bytes32 messageId) {
        vm.selectFork(sourceFork);
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: data,
            tokenAmounts: tokenAmounts,
            extraArgs: extraArgs,
            feeToken: address(0)
        });

        vm.startPrank(s_alice);
        for (uint256 i; i < tokenAmounts.length; ++i) {
            IERC20(tokenAmounts[i].token).approve(router, tokenAmounts[i].amount);
        }
        uint256 fee = IRouterClient(router).getFee(destChainSelector, message);
        messageId = IRouterClient(router).ccipSend{value: fee}(destChainSelector, message);
        vm.stopPrank();
    }
}
