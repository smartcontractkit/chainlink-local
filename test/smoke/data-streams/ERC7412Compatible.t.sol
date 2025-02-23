// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {
    DataStreamsLocalSimulator,
    MockVerifierProxy
} from "@chainlink/local/src/data-streams/DataStreamsLocalSimulator.sol";
import {MockReportGenerator} from "@chainlink/local/src/data-streams/MockReportGenerator.sol";

import {DataStreamsERC7412Compatible} from "../../../src/test/data-streams/ERC7412Compatible.sol";

contract ERC7412CompatibleTest is Test {
    DataStreamsLocalSimulator public dataStreamsLocalSimulator;
    MockReportGenerator public mockReportGenerator;

    DataStreamsERC7412Compatible public consumer;

    string public constant STRING_DATASTREAMS_FEEDLABEL = "feedIDs";
    string public constant STRING_DATASTREAMS_QUERYLABEL = "timestamp";

    function setUp() public {
        dataStreamsLocalSimulator = new DataStreamsLocalSimulator();
        (,,, MockVerifierProxy mockVerifierProxy_,,) = dataStreamsLocalSimulator.configuration();

        int192 initialPrice = 1 ether;
        mockReportGenerator = new MockReportGenerator(initialPrice);

        consumer = new DataStreamsERC7412Compatible(address(mockVerifierProxy_));
    }

    function test_smoke() public {
        mockReportGenerator.updateFees(1 ether, 0.5 ether);
        dataStreamsLocalSimulator.requestLinkFromFaucet(address(consumer), 0.5 ether);

        bytes32 feedId = hex"0002777777777777777777777777777777777777777777777777777777777777";
        uint32 stalenessTolerance = 5 minutes;

        try consumer.generate7412CompatibleCall(feedId, stalenessTolerance) {}
        catch (bytes memory lowLevelData) {
            if (bytes4(abi.encodeWithSignature("OracleDataRequired(address,bytes)")) == bytes4(lowLevelData)) {
                uint256 length = lowLevelData.length;
                bytes memory revertData = new bytes(length - 4);
                for (uint256 i = 4; i < length; ++i) {
                    revertData[i - 4] = lowLevelData[i];
                }

                (address oracleContract, bytes memory oracleQuery) = abi.decode(revertData, (address, bytes));
                assertEq(oracleContract, address(consumer));

                (, bytes32 revertedFeedId,,,) = abi.decode(oracleQuery, (string, bytes32, string, uint256, string));
                assertEq(feedId, revertedFeedId);

                (bytes memory signedReportV2,) = mockReportGenerator.generateReportV2();

                consumer.fulfillOracleQuery(signedReportV2);
            }
        }
    }
}
