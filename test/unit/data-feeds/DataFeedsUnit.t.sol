// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {MockV3Aggregator} from "@chainlink/local/src/data-feeds/MockV3Aggregator.sol";
import {MockOffchainAggregator} from "@chainlink/local/src/data-feeds/MockOffchainAggregator.sol";
import {AggregatorV2V3Interface} from "@chainlink/local/src/data-feeds/interfaces/AggregatorV2V3Interface.sol";

contract BasicDataConsumerV3Test is Test {
    MockV3Aggregator public mockAggregator;
    MockOffchainAggregator public mockOffchainAggregator;

    uint8 public decimals;
    int256 public initialAnswer;
    uint256 public deploymentTimestamp;
    uint80 public initialRoundId;

    function setUp() public {
        decimals = 8;
        initialAnswer = 100000000000;
        deploymentTimestamp = block.timestamp;
        initialRoundId = 1;

        mockAggregator = new MockV3Aggregator(decimals, initialAnswer);
        mockOffchainAggregator = MockOffchainAggregator(mockAggregator.aggregator());
    }

    function test_shouldReturnDecimals() public {
        uint8 result = mockAggregator.decimals();
        assertEq(result, decimals);
    }

    function test_shouldReturnAnswerByRoundId() public {
        int256 result = mockAggregator.getAnswer(initialRoundId);
        assertEq(result, initialAnswer);
    }

    function test_shouldReturnRoundDataByRoundId() public {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            mockAggregator.getRoundData(initialRoundId);

        assertEq(roundId, initialRoundId);
        assertEq(answer, initialAnswer);
        assertEq(startedAt, deploymentTimestamp);
        assertEq(updatedAt, deploymentTimestamp);
        assertEq(answeredInRound, initialRoundId);
    }

    function test_shouldReturnLatestRoundData() public {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            mockAggregator.latestRoundData();

        assertEq(roundId, initialRoundId);
        assertEq(answer, initialAnswer);
        assertEq(startedAt, deploymentTimestamp);
        assertEq(updatedAt, deploymentTimestamp);
        assertEq(answeredInRound, initialRoundId);
    }

    function test_shouldReturnTimestampByRoundId() public {
        uint256 result = mockAggregator.getTimestamp(initialRoundId);
        assertEq(result, deploymentTimestamp);
    }

    function test_shouldReturnLatestAnswer() public {
        int256 result = mockAggregator.latestAnswer();
        assertEq(result, initialAnswer);
    }

    function test_shouldReturnLatestTimestamp() public {
        uint256 result = mockAggregator.latestTimestamp();
        assertEq(result, deploymentTimestamp);
    }

    function test_shouldReturnLatestRound() public {
        uint256 result = mockAggregator.latestRound();
        assertEq(result, initialRoundId);
    }

    function test_shouldUpdateAnswer() public {
        int256 newAnswer = 200000000000;
        mockOffchainAggregator.updateAnswer(newAnswer);

        (uint80 roundId, int256 answer,,,) = mockAggregator.latestRoundData();

        assertEq(answer, newAnswer);
        assertEq(roundId, initialRoundId + 1);
    }

    function test_shouldUpdateRoundData() public {
        uint80 newRoundId = initialRoundId + 1;
        int256 newAnswer = 200000000000;
        uint256 newStartedAt = deploymentTimestamp + 1;
        uint256 newTimestamp = deploymentTimestamp + 2;

        mockOffchainAggregator.updateRoundData(newRoundId, newAnswer, newTimestamp, newStartedAt);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            mockAggregator.getRoundData(newRoundId);

        assertEq(roundId, initialRoundId + 1);
        assertEq(answer, newAnswer);
        assertEq(startedAt, newStartedAt);
        assertEq(updatedAt, newTimestamp);
        assertEq(answeredInRound, initialRoundId + 1);

        (
            uint80 previousRoundId,
            int256 previousRoundanswer,
            uint256 previousRoundStartedAt,
            uint256 previousRoundUpdatedAt,
            uint80 previousRoundAnsweredInRound
        ) = mockAggregator.getRoundData(initialRoundId);

        assertEq(previousRoundId, initialRoundId);
        assertEq(previousRoundanswer, initialAnswer);
        assertEq(previousRoundStartedAt, deploymentTimestamp);
        assertEq(previousRoundUpdatedAt, deploymentTimestamp);
        assertEq(previousRoundAnsweredInRound, initialRoundId);
    }

    function test_shouldUpdateAggregator() public {
        int256 newAnswer = 200000000000;
        MockOffchainAggregator newMockOffchainAggregator = new MockOffchainAggregator(decimals, newAnswer);

        address currentAggregator = mockAggregator.aggregator();
        address currentProposedAggregator = mockAggregator.proposedAggregator();

        assertEq(currentAggregator, address(mockOffchainAggregator));
        assertEq(currentProposedAggregator, address(0));

        mockAggregator.proposeAggregator(AggregatorV2V3Interface(address(newMockOffchainAggregator)));

        currentProposedAggregator = mockAggregator.proposedAggregator();
        assertEq(currentProposedAggregator, address(newMockOffchainAggregator));

        mockAggregator.confirmAggregator(address(newMockOffchainAggregator));

        currentAggregator = mockAggregator.aggregator();
        currentProposedAggregator = mockAggregator.proposedAggregator();

        assertEq(currentAggregator, address(newMockOffchainAggregator));
        assertEq(currentProposedAggregator, address(0));

        int256 result = mockAggregator.latestAnswer();
        assertEq(result, newAnswer);
    }

    function test_shouldReturnMinAndMaxAnswers() public {
        int192 minAnswer = 1;
        int192 maxAnswer = 95780971304118053647396689196894323976171195136475135; // type(uint176).max

        int192 resultMinAnswer = mockOffchainAggregator.minAnswer();
        int192 resultMaxAnswer = mockOffchainAggregator.maxAnswer();

        assertEq(resultMinAnswer, minAnswer);
        assertEq(resultMaxAnswer, maxAnswer);
    }

    function test_shouldUpdateMinAndMaxAnswers() public {
        int192 newMinAnswer = 0.5 ether;
        int192 newMaxAnswer = 1.5 ether;

        mockOffchainAggregator.updateMinAndMaxAnswers(newMinAnswer, newMaxAnswer);

        int192 resultMinAnswer = mockOffchainAggregator.minAnswer();
        int192 resultMaxAnswer = mockOffchainAggregator.maxAnswer();

        assertEq(resultMinAnswer, newMinAnswer);
        assertEq(resultMaxAnswer, newMaxAnswer);
    }

    function test_shouldRevertIfProposedAggregatorIsZero() public {
        vm.expectRevert("Proposed aggregator cannot be zero address");
        mockAggregator.proposeAggregator(AggregatorV2V3Interface(address(0)));
    }

    function test_shouldRevertIfProposedAggregatorIsCurrentAggregator() public {
        vm.expectRevert("Proposed aggregator cannot be current aggregator");
        mockAggregator.proposeAggregator(AggregatorV2V3Interface(address(mockOffchainAggregator)));
    }

    function test_shouldRevertIfProposedAggregatorIsNotSet() public {
        vm.expectRevert("Invalid proposed aggregator");
        mockAggregator.confirmAggregator(address(1));
    }

    function test_shouldRevertIfProposedAggregatorIsNotCorrect() public {
        int256 newAnswer = 200000000000;
        MockOffchainAggregator newMockOffchainAggregator = new MockOffchainAggregator(decimals, newAnswer);

        mockAggregator.proposeAggregator(AggregatorV2V3Interface(address(newMockOffchainAggregator)));
        vm.expectRevert("Invalid proposed aggregator");
        mockAggregator.confirmAggregator(address(1));
    }

    function test_shouldRevertIfMinAnswerIsGreaterThanMaxAnswer() public {
        int192 newMinAnswer = 1.5 ether;
        int192 newMaxAnswer = 0.5 ether;

        vm.expectRevert("minAnswer must be less than maxAnswer");
        mockOffchainAggregator.updateMinAndMaxAnswers(newMinAnswer, newMaxAnswer);
    }

    function test_shouldRevertIfMinAnswerIsEqualToMaxAnswer() public {
        int192 newMinAnswer = 1.5 ether;
        int192 newMaxAnswer = 1.5 ether;

        vm.expectRevert("minAnswer must be less than maxAnswer");
        mockOffchainAggregator.updateMinAndMaxAnswers(newMinAnswer, newMaxAnswer);
    }

    function test_shouldRevertIfMinAnswerIsLessMinAnswerPossible() public {
        int192 newMinAnswer = 0;
        int192 newMaxAnswer = 1.5 ether;

        vm.expectRevert("minAnswer is too low");
        mockOffchainAggregator.updateMinAndMaxAnswers(newMinAnswer, newMaxAnswer);
    }

    function test_shouldRevertIfMaxAnswerIsGreaterThanMaxAnswerPossible() public {
        int192 newMinAnswer = 0.5 ether;
        int192 newMaxAnswer = type(int192).max;

        vm.expectRevert("maxAnswer is too high");
        mockOffchainAggregator.updateMinAndMaxAnswers(newMinAnswer, newMaxAnswer);
    }
}
