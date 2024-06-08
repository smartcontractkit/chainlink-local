// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AggregatorV2V3Interface} from "./interfaces/AggregatorV2V3Interface.sol";

contract MockOffchainAggregator is AggregatorV2V3Interface {
    uint256 public constant override version = 0;
    uint8 public override decimals;
    int256 public override latestAnswer;
    uint256 public override latestTimestamp;
    uint256 public override latestRound;

    // Lowest answer the system is allowed to report in response to transmissions
    // Not exposed from the Proxy contract
    int192 public minAnswer;
    // Highest answer the system is allowed to report in response to transmissions
    // Not exposed from the Proxy contract
    int192 public maxAnswer;

    mapping(uint256 => int256) public override getAnswer;
    mapping(uint256 => uint256) public override getTimestamp;
    mapping(uint256 => uint256) private getStartedAt;

    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals = _decimals;
        updateAnswer(_initialAnswer);
        // If the minAnswer has a value of 1 and the maxAnswer has a value of 95780971304118053647396689196894323976171195136475135 then that theoretically means there is no min or max for that feed
        // If the minAnswer and maxAnswer values are set to other than those mentioned above, then there are actually min and max for that feed - which you will need to normalize using the demicals value
        minAnswer = 1;
        maxAnswer = type(int192).max;
    }

    function updateAnswer(int256 _answer) public {
        latestAnswer = _answer;
        latestTimestamp = block.timestamp;
        latestRound++;
        getAnswer[latestRound] = _answer;
        getTimestamp[latestRound] = block.timestamp;
        getStartedAt[latestRound] = block.timestamp;
    }

    function updateRoundData(uint80 _roundId, int256 _answer, uint256 _timestamp, uint256 _startedAt) public {
        latestRound = _roundId;
        latestAnswer = _answer;
        latestTimestamp = _timestamp;
        getAnswer[latestRound] = _answer;
        getTimestamp[latestRound] = _timestamp;
        getStartedAt[latestRound] = _startedAt;
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, getAnswer[_roundId], getStartedAt[_roundId], getTimestamp[_roundId], _roundId);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (
            uint80(latestRound),
            getAnswer[latestRound],
            getStartedAt[latestRound],
            getTimestamp[latestRound],
            uint80(latestRound)
        );
    }

    function updateMinAndMaxAnswers(int192 _minAnswer, int192 _maxAnswer) external {
        minAnswer = _minAnswer;
        maxAnswer = _maxAnswer;
    }

    function description() external pure override returns (string memory) {
        return "src/data-feeds/MockOffchainAggregator.sol";
    }
}
