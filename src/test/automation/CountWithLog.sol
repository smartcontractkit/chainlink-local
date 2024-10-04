// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ILogAutomation, Log} from "@chainlink/contracts/src/v0.8/automation/interfaces/ILogAutomation.sol";

contract CountWithLog is ILogAutomation {
    event WantsToCount(address indexed msgSender);

    uint256 s_count;

    mapping(uint256 => address) internal s_counters;

    function emitCountLog() public {
        emit WantsToCount(msg.sender);
    }

    function getCurrentCount() public view returns (uint256) {
        return s_count;
    }

    function getCounter(uint256 count) public view returns (address) {
        return s_counters[count];
    }

    function checkLog(Log calldata log, bytes memory /*checkData*/ )
        external
        pure
        returns (bool upkeepNeeded, bytes memory performData)
    {
        upkeepNeeded = true;
        address logSender = address(uint160(uint256(log.topics[1])));
        performData = abi.encode(logSender);
    }

    function performUpkeep(bytes calldata performData) external override {
        s_count += 1;
        address logSender = abi.decode(performData, (address));
        s_counters[s_count] = logSender;
    }
}
