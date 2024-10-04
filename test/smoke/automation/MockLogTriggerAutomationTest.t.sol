// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AutomationLocalSimulator} from "@chainlink/local/src/automation/AutomationLocalSimulator.sol";

import {CountWithLog} from "../../../src/test/automation/CountWithLog.sol";

contract MockLogTriggerAutomationTest is Test {
    AutomationLocalSimulator public automationLocalSimulator;

    CountWithLog public countWithLog;
    address public alice;
    address public bob;

    function setUp() public {
        automationLocalSimulator = new AutomationLocalSimulator();

        alice = makeAddr("alice");
        bob = makeAddr("bob");

        countWithLog = new CountWithLog();

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
        AutomationLocalSimulator.LogTriggerConfig memory logTriggerConfig = AutomationLocalSimulator.LogTriggerConfig({
            contractEmittingLogs: address(countWithLog),
            filterSelector: 1, // 001
            topic0: CountWithLog.WantsToCount.selector,
            topic1: bytes32(uint256(uint160(alice))),
            topic2: bytes32(0),
            topic3: bytes32(0)
        });

        uint256 performGas = 100_000;
        bytes memory checkData = "";

        automationLocalSimulator.registerNewMockLogTriggerUpkeep(
            address(countWithLog), logTriggerConfig, performGas, checkData
        );
    }

    function test_countWithLog() external {
        uint256 prevCount = countWithLog.getCurrentCount();

        automationLocalSimulator.simulateTx(address(countWithLog), abi.encodeCall(countWithLog.emitCountLog, ()), alice);

        uint256 newCount = countWithLog.getCurrentCount();
        address counter = countWithLog.getCounter(newCount);

        assertEq(prevCount + 1, newCount);
        assertEq(counter, alice);
    }
}
