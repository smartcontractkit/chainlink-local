// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVerifier {
    function verify(bytes calldata signedReport, address sender) external returns (bytes memory verifierResponse);
    function activateConfig(bytes32 feedId, bytes32 configDigest) external;
    function deactivateConfig(bytes32 feedId, bytes32 configDigest) external;
    function activateFeed(bytes32 feedId) external;
    function deactivateFeed(bytes32 feedId) external;
}
