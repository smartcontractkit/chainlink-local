// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";

interface IMockExchange {
    // Get the current ETH : mockToken exchange rate
    // Returns the amount of ETH backing 1 mockToken
    function getExchangeRate() external view returns (uint256);
}

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract MockExchange {
    uint256 internal s_exchangeRate;

    function setExchangeRate(uint256 exchangeRate) external {
        s_exchangeRate = exchangeRate;
    }

    function getExchangeRate() external view returns (uint256) {
        return s_exchangeRate;
    }
}

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract MockExchangeRateLimiter is AutomationCompatibleInterface, OwnerIsCreator {
    error OnlyAutomationForwarderCanCall();

    struct RateDetailsV1 {
        uint256 exchangeRate;
        address tokenAddress;
        uint48 blockTimestamp;
        uint48 blockNumber;
    }

    address internal s_automationForwarder;

    RateDetailsV1 internal s_latestRate;

    modifier onlyAutomationForwarder() {
        if (msg.sender != s_automationForwarder) {
            revert OnlyAutomationForwarderCanCall();
        }
        _;
    }

    event NewRateReported(address indexed target, uint256 indexed exchangeRate, uint256 timestamp, uint256 blockNumber);

    // ================================================================
    // │                        Core logic                            │
    // ================================================================
    function checkUpkeep(bytes calldata checkData)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        address target = abi.decode(checkData, (address));
        uint256 latestExchangeRate = IMockExchange(target).getExchangeRate();

        upkeepNeeded = s_latestRate.exchangeRate != latestExchangeRate;
        performData = abi.encode(latestExchangeRate, target);
    }

    function performUpkeep(bytes calldata performData) external override onlyAutomationForwarder {
        (uint256 latestExchangeRate, address target) = abi.decode(performData, (uint256, address));
        s_latestRate = RateDetailsV1({
            exchangeRate: latestExchangeRate,
            tokenAddress: target,
            blockTimestamp: uint48(block.timestamp),
            blockNumber: uint48(block.number)
        });

        emit NewRateReported(target, latestExchangeRate, block.timestamp, block.number);
    }

    // ================================================================
    // │                      Admin functions                         │
    // ================================================================
    function setAutomationForwarder(address automationForwarder) external onlyOwner {
        s_automationForwarder = automationForwarder;
    }

    // ================================================================
    // │                        View functions                        │
    // ================================================================
    function getLatestRate() external view returns (RateDetailsV1 memory) {
        return s_latestRate;
    }

    function getAutomationForwarder() external view returns (address) {
        return s_automationForwarder;
    }
}

interface IMockExchangeRateLimiter {
    function getLatestRate() external view returns (MockExchangeRateLimiter.RateDetailsV1 memory);
}

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract ExampleConsumer {
    IMockExchangeRateLimiter immutable i_aggregator;

    constructor(address aggregator) {
        i_aggregator = IMockExchangeRateLimiter(aggregator);
    }

    function getLatestExchangeRate() public view returns (uint256) {
        return i_aggregator.getLatestRate().exchangeRate;
    }
}
