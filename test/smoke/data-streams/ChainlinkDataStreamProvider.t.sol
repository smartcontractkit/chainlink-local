// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {
    DataStreamsLocalSimulator,
    MockVerifierProxy,
    MockFeeManager,
    LinkToken
} from "@chainlink/local/src/data-streams/DataStreamsLocalSimulator.sol";
import {MockReportGenerator} from "@chainlink/local/src/data-streams/MockReportGenerator.sol";

import {ChainlinkDataStreamProvider} from "../../../src/test/data-streams/ChainlinkDataStreamProvider.sol";

contract ChainlinkDataStreamProviderTest is Test {
    DataStreamsLocalSimulator public dataStreamsLocalSimulator;
    MockReportGenerator public mockReportGenerator;
    MockFeeManager public mockFeeManager;

    ChainlinkDataStreamProvider public consumer;
    int192 public initialPrice;

    function setUp() public {
        dataStreamsLocalSimulator = new DataStreamsLocalSimulator();
        (, LinkToken linkToken_,, MockVerifierProxy mockVerifierProxy_, MockFeeManager mockFeeManager_,) =
            dataStreamsLocalSimulator.configuration();

        mockFeeManager = mockFeeManager_;

        initialPrice = 1 ether;
        mockReportGenerator = new MockReportGenerator(initialPrice);

        consumer = new ChainlinkDataStreamProvider(address(mockVerifierProxy_), address(linkToken_));
    }

    function test_smoke() public {
        mockFeeManager.setMockDiscount(address(consumer), 1e18); // 1e18 => 100% discount on fees

        int192 wantPrice = 200;
        int192 wantBid = 100;
        int192 wantAsk = 300;
        mockReportGenerator.updatePriceBidAndAsk(wantPrice, wantBid, wantAsk);

        bytes32 feedId = hex"0003777777777777777777777777777777777777777777777777777777777777";
        address token = 0x7777777777777777777777777777777777777777;
        consumer.setBytes32(token, feedId);

        (bytes memory signedReportV3,) = mockReportGenerator.generateReportV3();

        (address gotToken, int192 gotBid, int192 gotAsk, /*uint32 gotObservationsTimestamp*/ ) =
            consumer.getOraclePrice(token, signedReportV3);

        assertEq(gotToken, token);
        assertEq(gotBid, wantBid);
        assertEq(gotAsk, wantAsk);
    }
}
