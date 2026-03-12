// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {
    CCIPLocalSimulator,
    IRouterClient,
    LinkToken,
    BurnMintERC677Helper
} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

import {BasicMessageReceiver} from "../../../src/test/ccip/BasicMessageReceiver.sol";
import {BasicMessageSender} from "../../../src/test/ccip/BasicMessageSender.sol";
import {EncodeExtraArgsOffchain} from "../../../src/test/ccip/utils/EncodeExtraArgsOffchain.sol";

contract ProgrammableTokenTransferSenderDefaultFinalityLocalTest is Test {
    uint64 internal s_chainSelector;
    IRouterClient internal s_sourceRouter;
    IRouterClient internal s_destinationRouter;
    LinkToken internal s_link;
    BurnMintERC677Helper internal s_ccipBnM;
    EncodeExtraArgsOffchain internal s_encoder;

    address internal s_alice;

    function setUp() public {
        CCIPLocalSimulator simulator = new CCIPLocalSimulator();
        (
            uint64 chainSelector_,
            IRouterClient sourceRouter_,
            IRouterClient destinationRouter_,,
            LinkToken link_,
            BurnMintERC677Helper ccipBnM_,

        ) = simulator.configuration();

        s_chainSelector = chainSelector_;
        s_sourceRouter = sourceRouter_;
        s_destinationRouter = destinationRouter_;
        s_link = link_;
        s_ccipBnM = ccipBnM_;
        s_encoder = new EncodeExtraArgsOffchain();

        s_alice = makeAddr("alice");
        vm.deal(s_alice, 100 ether);
    }

    function test_programmableTokenTransferSenderDefaultFinality_local() external {
        BasicMessageReceiver receiver = new BasicMessageReceiver(address(s_destinationRouter));
        BasicMessageSender sender = new BasicMessageSender(address(s_sourceRouter), address(s_link));

        vm.deal(address(sender), 1 ether);

        uint256 amountToSend = 0.2 ether;
        s_ccipBnM.drip(s_alice);

        bytes memory payload = bytes("Hello World");
        bytes memory extraArgs = s_encoder.encodeV3Basic(200_000, 0);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(s_ccipBnM), amount: amountToSend});

        vm.startPrank(s_alice);
        s_ccipBnM.approve(address(sender), amountToSend);
        sender.send(s_chainSelector, address(receiver), payload, tokenAmounts, extraArgs, address(0));
        vm.stopPrank();

        assertEq(receiver.latestSender(), address(sender));
        assertEq(receiver.latestMessage(), payload);
        assertEq(s_ccipBnM.balanceOf(address(receiver)), amountToSend);
    }
}
