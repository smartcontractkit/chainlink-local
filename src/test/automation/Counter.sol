// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";

contract Counter is OwnerIsCreator {
    uint256 public counter;

    address internal s_automationForwarder;

    error OnlyForwarder();

    modifier onlyForwarder() {
        if (msg.sender != s_automationForwarder) {
            revert OnlyForwarder();
        }
        _;
    }

    function increment() public onlyForwarder {
        counter++;
    }

    function setAutomationForwarder(address automationForwarder) external onlyOwner {
        s_automationForwarder = automationForwarder;
    }
}
