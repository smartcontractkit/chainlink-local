// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BasicMessageReceiver} from "./BasicMessageReceiver.sol";

import {Ownable, Ownable2Step} from "@openzeppelin/contracts@5.3.0/access/Ownable2Step.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract BasicMessageReceiverWithCCVs is BasicMessageReceiver, Ownable2Step {
    /// @notice CCV configuration for a source chain.
    /// @dev For incoming messages, this receiver will require this CCV criteria to be met.
    /// Required CCVs must all pass verification. >= optionalThreshold of the optional CCVs must pass verification.
    struct CCVConfig {
        address[] requiredCCVs;
        address[] optionalCCVs;
        uint8 optionalThreshold;
        bool requireFinality;
    }

    /// @notice Arguments required to add a CCV configuration for a source chain.
    struct CCVConfigArgs {
        address[] requiredCCVs;
        address[] optionalCCVs;
        uint64 sourceChainSelector;
        uint8 optionalThreshold;
        bool requireFinality;
    }

    error DuplicateCCV(uint64 sourceChainSelector, address ccv);
    error InvalidOptionalThreshold(uint64 sourceChainSelector, uint8 optionalThreshold);
    error ZeroAddressNotAllowedAsOptional();

    event CCVConfigSet(
        uint64 indexed sourceChainSelector,
        address[] requiredCCVs,
        address[] optionalCCVs,
        uint8 optionalThreshold,
        bool requireFinality
    );

    mapping(uint64 sourceChainSelector => CCVConfig ccvConfig) internal s_ccvConfigs;

    constructor(address router) BasicMessageReceiver(router) Ownable(msg.sender) {}

    /// @dev Override getCCVs
    function getCCVsAndMinBlockDepth(
        uint64 sourceChainSelector,
        bytes calldata /*sender*/
    )
        external
        view
        override
        returns (
            address[] memory requiredCCVs,
            address[] memory optionalCCVs,
            uint8 optionalThreshold,
            uint16 minBlockDepth
        )
    {
        CCVConfig memory config = s_ccvConfigs[sourceChainSelector];
        // If requireFinality is true, minBlockDepth = 0 (require finality).
        // If requireFinality is false, minBlockDepth = 1 (allow any FTF level) - WARNING only use a finality of 1 when
        // you use a trusted sender on the source chain that manages the finality risk when sending messages.
        minBlockDepth = config.requireFinality ? 0 : 1;
        return (config.requiredCCVs, config.optionalCCVs, config.optionalThreshold, minBlockDepth);
    }

    /// @notice Set CCV configurations for source chains.
    /// @param ccvConfigsToSet List of CCV configs to set.
    function applyCCVConfigUpdates(CCVConfigArgs[] calldata ccvConfigsToSet) external virtual onlyOwner {
        for (uint256 i = 0; i < ccvConfigsToSet.length; ++i) {
            CCVConfigArgs memory args = ccvConfigsToSet[i];
            // If optionalThreshold > optionalCCVs.length, then it's impossible to satisfy the optional CCV requirement.
            // If optionalThreshold == optionalCCVs.length, then optional CCVs are essentially required, they should instead
            // be defined as required CCVs.
            if (args.optionalCCVs.length > 0) {
                if (args.optionalThreshold >= args.optionalCCVs.length) {
                    revert InvalidOptionalThreshold(args.sourceChainSelector, args.optionalThreshold);
                }
            } else {
                if (args.optionalThreshold > 0) {
                    revert InvalidOptionalThreshold(args.sourceChainSelector, args.optionalThreshold);
                }
            }
            uint256 requiredCCVLength = args.requiredCCVs.length;
            uint256 optionalCCVLength = args.optionalCCVs.length;
            uint256 totalCCVLength = requiredCCVLength + optionalCCVLength;
            for (uint256 j = 0; j < totalCCVLength; ++j) {
                address ccvAddressJ =
                    j < requiredCCVLength ? args.requiredCCVs[j] : args.optionalCCVs[j - requiredCCVLength];
                // address(0) is a valid required CCV address, but not a valid optional CCV address.
                // This is because address(0) signals to always enforce the default CCVs for the lane.
                if (j >= requiredCCVLength && ccvAddressJ == address(0)) {
                    revert ZeroAddressNotAllowedAsOptional();
                }

                for (uint256 k = j + 1; k < totalCCVLength; ++k) {
                    address ccvAddressK =
                        k < requiredCCVLength ? args.requiredCCVs[k] : args.optionalCCVs[k - requiredCCVLength];
                    if (ccvAddressK == ccvAddressJ) {
                        revert DuplicateCCV(args.sourceChainSelector, ccvAddressK);
                    }
                }
            }
            s_ccvConfigs[args.sourceChainSelector] = CCVConfig({
                requiredCCVs: args.requiredCCVs,
                optionalCCVs: args.optionalCCVs,
                optionalThreshold: args.optionalThreshold,
                requireFinality: args.requireFinality
            });
            emit CCVConfigSet(
                args.sourceChainSelector,
                args.requiredCCVs,
                args.optionalCCVs,
                args.optionalThreshold,
                args.requireFinality
            );
        }
    }
}
