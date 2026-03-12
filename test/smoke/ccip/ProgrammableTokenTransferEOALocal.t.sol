// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {
    CCIPLocalSimulator,
    IRouterClient,
    BurnMintERC677Helper
} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts@4.8.3/token/ERC20/IERC20.sol";

import {BasicMessageReceiver} from "../../../src/test/ccip/BasicMessageReceiver.sol";
import {EncodeExtraArgsOffchain} from "../../../src/test/ccip/utils/EncodeExtraArgsOffchain.sol";

contract ProgrammableTokenTransferEOALocalTest is Test {
    uint64 internal s_chainSelector;
    IRouterClient internal s_sourceRouter;
    IRouterClient internal s_destinationRouter;
    BurnMintERC677Helper internal s_ccipBnM;
    EncodeExtraArgsOffchain internal s_encoder;

    address internal s_alice;

    function setUp() public {
        CCIPLocalSimulator simulator = new CCIPLocalSimulator();
        (
            uint64 chainSelector_,
            IRouterClient sourceRouter_,
            IRouterClient destinationRouter_,,,
            BurnMintERC677Helper ccipBnM_,

        ) = simulator.configuration();

        s_chainSelector = chainSelector_;
        s_sourceRouter = sourceRouter_;
        s_destinationRouter = destinationRouter_;
        s_ccipBnM = ccipBnM_;
        s_encoder = new EncodeExtraArgsOffchain();

        s_alice = makeAddr("alice");
        vm.deal(s_alice, 100 ether);
    }

    function test_programmableTokenTransferEOA_local() external {
        BasicMessageReceiver receiver = new BasicMessageReceiver(address(s_destinationRouter));

        uint256 amountToSend = 0.25 ether;
        s_ccipBnM.drip(s_alice);

        bytes memory payload = bytes("Hello World");
        bytes memory extraArgs = s_encoder.encodeV3Basic(200_000, 1);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(s_ccipBnM), amount: amountToSend});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(receiver)),
            data: payload,
            tokenAmounts: tokenAmounts,
            extraArgs: extraArgs,
            feeToken: address(0)
        });

        vm.startPrank(s_alice);
        IERC20(address(s_ccipBnM)).approve(address(s_sourceRouter), amountToSend);
        uint256 fee = s_sourceRouter.getFee(s_chainSelector, message);
        s_sourceRouter.ccipSend{value: fee}(s_chainSelector, message);
        vm.stopPrank();

        assertEq(receiver.latestSender(), s_alice);
        assertEq(receiver.latestMessage(), payload);
        assertEq(s_ccipBnM.balanceOf(address(receiver)), amountToSend);
    }
}
