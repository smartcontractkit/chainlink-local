// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {IERC20} from "../../../src/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {CCIPLocalSimulatorFork, IRouterFork} from "../../../src/ccip/CCIPLocalSimulatorFork.sol";
import {Register} from "../../../src/ccip/Register.sol";

/// @dev Minimal receiver so the only “application” code is CCIP wiring; the test sends via the Router directly.
contract MinimalStringReceiver is CCIPReceiver {
    string public lastPayload;

    constructor(address router) CCIPReceiver(router) {}

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        lastPayload = abi.decode(message.data, (string));
    }
}

/// @title Eth Sepolia → Arbitrum Sepolia (fork): multi-OffRamp routing smoke test
/// @notice Production Arb Sepolia routers often register several OffRamps for the same `sourceChainSelector`
///         (Ethereum Sepolia) across upgrades. This test requires that layout and sends a single CCIP message
///         by calling `IRouterClient.ccipSend` on the source router from the test contract, then routes via
///         `CCIPLocalSimulatorFork.switchChainAndRouteMessage`.
contract EthSepoliaToArbSepoliaMultiOffRampForkTest is Test {
    /// @dev CCIP chain selector for Ethereum Sepolia (lane source).
    uint64 internal constant ETH_SEPOLIA_CHAIN_SELECTOR = 16015286601757825753;

    CCIPLocalSimulatorFork internal ccipFork;
    uint256 internal sepoliaFork;
    uint256 internal arbSepoliaFork;

    Register.NetworkDetails internal sepoliaDetails;
    Register.NetworkDetails internal arbDetails;

    IRouterClient internal sepoliaRouter;
    MinimalStringReceiver internal receiver;

    function setUp() public {
        string memory ethSepoliaRpc = vm.envString("ETHEREUM_SEPOLIA_RPC_URL");
        string memory arbSepoliaRpc = vm.envString("ARBITRUM_SEPOLIA_RPC_URL");

        sepoliaFork = vm.createSelectFork(ethSepoliaRpc);
        arbSepoliaFork = vm.createFork(arbSepoliaRpc);

        ccipFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipFork));

        sepoliaDetails = ccipFork.getNetworkDetails(block.chainid);
        sepoliaRouter = IRouterClient(sepoliaDetails.routerAddress);

        vm.selectFork(arbSepoliaFork);
        arbDetails = ccipFork.getNetworkDetails(block.chainid);

        IRouterFork.OffRamp[] memory offRamps = IRouterFork(arbDetails.routerAddress).getOffRamps();
        uint256 matching;
        for (uint256 i; i < offRamps.length; ++i) {
            if (offRamps[i].sourceChainSelector == ETH_SEPOLIA_CHAIN_SELECTOR) {
                ++matching;
            }
        }
        assertGe(
            matching,
            2,
            "Arb Sepolia router must list 2+ OffRamps for Ethereum Sepolia (multi-OffRamp lane); CCIP config may have changed"
        );

        receiver = new MinimalStringReceiver(arbDetails.routerAddress);

        vm.selectFork(sepoliaFork);
        ccipFork.requestLinkFromFaucet(address(this), 5 ether);
    }

    function test_routerDirectSend_routesWhenMultipleOffRampsShareSourceSelector() public {
        string memory payload = "fork-multi-offramp-smoke";

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(receiver)),
            data: abi.encode(payload),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 300_000})),
            feeToken: sepoliaDetails.linkAddress
        });

        vm.selectFork(sepoliaFork);

        uint256 fee = sepoliaRouter.getFee(arbDetails.chainSelector, message);
        IERC20(sepoliaDetails.linkAddress).approve(address(sepoliaRouter), fee);

        sepoliaRouter.ccipSend(arbDetails.chainSelector, message);

        ccipFork.switchChainAndRouteMessage(arbSepoliaFork);

        vm.selectFork(arbSepoliaFork);
        assertEq(receiver.lastPayload(), payload);
    }
}
