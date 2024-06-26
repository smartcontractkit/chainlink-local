// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AggregatorV2V3Interface} from "./interfaces/AggregatorV2V3Interface.sol";
import {MockOffchainAggregator} from "./MockOffchainAggregator.sol";

contract MockV3Aggregator is AggregatorV2V3Interface {
    uint256 public constant override version = 0;

    address public aggregator;
    address public proposedAggregator;

    constructor(uint8 _decimals, int256 _initialAnswer) {
        aggregator = address(new MockOffchainAggregator(_decimals, _initialAnswer));
        proposedAggregator = address(0);
    }

    function decimals() external view override returns (uint8) {
        return AggregatorV2V3Interface(aggregator).decimals();
    }

    function getAnswer(uint256 roundId) external view override returns (int256) {
        return AggregatorV2V3Interface(aggregator).getAnswer(roundId);
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return AggregatorV2V3Interface(aggregator).getRoundData(_roundId);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return AggregatorV2V3Interface(aggregator).latestRoundData();
    }

    function getTimestamp(uint256 roundId) external view override returns (uint256) {
        return AggregatorV2V3Interface(aggregator).getTimestamp(roundId);
    }

    function latestAnswer() external view override returns (int256) {
        return AggregatorV2V3Interface(aggregator).latestAnswer();
    }

    function latestTimestamp() external view override returns (uint256) {
        return AggregatorV2V3Interface(aggregator).latestTimestamp();
    }

    function latestRound() external view override returns (uint256) {
        return AggregatorV2V3Interface(aggregator).latestRound();
    }

    function updateAnswer(int256 _answer) public {
        MockOffchainAggregator(aggregator).updateAnswer(_answer);
    }

    function updateRoundData(uint80 _roundId, int256 _answer, uint256 _timestamp, uint256 _startedAt) public {
        MockOffchainAggregator(aggregator).updateRoundData(_roundId, _answer, _timestamp, _startedAt);
    }

    function proposeAggregator(AggregatorV2V3Interface _aggregator) external {
        require(address(_aggregator) != address(0), "Proposed aggregator cannot be zero address");
        require(address(_aggregator) != aggregator, "Proposed aggregator cannot be current aggregator");
        proposedAggregator = address(_aggregator);
    }

    function confirmAggregator(address _aggregator) external {
        require(_aggregator == address(proposedAggregator), "Invalid proposed aggregator");
        aggregator = proposedAggregator;
        proposedAggregator = address(0);
    }

    function description() external pure override returns (string memory) {
        return "src/data-feeds/MockV3Aggregator.sol";
    }
}
