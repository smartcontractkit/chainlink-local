// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";

import {BasicDataConsumerV3} from "../../../src/test/data-feeds/BasicDataConsumerV3.sol";

contract BasicDataConsumerV3Test is Test {
    BasicDataConsumerV3 public consumer;
    address constant ETH_USD_AGGREGATOR_ADDRESS = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    uint256 constant BLOCK_NUMBER = 20163485;
    int256 constant EXPECTED_ANSWER_AT_PINNED_BLOCK_NUMBER = 329182212045; // retrieved from Etherscan

    uint256 ethereumMainnetForkId;

    function setUp() public {
        string memory ETHEREUM_MAINNET_RPC_URL = vm.envString("ETHEREUM_MAINNET_RPC_URL");
        ethereumMainnetForkId = vm.createSelectFork(ETHEREUM_MAINNET_RPC_URL, BLOCK_NUMBER);

        consumer = new BasicDataConsumerV3(ETH_USD_AGGREGATOR_ADDRESS);
    }

    function test_forkSmoke() public {
        assertEq(vm.activeFork(), ethereumMainnetForkId);

        int256 answer = consumer.getChainlinkDataFeedLatestAnswer();
        assertEq(answer, EXPECTED_ANSWER_AT_PINNED_BLOCK_NUMBER);
    }
}
