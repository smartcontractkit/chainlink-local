// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Test, Vm} from "forge-std/Test.sol";

import {CronExternal, Spec} from "./MockCron.sol";
import {MockAutomationForwarder} from "./MockAutomationForwarder.sol";

import {AutomationCompatibleInterface} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {ILogAutomation, Log} from "@chainlink/contracts/src/v0.8/automation/interfaces/ILogAutomation.sol";
import {EnumerableSet} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/utils/structs/EnumerableSet.sol";

contract AutomationLocalSimulator is Test {
    using EnumerableSet for EnumerableSet.UintSet;

    enum TriggerType {
        CONDITION,
        LOG,
        TIME_BASED
    }

    struct MockTimeBasedUpkeep {
        address target;
        bytes4 performSelector;
        uint256 lastRun;
        uint256 performGas;
        bytes performData;
        string cronString;
        Spec spec;
    }

    struct MockCustomLogicUpkeep {
        address target;
        uint256 performGas;
        bytes checkData;
    }

    struct MockLogTriggerUpkeep {
        address target;
        LogTriggerConfig logTriggerConfig;
        uint256 performGas;
        bytes checkData;
    }

    bytes4 internal constant PERFORM_SELECTOR = AutomationCompatibleInterface.performUpkeep.selector;
    uint256 internal constant DEFAULT_GAS_LIMIT = 500_000;

    MockAutomationForwarder internal immutable i_forwarder;

    uint32 internal s_nonce; // Nonce for each upkeep created
    uint256 internal s_lastProcessedEvent;
    EnumerableSet.UintSet internal s_timeBasedUpkeepIds;
    EnumerableSet.UintSet internal s_customLogicUpkeepIds;
    EnumerableSet.UintSet internal s_logTriggerUpkeepIds;

    mapping(uint256 => MockTimeBasedUpkeep) internal s_timeBasedUpkeeps;
    mapping(uint256 => MockCustomLogicUpkeep) internal s_customLogicUpkeeps;
    mapping(uint256 => MockLogTriggerUpkeep) internal s_logTriggerUpkeeps;

    error AutomationSimulator_ChekUpkeepFailed(address target, bytes checkData);
    error AutomationSimulator_PerformUpkeepFailed(address target, bytes performData);

    event AutomationSimulator_PerformUpkeep(uint256 indexed id, uint256 gasUsed);

    constructor() {
        vm.recordLogs();
        i_forwarder = new MockAutomationForwarder();
    }

    // ================================================================
    // │                 Register Upkeep Logic (UI)                   │
    // ================================================================

    function registerNewMockCustomLogicUpkeep(address target, uint256 performGas, bytes calldata checkData)
        external
        returns (uint256 id)
    {
        s_nonce++;
        id = _createID(TriggerType.CONDITION);
        s_customLogicUpkeepIds.add(id);

        s_customLogicUpkeeps[id] = MockCustomLogicUpkeep({target: target, performGas: performGas, checkData: checkData});
    }

    function registerNewMockLogTriggerUpkeep(
        address target,
        LogTriggerConfig memory logTriggerConfig,
        uint256 performGas,
        bytes calldata checkData
    ) external returns (uint256 id) {
        s_nonce++;
        id = _createID(TriggerType.LOG);
        s_logTriggerUpkeepIds.add(id);

        logTriggerConfig.filterSelector = logTriggerConfig.filterSelector & 0x07; // Mask to get only the last 3 bits

        s_logTriggerUpkeeps[id] = MockLogTriggerUpkeep({
            target: target,
            logTriggerConfig: logTriggerConfig,
            performGas: performGas,
            checkData: checkData
        });
    }

    function registerNewMockTimeBasedUpkeep(
        address target,
        bytes4 performSelector,
        bytes calldata performData,
        uint256 performGas,
        string calldata cronString
    ) external returns (uint256 id) {
        s_nonce++;
        id = _createID(TriggerType.TIME_BASED);
        s_timeBasedUpkeepIds.add(id);

        Spec memory spec = CronExternal.toSpec(cronString);
        s_timeBasedUpkeeps[id] = MockTimeBasedUpkeep({
            target: target,
            performSelector: performSelector,
            lastRun: block.timestamp,
            performGas: performGas,
            performData: performData,
            cronString: cronString,
            spec: spec
        });
    }

    // ================================================================
    // │                     MAIN FUNCTIONALITY                       │
    // ================================================================

    function simulateTx(address targetContract, bytes memory abiEncodedFuncWithArguments, address msgSender)
        external
        returns (bytes memory)
    {
        _preTxHook();

        vm.startPrank(msgSender);
        (bool ok, bytes memory returnData) = targetContract.call(abiEncodedFuncWithArguments);
        vm.stopPrank();
        require(ok);

        _postTxHook();

        return returnData;
    }

    /**
     * @dev calls the Upkeep target with the performData param passed and the exact gas required by the Upkeep
     */
    function _performUpkeep(address target, bytes4 performSelector, bytes memory performData, uint256 performGas)
        internal
        returns (bool success, uint256 gasUsed)
    {
        performData = abi.encodeWithSelector(performSelector, performData);
        return i_forwarder.forward(target, performGas, performData);
    }

    function _preTxHook() internal {
        _checkTimeBasedUpkeeps();
    }

    function _postTxHook() internal {
        _checkCustomLogicUpkeeps();
        _checkLogTriggerUpkeeps();
    }

    // ================================================================
    // │                   Condition trigger logic                    │
    // ================================================================

    function _checkCustomLogicUpkeeps() internal {
        uint256 length = s_customLogicUpkeepIds.length();
        for (uint256 i = 0; i < length; ++i) {
            uint256 id = s_customLogicUpkeepIds.at(i);
            MockCustomLogicUpkeep memory currentUpkeep = s_customLogicUpkeeps[id];

            // eth_call
            (bool ok, bytes memory returnData) = currentUpkeep.target.staticcall{gas: DEFAULT_GAS_LIMIT}(
                abi.encodeWithSelector(AutomationCompatibleInterface.checkUpkeep.selector, currentUpkeep.checkData)
            );
            if (!ok) {
                revert AutomationSimulator_ChekUpkeepFailed(currentUpkeep.target, currentUpkeep.checkData);
            }

            (bool upkeepNeeded, bytes memory performData) = abi.decode(returnData, (bool, bytes));
            if (upkeepNeeded) {
                (bool success, uint256 gasUsed) =
                    _performUpkeep(currentUpkeep.target, PERFORM_SELECTOR, performData, currentUpkeep.performGas);
                if (!success) {
                    revert AutomationSimulator_PerformUpkeepFailed(currentUpkeep.target, performData);
                }
                emit AutomationSimulator_PerformUpkeep(id, gasUsed);
            }
        }
    }

    // ================================================================
    // │                     Log trigger logic                        │
    // ================================================================

    struct LogTriggerConfig {
        address contractEmittingLogs; // must have address that will be emitting the log
        uint8 filterSelector; // must have filtserSelector, denoting  which topics apply to filter ex 000, 101, 111...only last 3 bits apply
        bytes32 topic0; // must have signature of the emitted event
        bytes32 topic1; // optional filter on indexed topic 1
        bytes32 topic2; // optional filter on indexed topic 2
        bytes32 topic3; // optional filter on indexed topic 3
    }

    /**
     * How to use the filterSelector:
     *
     * | Filter | Description                             | Example                                                          |
     * |--------|-----------------------------------------|------------------------------------------------------------------|
     * | `000`  | No Topic Filters Applied                | event Foo(uint bar, uint baz, uint qux);                         |
     * | `001`  | Filter on Topic 1 Only                  | event Foo(uint indexed bar, uint baz, uint qux);                 |
     * | `010`  | Filter on Topic 2 Only                  | event Foo(uint bar, uint indexed baz, uint qux);                 |
     * | `011`  | Filter on Topic 1 and Topic 2           | event Foo(uint indexed bar, uint indexed baz, uint qux);         |
     * | `100`  | Filter on Topic 3 Only                  | event Foo(uint bar, uint baz, uint indexed qux);                 |
     * | `101`  | Filter on Topic 1 and Topic 3           | event Foo(uint indexed bar, uint baz, uint indexed qux);         |
     * | `110`  | Filter on Topic 2 and Topic 3           | event Foo(uint bar, uint indexed baz, uint indexed qux);         |
     * | `111`  | Filter on Topic 1, Topic 2, and Topic 3 | event Foo(uint indexed bar, uint indexed baz, uint indexed qux); |
     */

    /**
     * @notice Checks if the log entry should trigger the upkeep
     * @param entry The recorded log from Foundry
     * @param config The upkeep log trigger configuration
     * @return bool True if the upkeep should be performed, false otherwise
     */
    function shouldProcessLog(Vm.Log memory entry, LogTriggerConfig memory config) internal pure returns (bool) {
        if (entry.emitter != config.contractEmittingLogs) {
            return false;
        }

        uint8 MASK_TOPIC1 = 0x01; // 001
        uint8 MASK_TOPIC2 = 0x02; // 010
        uint8 MASK_TOPIC3 = 0x04; // 100

        if ((config.filterSelector & MASK_TOPIC1) != 0) {
            if (entry.topics.length < 2 || entry.topics[1] != config.topic1) {
                return false;
            }
        }

        if ((config.filterSelector & MASK_TOPIC2) != 0) {
            if (entry.topics.length < 3 || entry.topics[2] != config.topic2) {
                return false;
            }
        }

        if ((config.filterSelector & MASK_TOPIC3) != 0) {
            if (entry.topics.length < 4 || entry.topics[3] != config.topic3) {
                return false;
            }
        }

        return true;
    }

    function _checkLogTriggerUpkeeps() internal {
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 start = s_lastProcessedEvent;
        uint256 end = entries.length;
        uint256 logTriggerUpkeepsLength = s_logTriggerUpkeepIds.length();

        for (uint256 i = 0; i < logTriggerUpkeepsLength; ++i) {
            uint256 id = s_logTriggerUpkeepIds.at(i);
            MockLogTriggerUpkeep memory currentUpkeep = s_logTriggerUpkeeps[id];

            for (uint256 j = start; j < end; ++j) {
                if (entries[i].topics[0] == currentUpkeep.logTriggerConfig.topic0) {
                    // Event caught
                    if (shouldProcessLog(entries[j], currentUpkeep.logTriggerConfig)) {
                        Log memory log = Log({
                            index: j,
                            timestamp: block.timestamp,
                            txHash: bytes32(0),
                            blockNumber: block.number,
                            blockHash: blockhash(block.number),
                            source: entries[j].emitter,
                            topics: entries[j].topics,
                            data: entries[j].data
                        });

                        (bool ok, bytes memory returnData) = currentUpkeep.target.staticcall{gas: DEFAULT_GAS_LIMIT}(
                            abi.encodeWithSelector(ILogAutomation.checkLog.selector, log, currentUpkeep.checkData)
                        );
                        if (!ok) {
                            revert AutomationSimulator_ChekUpkeepFailed(currentUpkeep.target, currentUpkeep.checkData);
                        }

                        (bool upkeepNeeded, bytes memory performData) = abi.decode(returnData, (bool, bytes));
                        if (upkeepNeeded) {
                            (bool success, uint256 gasUsed) = _performUpkeep(
                                currentUpkeep.target, PERFORM_SELECTOR, performData, currentUpkeep.performGas
                            );
                            if (!success) {
                                revert AutomationSimulator_PerformUpkeepFailed(currentUpkeep.target, performData);
                            }
                            emit AutomationSimulator_PerformUpkeep(id, gasUsed);
                        }
                    }
                }
            }
        }

        s_lastProcessedEvent = entries.length - 1;
    }

    // ================================================================
    // │                  Time-based trigger logic                    │
    // ================================================================

    function _checkTimeBasedUpkeeps() internal {
        uint256 length = s_timeBasedUpkeepIds.length();
        for (uint256 i = 0; i < length; ++i) {
            uint256 id = s_timeBasedUpkeepIds.at(i);
            MockTimeBasedUpkeep memory currentUpkeep = s_timeBasedUpkeeps[id];
            uint256 lastTick = CronExternal.lastTick(currentUpkeep.spec);

            if (lastTick > currentUpkeep.lastRun) {
                uint256 nextTick = CronExternal.nextTick(currentUpkeep.spec);
                uint256 interval = nextTick - lastTick;
                if (interval == 0) {
                    (bool success, uint256 gasUsed) = _performUpkeep(
                        currentUpkeep.target,
                        currentUpkeep.performSelector,
                        currentUpkeep.performData,
                        currentUpkeep.performGas
                    );
                    if (!success) {
                        revert AutomationSimulator_PerformUpkeepFailed(currentUpkeep.target, currentUpkeep.performData);
                    }
                    emit AutomationSimulator_PerformUpkeep(id, gasUsed);
                }
            }
        }
    }

    function increaseBlockTimestamp(uint256 numberOfSecondsToSkipForward) external {
        skip(numberOfSecondsToSkipForward);

        uint256 length = s_timeBasedUpkeepIds.length();
        for (uint256 i = 0; i < length; ++i) {
            uint256 id = s_timeBasedUpkeepIds.at(i);
            MockTimeBasedUpkeep memory currentUpkeep = s_timeBasedUpkeeps[id];
            uint256 lastTick = CronExternal.lastTick(currentUpkeep.spec);

            if (lastTick > currentUpkeep.lastRun) {
                uint256 nextTick = CronExternal.nextTick(currentUpkeep.spec);
                uint256 interval = nextTick - lastTick;
                if (interval == 0) {
                    (bool success, uint256 gasUsed) = _performUpkeep(
                        currentUpkeep.target,
                        currentUpkeep.performSelector,
                        currentUpkeep.performData,
                        currentUpkeep.performGas
                    );
                    if (!success) {
                        revert AutomationSimulator_PerformUpkeepFailed(currentUpkeep.target, currentUpkeep.performData);
                    }
                    emit AutomationSimulator_PerformUpkeep(id, gasUsed);
                } else {
                    uint256 numberOfTicksMissed = block.timestamp / interval;
                    for (uint256 j = 0; j < numberOfTicksMissed; ++j) {
                        (bool success, uint256 gasUsed) = _performUpkeep(
                            currentUpkeep.target,
                            currentUpkeep.performSelector,
                            currentUpkeep.performData,
                            currentUpkeep.performGas
                        );
                        if (!success) {
                            revert AutomationSimulator_PerformUpkeepFailed(
                                currentUpkeep.target, currentUpkeep.performData
                            );
                        }
                        emit AutomationSimulator_PerformUpkeep(id, gasUsed);
                    }
                }

                currentUpkeep.lastRun = block.timestamp;
            }
        }
    }

    /**
     * @dev creates an ID for the upkeep based on the upkeep's type
     * @dev the format of the ID looks like this:
     * ****00000000000X****************
     * 4 bytes of entropy
     * 11 bytes of zeros
     * 1 identifying byte for the trigger type
     * 16 bytes of entropy
     * @dev this maintains the same level of entropy as eth addresses, so IDs will still be unique
     * @dev we add the "identifying" part in the middle so that it is mostly hidden from users who usually only
     * see the first 4 and last 4 hex values ex 0x1234...ABCD
     */
    function _createID(TriggerType triggerType) internal view returns (uint256) {
        bytes1 empty;
        bytes memory idBytes =
            abi.encodePacked(keccak256(abi.encode(keccak256(abi.encode(block.number - 1)), address(this), s_nonce)));
        for (uint256 idx = 4; idx < 15; idx++) {
            idBytes[idx] = empty;
        }
        idBytes[15] = bytes1(uint8(triggerType));
        return uint256(bytes32(idBytes));
    }

    function configuration() external view returns (address forwarder) {
        return address(i_forwarder);
    }
}
