// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {
    CCIPLocalSimulator,
    IRouterClient,
    WETH9,
    LinkToken,
    BurnMintERC677Helper
} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

contract ReadmeUsageExampleTest is Test {
    CCIPLocalSimulator public ccipLocalSimulator;
    uint64 public chainSelector;
    IRouterClient public sourceRouter;
    LinkToken public linkToken;
    BurnMintERC677Helper public ccipBnM;

    function setUp() public {
        ccipLocalSimulator = new CCIPLocalSimulator();

        WETH9 wrappedNative;
        IRouterClient destinationRouter;
        BurnMintERC677Helper ccipLnM;
        (chainSelector, sourceRouter, destinationRouter, wrappedNative, linkToken, ccipBnM, ccipLnM) =
            ccipLocalSimulator.configuration();
    }

    function test_sendTokens() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        ccipLocalSimulator.requestLinkFromFaucet(alice, 5 ether);
        ccipBnM.drip(alice);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(ccipBnM), amount: 1 ether});
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(bob),
            data: "",
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 0, allowOutOfOrderExecution: true})),
            feeToken: address(linkToken)
        });

        vm.startPrank(alice);
        uint256 fee = sourceRouter.getFee(chainSelector, message);
        linkToken.approve(address(sourceRouter), fee);
        ccipBnM.approve(address(sourceRouter), 1 ether);
        sourceRouter.ccipSend(chainSelector, message);
        vm.stopPrank();

        assertEq(ccipBnM.balanceOf(bob), 1 ether);
    }
}
