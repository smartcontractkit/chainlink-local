// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {
    CCIPLocalSimulator,
    IRouterClient
} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

import {BasicMessageReceiverWithCCVs} from "../../../src/test/ccip/BasicMessageReceiverWithCCVs.sol";
import {EncodeExtraArgsOffchain} from "../../../src/test/ccip/utils/EncodeExtraArgsOffchain.sol";

contract HelloWorldBasicMessageReceiverWithCCVsLocalTest is Test {
    address internal constant LOCAL_CCV_A = 0x1111111111111111111111111111111111111111;
    address internal constant LOCAL_CCV_B = 0x2222222222222222222222222222222222222222;
    address internal constant LOCAL_CCV_C = 0x3333333333333333333333333333333333333333;

    uint64 internal s_chainSelector;
    IRouterClient internal s_sourceRouter;
    IRouterClient internal s_destinationRouter;
    EncodeExtraArgsOffchain internal s_encoder;

    address internal s_alice;

    function setUp() public {
        CCIPLocalSimulator simulator = new CCIPLocalSimulator();
        (uint64 chainSelector_, IRouterClient sourceRouter_, IRouterClient destinationRouter_,,,,) = simulator.configuration();

        s_chainSelector = chainSelector_;
        s_sourceRouter = sourceRouter_;
        s_destinationRouter = destinationRouter_;
        s_encoder = new EncodeExtraArgsOffchain();

        s_alice = makeAddr("alice");
        vm.deal(s_alice, 100 ether);
    }

    function test_helloWorldBasicMessageReceiverWithCCVs_local() external {
        BasicMessageReceiverWithCCVs receiver = new BasicMessageReceiverWithCCVs(address(s_destinationRouter));

        address[] memory requiredCCVs = new address[](1);
        requiredCCVs[0] = LOCAL_CCV_A;
        address[] memory optionalCCVs = new address[](2);
        optionalCCVs[0] = LOCAL_CCV_B;
        optionalCCVs[1] = LOCAL_CCV_C;

        BasicMessageReceiverWithCCVs.CCVConfigArgs[] memory updates = new BasicMessageReceiverWithCCVs.CCVConfigArgs[](1);
        updates[0] = BasicMessageReceiverWithCCVs.CCVConfigArgs({
            requiredCCVs: requiredCCVs,
            optionalCCVs: optionalCCVs,
            sourceChainSelector: s_chainSelector,
            optionalThreshold: 1,
            requireFinality: false
        });
        receiver.applyCCVConfigUpdates(updates);

        address[] memory ccvs = new address[](3);
        ccvs[0] = LOCAL_CCV_A;
        ccvs[1] = LOCAL_CCV_B;
        ccvs[2] = LOCAL_CCV_C;
        bytes[] memory ccvArgs = new bytes[](3);

        bytes memory payload = bytes("Hello World");
        bytes memory extraArgs = s_encoder.encodeV3(200_000, 1, ccvs, ccvArgs, address(0), "", "", "");

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(receiver)),
            data: payload,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: extraArgs,
            feeToken: address(0)
        });

        vm.startPrank(s_alice);
        uint256 fee = s_sourceRouter.getFee(s_chainSelector, message);
        bytes32 messageId = s_sourceRouter.ccipSend{value: fee}(s_chainSelector, message);
        vm.stopPrank();

        assertEq(receiver.latestMessageId(), messageId);
        assertEq(receiver.latestSourceChainSelector(), s_chainSelector);
        assertEq(receiver.latestSender(), s_alice);
        assertEq(receiver.latestMessage(), payload);
    }
}
