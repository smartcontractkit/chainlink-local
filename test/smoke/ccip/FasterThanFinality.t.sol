// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ExtraArgsCodec} from "@chainlink/contracts-ccip/contracts/libraries/ExtraArgsCodec.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

import {CCIPLocalSimulator, BurnMintERC677Helper} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";

contract FasterThanFinalityTest is Test {
    uint64 chainSelector;
    BurnMintERC677Helper ccipBnM;
    IRouterClient sourceRouter;

    address alice;
    address bob;

    function setUp() public {
        CCIPLocalSimulator ccipLocalSimulator = new CCIPLocalSimulator();

        (uint64 chainSelector_, IRouterClient sourceRouter_,,,, BurnMintERC677Helper ccipBnM_,) =
            ccipLocalSimulator.configuration();

        chainSelector = chainSelector_;
        sourceRouter = sourceRouter_;
        ccipBnM = ccipBnM_;

        alice = makeAddr("alice");
        bob = makeAddr("bob");
    }

    function test_tokenTransfer() public {
        ccipBnM.drip(alice);

        assertEq(ccipBnM.balanceOf(alice), 1 ether);
        assertEq(ccipBnM.balanceOf(bob), 0);

        uint256 amountToSend = 0.5 ether;
        uint32 gasLimit = 0;
        uint16 blockConfirmations = 1;

        bytes memory extraArgs = ExtraArgsCodec._getBasicEncodedExtraArgsV3(gasLimit, blockConfirmations);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(ccipBnM), amount: amountToSend});

        Client.EVM2AnyMessage memory ccipMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(bob), data: "", tokenAmounts: tokenAmounts, extraArgs: extraArgs, feeToken: address(0)
        });

        vm.startPrank(alice);
        ccipBnM.approve(address(sourceRouter), amountToSend);

        uint256 fee = sourceRouter.getFee(chainSelector, ccipMessage);

        sourceRouter.ccipSend{value: fee}(chainSelector, ccipMessage);
        vm.stopPrank();

        assertEq(ccipBnM.balanceOf(alice), 1 ether - amountToSend);
        assertEq(ccipBnM.balanceOf(bob), amountToSend);
    }
}
