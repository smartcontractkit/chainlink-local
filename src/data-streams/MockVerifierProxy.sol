// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OwnerIsCreator} from "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";
import {IERC165} from "../vendor/openzeppelin-solidity/v4.8.3/contracts/interfaces/IERC165.sol";

// import {IVerifier} from "@chainlink/contracts/src/v0.8/llo-feeds/interfaces/IVerifier.sol";
// import {IVerifierFeeManager} from "@chainlink/contracts/src/v0.8/llo-feeds/interfaces/IVerifierFeeManager.sol";
import {IVerifier} from "./interfaces/IVerifier.sol";
import {IVerifierFeeManager} from "./interfaces/IVerifierFeeManager.sol";

contract MockVerifierProxy is OwnerIsCreator {
    error ZeroAddress();
    error VerifierInvalid();
    error VerifierNotFound();
    error FeeManagerRequired(string message);
    error FeeManagerNotExpected(string message);

    address internal s_verifier;
    IVerifierFeeManager public s_feeManager;

    event VerifierInitialized(address indexed verifierAddress);

    modifier onlyValidVerifier(address verifierAddress) {
        if (verifierAddress == address(0)) revert ZeroAddress();
        if (!IERC165(verifierAddress).supportsInterface(IVerifier.verify.selector)) revert VerifierInvalid();
        _;
    }

    function verify(bytes calldata payload, bytes calldata parameterPayload) external payable returns (bytes memory) {
        IVerifierFeeManager feeManager = s_feeManager;

        _validateBillingMechanism(address(feeManager), parameterPayload);

        // Bill the verifier
        if (address(feeManager) != address(0)) {
            feeManager.processFee{value: msg.value}(payload, parameterPayload, msg.sender);
        }

        return _verify(payload);
    }

    function verifyBulk(bytes[] calldata payloads, bytes calldata parameterPayload)
        external
        payable
        returns (bytes[] memory verifiedReports)
    {
        IVerifierFeeManager feeManager = s_feeManager;

        _validateBillingMechanism(address(feeManager), parameterPayload);

        // Bill the verifier
        if (address(feeManager) != address(0)) {
            feeManager.processFeeBulk{value: msg.value}(payloads, parameterPayload, msg.sender);
        }

        // Verify reports
        verifiedReports = new bytes[](payloads.length);
        for (uint256 i; i < payloads.length; ++i) {
            verifiedReports[i] = _verify(payloads[i]);
        }

        return verifiedReports;
    }

    function _verify(bytes calldata payload) internal returns (bytes memory) {
        if (s_verifier == address(0)) revert VerifierNotFound();

        return IVerifier(s_verifier).verify(payload, msg.sender);
    }

    function initializeVerifier(address verifierAddress) external onlyOwner onlyValidVerifier(verifierAddress) {
        s_verifier = verifierAddress;
        emit VerifierInitialized(verifierAddress);
    }

    function getVerifier(bytes32 /*configDigest*/ ) external view returns (address) {
        return s_verifier;
    }

    function setFeeManager(IVerifierFeeManager feeManager) external {
        s_feeManager = feeManager;
    }

    /**
     * @notice Validates billing mechanism configuration and provides helpful error messages
     * @dev This validation helps developers catch billing mechanism mismatches early in development
     * @param feeManagerAddress Current fee manager address (address(0) if off-chain billing)
     * @param parameterPayload The parameter payload from the consumer contract
     */
    function _validateBillingMechanism(address feeManagerAddress, bytes calldata parameterPayload) internal pure {
        bool hasFeeManager = feeManagerAddress != address(0);
        bool hasParameterPayload = parameterPayload.length > 0;

        // Case 1: On-chain billing is configured but consumer is using off-chain mechanism
        if (hasFeeManager && !hasParameterPayload) {
            revert FeeManagerRequired(
                "On-chain billing is active but your contract is using off-chain billing mechanism. "
                "Either call simulator.enableOffChainBilling() or provide fee token address in parameterPayload. "
                "See: https://docs.chain.link/data-streams/tutorials/evm-onchain-report-verification"
            );
        }

        // Case 2: Off-chain billing is configured but consumer is using on-chain mechanism
        if (!hasFeeManager && hasParameterPayload) {
            revert FeeManagerNotExpected(
                "Off-chain billing is active but your contract is providing parameterPayload for on-chain billing. "
                "Either call simulator.enableOnChainBilling() or pass empty bytes as parameterPayload. "
                "Off-chain billing chains don't require fee handling in smart contracts."
            );
        }

        // Case 3: Both configurations match - validation passes
        // hasFeeManager && hasParameterPayload = On-chain billing (correct)
        // !hasFeeManager && !hasParameterPayload = Off-chain billing (correct)
    }
}
