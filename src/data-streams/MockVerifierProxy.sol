// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OwnerIsCreator} from "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";
import {IERC165} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/interfaces/IERC165.sol";

// import {IVerifier} from "@chainlink/contracts/src/v0.8/llo-feeds/interfaces/IVerifier.sol";
// import {IVerifierFeeManager} from "@chainlink/contracts/src/v0.8/llo-feeds/interfaces/IVerifierFeeManager.sol";
import {IVerifier} from "./interfaces/IVerifier.sol";
import {IVerifierFeeManager} from "./interfaces/IVerifierFeeManager.sol";

contract MockVerifierProxy is OwnerIsCreator {
    error ZeroAddress();
    error VerifierInvalid();
    error VerifierNotFound();

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
}
