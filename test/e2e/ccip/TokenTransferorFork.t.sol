// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, Vm} from "forge-std/Test.sol";
import {TokenTransferor} from "../../../src/test/ccip/TokenTransferor.sol";
import {BurnMintERC677Helper, IERC20} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {CCIPLocalSimulatorFork, Register} from "../../../src/ccip/CCIPLocalSimulatorFork.sol";

contract TokenTransferorFork is Test {
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    TokenTransferor public sender;
    BurnMintERC677Helper public ccipBnM;
    IERC20 public linkToken;
    address alice;

    uint256 sepoliaFork;
    uint256 mumbaiFork;

    function setUp() public {
        string memory ETHEREUM_SEPOLIA_RPC_URL = vm.envString("ETHEREUM_SEPOLIA_RPC_URL");
        string memory POLYGON_MUMBAI_RPC_URL = vm.envString("POLYGON_MUMBAI_RPC_URL");
        sepoliaFork = vm.createSelectFork(ETHEREUM_SEPOLIA_RPC_URL);
        mumbaiFork = vm.createFork(POLYGON_MUMBAI_RPC_URL);

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        Register.NetworkDetails memory sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        sender = new TokenTransferor(sepoliaNetworkDetails.routerAddress, sepoliaNetworkDetails.linkAddress);

        ccipBnM = BurnMintERC677Helper(sepoliaNetworkDetails.ccipBnMAddress);

        linkToken = IERC20(sepoliaNetworkDetails.linkAddress);

        alice = makeAddr("alice");

        address linkFaucetSepolia = 0x4281eCF07378Ee595C564a59048801330f3084eE;
        vm.startPrank(linkFaucetSepolia);
        linkToken.transfer(address(sender), 25 ether);
        vm.stopPrank();
    }

    function test_forkTokenTransfer() external {
        uint256 amountToSend = 100;
        ccipBnM.drip(address(sender));

        uint64 polygonChainSelector = 12532609583862916517;
        sender.allowlistDestinationChain(polygonChainSelector, true);

        uint256 balanceBefore = ccipBnM.balanceOf(address(sender));

        sender.transferTokensPayLINK(polygonChainSelector, alice, address(ccipBnM), amountToSend);

        uint256 balanceAfer = ccipBnM.balanceOf(address(sender));
        assertEq(balanceAfer, balanceBefore - amountToSend);

        ccipLocalSimulatorFork.switchChainAndRouteMessage(mumbaiFork);

        Register.NetworkDetails memory mumbaiNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        BurnMintERC677Helper ccipBnMPolygon = BurnMintERC677Helper(mumbaiNetworkDetails.ccipBnMAddress);

        assertEq(ccipBnMPolygon.balanceOf(alice), amountToSend);
    }
}
