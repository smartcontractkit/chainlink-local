// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockOffchainAggregator {
    int192 private constant MIN_ANSWER_POSSIBLE = 1;
    int192 private constant MAX_ANSWER_POSSIBLE = 95780971304118053647396689196894323976171195136475135; // type(uint176).max

    uint8 public decimals;
    int256 public latestAnswer;
    uint256 public latestTimestamp;
    uint256 public latestRound;

    // Lowest answer the system is allowed to report in response to transmissions
    // Not exposed from the Proxy contract
    int192 public minAnswer;
    // Highest answer the system is allowed to report in response to transmissions
    // Not exposed from the Proxy contract
    int192 public maxAnswer;

    mapping(uint256 => int256) public getAnswer;
    mapping(uint256 => uint256) public getTimestamp;
    mapping(uint256 => uint256) private getStartedAt;

    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals = _decimals;
        updateAnswer(_initialAnswer);
        // If the minAnswer has a value of 1 and the maxAnswer has a value of 95780971304118053647396689196894323976171195136475135 then that theoretically means there is no min or max for that feed
        // If the minAnswer and maxAnswer values are set to other than those mentioned above, then there are actually min and max for that feed - which you will need to normalize using the demicals value
        minAnswer = MIN_ANSWER_POSSIBLE;
        maxAnswer = MAX_ANSWER_POSSIBLE;
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
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, getAnswer[_roundId], getStartedAt[_roundId], getTimestamp[_roundId], _roundId);
    }

    function latestRoundData()
        external
        view
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
        require(_minAnswer < _maxAnswer, "minAnswer must be less than maxAnswer");
        require(_minAnswer >= MIN_ANSWER_POSSIBLE, "minAnswer is too low");
        require(_maxAnswer <= MAX_ANSWER_POSSIBLE, "maxAnswer is too high");

        minAnswer = _minAnswer;
        maxAnswer = _maxAnswer;
    }
}
