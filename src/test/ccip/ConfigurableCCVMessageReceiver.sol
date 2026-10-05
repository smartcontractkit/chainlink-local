// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
/// @notice Test-only receiver whose `getCCVsAndFinalityConfig` response is fully controllable, including invalid
/// configurations (duplicate CCVs, out-of-range optional thresholds) and arbitrary reverts. This is needed to
/// exercise `CCIPLocalRouter`'s mirroring of `OffRamp._getCCVsFromReceiver`: the validated setters on
/// `BasicMessageReceiverWithCCVs` cannot reach these invalid states, but a hostile or buggy production receiver can
/// return them, and the OffRamp (and therefore the local router) must reject them.
contract ConfigurableCCVMessageReceiver is CCIPReceiver {
    bytes32 public latestMessageId;
    bytes public latestMessage;

    address[] internal s_requiredCCVs;
    address[] internal s_optionalCCVs;
    uint8 internal s_optionalThreshold;
    bytes4 internal s_allowedFinalityConfig;

    bool internal s_shouldRevert;
    bytes internal s_revertData;

    constructor(address router) CCIPReceiver(router) {}

    /// @dev No validation on purpose: used to construct configs a real receiver's own setters would reject.
    function setCCVConfig(
        address[] memory requiredCCVs,
        address[] memory optionalCCVs,
        uint8 optionalThreshold,
        bytes4 allowedFinalityConfig
    ) external {
        s_requiredCCVs = requiredCCVs;
        s_optionalCCVs = optionalCCVs;
        s_optionalThreshold = optionalThreshold;
        s_allowedFinalityConfig = allowedFinalityConfig;
    }

    function setRevert(bool shouldRevert, bytes memory revertData) external {
        s_shouldRevert = shouldRevert;
        s_revertData = revertData;
    }

    function getCCVsAndFinalityConfig(uint64, bytes calldata)
        external
        view
        override
        returns (
            address[] memory requiredCCVs,
            address[] memory optionalCCVs,
            uint8 optionalThreshold,
            bytes4 allowedFinalityConfig
        )
    {
        if (s_shouldRevert) {
            bytes memory data = s_revertData;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                revert(add(data, 32), mload(data))
            }
        }
        return (s_requiredCCVs, s_optionalCCVs, s_optionalThreshold, s_allowedFinalityConfig);
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        latestMessageId = message.messageId;
        latestMessage = message.data;
    }
}
