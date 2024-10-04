// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AutomationLocalSimulator} from "@chainlink/local/src/automation/AutomationLocalSimulator.sol";

import {Counter} from "../../../src/test/automation/Counter.sol";

contract MockTimeBasedAutomationTest is Test {
    AutomationLocalSimulator public automationLocalSimulator;
    Counter public targetContract;

    function setUp() public {
        automationLocalSimulator = new AutomationLocalSimulator();
        address forwarder = automationLocalSimulator.configuration();
        targetContract = new Counter();
        targetContract.setAutomationForwarder(forwarder);
    }

    function prepareScenario() public {
        string memory every15Minutes = "*/15 * * * *";
        uint256 performGas = 100_000;

        uint256 id = automationLocalSimulator.registerNewMockTimeBasedUpkeep(
            address(targetContract), targetContract.increment.selector, "", performGas, every15Minutes
        );
        assertGt(id, 0);
    }

    function test_shouldIncreaseBlockTimestampAndAutomateCounter() external {
        uint256 prevCount = targetContract.counter();

        prepareScenario();

        automationLocalSimulator.increaseBlockTimestamp(15 minutes);

        uint256 currentCount = targetContract.counter();
        assertEq(currentCount, prevCount + 1);
    }

    function test_shouldIncreaseBlockTimestampAndAutomateCounterMultipleTimes() external {
        uint256 prevCount = targetContract.counter();

        prepareScenario();

        automationLocalSimulator.increaseBlockTimestamp(46 minutes);

        uint256 currentCount = targetContract.counter();
        assertEq(currentCount, prevCount + 3);
    }
}
