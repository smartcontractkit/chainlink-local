// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {
    DataStreamsLocalSimulator,
    MockVerifierProxy
} from "@chainlink/local/src/data-streams/DataStreamsLocalSimulator.sol";
import {MockReportGenerator} from "@chainlink/local/src/data-streams/MockReportGenerator.sol";

import {ClientReportsVerifier} from "../../../src/test/data-streams/ClientReportsVerifier.sol";

contract ClientReportsVerifierTest is Test {
    DataStreamsLocalSimulator public dataStreamsLocalSimulator;
    MockReportGenerator public mockReportGenerator;

    ClientReportsVerifier public consumer;
    int192 initialPrice;

    function setUp() public {
        dataStreamsLocalSimulator = new DataStreamsLocalSimulator();
        (,,, MockVerifierProxy mockVerifierProxy_,,) = dataStreamsLocalSimulator.configuration();

        initialPrice = 1 ether;
        mockReportGenerator = new MockReportGenerator(initialPrice);

        consumer = new ClientReportsVerifier(address(mockVerifierProxy_));
    }

    function test_smoke() public {
        mockReportGenerator.updateFees(1 ether, 0.5 ether);
        (bytes memory signedReportV3,) = mockReportGenerator.generateReportV3();

        dataStreamsLocalSimulator.requestLinkFromFaucet(address(consumer), 1 ether);

        consumer.verifyReport(signedReportV3);

        int192 lastDecodedPrice = consumer.lastDecodedPrice();
        assertEq(lastDecodedPrice, initialPrice);
    }
}
