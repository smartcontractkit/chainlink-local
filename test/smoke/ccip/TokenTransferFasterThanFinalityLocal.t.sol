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

import {EncodeExtraArgsOffchain} from "../../../src/test/ccip/utils/EncodeExtraArgsOffchain.sol";

contract TokenTransferFasterThanFinalityLocalTest is Test {
    CCIPLocalSimulator internal s_localSimulator;
    uint64 internal s_chainSelector;
    IRouterClient internal s_sourceRouter;
    BurnMintERC677Helper internal s_ccipBnM;
    EncodeExtraArgsOffchain internal s_encoder;

    address internal s_alice;
    address internal s_bob;

    function setUp() public {
        s_localSimulator = new CCIPLocalSimulator();
        (uint64 chainSelector_, IRouterClient sourceRouter_,,, , BurnMintERC677Helper ccipBnM_,) =
            s_localSimulator.configuration();

        s_chainSelector = chainSelector_;
        s_sourceRouter = sourceRouter_;
        s_ccipBnM = ccipBnM_;
        s_encoder = new EncodeExtraArgsOffchain();

        s_alice = makeAddr("alice");
        s_bob = makeAddr("bob");
        vm.deal(s_alice, 100 ether);
    }

    function test_tokenTransferFasterThanFinality_local() external {
        uint256 amountToSend = 0.5 ether;
        s_ccipBnM.drip(s_alice);

        uint32 gasLimit = 0;
        uint16 blockConfirmations = 1;
        bytes memory extraArgs = s_encoder.encodeV3Basic(gasLimit, blockConfirmations);
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(s_bob),
            data: "",
            tokenAmounts: _singleTokenAmount(amountToSend),
            extraArgs: extraArgs,
            feeToken: address(0)
        });

        _sendFromAlice(message);

        assertEq(s_ccipBnM.balanceOf(s_alice), 1 ether - amountToSend);
        assertEq(s_ccipBnM.balanceOf(s_bob), amountToSend);
    }

    function _singleTokenAmount(uint256 amount) internal view returns (Client.EVMTokenAmount[] memory tokenAmounts) {
        tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(s_ccipBnM), amount: amount});
    }

    function _sendFromAlice(Client.EVM2AnyMessage memory message) internal returns (bytes32 messageId) {
        vm.startPrank(s_alice);
        for (uint256 i = 0; i < message.tokenAmounts.length; ++i) {
            IERC20(message.tokenAmounts[i].token).approve(address(s_sourceRouter), message.tokenAmounts[i].amount);
        }
        uint256 fee = s_sourceRouter.getFee(s_chainSelector, message);
        messageId = s_sourceRouter.ccipSend{value: fee}(s_chainSelector, message);
        vm.stopPrank();
    }
}
