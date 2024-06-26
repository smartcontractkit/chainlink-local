// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {MockV3Aggregator} from "@chainlink/local/src/data-feeds/MockV3Aggregator.sol";

import {BasicDataConsumerV3} from "../../../src/test/data-feeds/BasicDataConsumerV3.sol";

contract BasicDataConsumerV3Test is Test {
    BasicDataConsumerV3 public consumer;
    MockV3Aggregator public mockEthUsdAggregator;

    uint8 public decimals;
    int256 public initialAnswer;

    function setUp() public {
        decimals = 8;
        initialAnswer = 100000000000;
        mockEthUsdAggregator = new MockV3Aggregator(decimals, initialAnswer);
        consumer = new BasicDataConsumerV3(address(mockEthUsdAggregator));
    }

    function test_smoke() public {
        int256 answer = consumer.getChainlinkDataFeedLatestAnswer();
        assertEq(answer, initialAnswer, "answer should be equal to initialAnswer");
    }
}
