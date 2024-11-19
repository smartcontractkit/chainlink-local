// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC165} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/interfaces/IERC165.sol";

contract MockVerifier is IERC165 {
    error AccessForbidden();
    error InactiveFeed(bytes32 feedId);
    error DigestInactive(bytes32 feedId, bytes32 configDigest);
    error BadVerification();
    error InvalidV();
    error AlreadyUsedSignature();
    error InvalidSignatureLength();
    error InvalidS();

    // secp256k1 Curve Order N / 2 (to prevent signature malleability s <= N / 2)
    uint256 constant N_2 = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;
    // Generated from uint256(keccak256(abi.encodePacked("Mock Data Streams DON")));
    address constant MOCK_DATA_STREAM_DON_ADDRESS = 0x143f40b47ab222503b787e98940023c59fc29984;

    address internal immutable i_verifierProxy;

    mapping(bytes32 => mapping(bytes32 => bool)) internal s_inactiveDigests;
    mapping(bytes32 => bool) internal s_inactiveFeeds;
    mapping(bytes => bool) internal s_verifiedSignatures;

    event ReportVerified(bytes32 indexed feedId, address indexed sender);

    constructor(address verifierProxy) {
        i_verifierProxy = verifierProxy;
    }

    function verify(bytes calldata signedReport, address sender) external returns (bytes memory verifierResponse) {
        if (msg.sender != i_verifierProxy) revert AccessForbidden();

        (
            bytes32[3] memory reportContext,
            bytes memory reportData,
            bytes32[] memory rs,
            bytes32[] memory ss,
            bytes32 rawVs
        ) = abi.decode(signedReport, (bytes32[3], bytes, bytes32[], bytes32[], bytes32));

        // The feed ID is the first 32 bytes of the report data.
        bytes32 feedId = bytes32(reportData);
        if (s_inactiveFeeds[feedId]) revert InactiveFeed(feedId);

        bytes32 configDigest = reportContext[0];
        if (s_inactiveDigests[feedId][configDigest]) revert DigestInactive(feedId, configDigest);

        // Decoding recid (v) like this works only for the mock verifier. In fork mode, use Verifier.sol from @chainlink/contracts.
        uint8 v = uint8(uint256(rawVs));
        // Recid (v) can also be 0 or 1, however 0x01 precompile expects 27 or 28.
        if (v < 27) v += 27;
        // Prevents signature malleability
        if (v != 27 && v != 28) revert InvalidV();

        bytes memory signature = abi.encodePacked(rs[0], ss[0], v);

        // Prevents replay attacks
        if (s_verifiedSignatures[signature]) revert AlreadyUsedSignature();

        // MockReportGenerator will only generate standard "r,s,v" signatures. EIP-2098 and ERC-1271 are not supported.
        if (signature.length != 65) revert InvalidSignatureLength();

        // Prevents signature malleability using EIP-2
        if (uint256(ss[0]) > N_2) revert InvalidS();

        // Expired signatures are handled in MockVerifierProxy.sol
        // In local mode we don't care about cross-chain replay attacks, because everything is on one local network.

        bytes32 hashedReport = keccak256(reportData);
        bytes32 h = keccak256(abi.encodePacked(hashedReport, reportContext));

        address signer = ecrecover(h, v, rs[0], ss[0]);
        if (signer != MOCK_DATA_STREAM_DON_ADDRESS) revert BadVerification();

        s_verifiedSignatures[signature] = true;
        emit ReportVerified(feedId, sender);

        return reportData;
    }

    function deactivateConfig(bytes32 feedId, bytes32 configDigest) external {
        s_inactiveDigests[feedId][configDigest] = true;
    }

    function activateConfig(bytes32 feedId, bytes32 configDigest) external {
        s_inactiveDigests[feedId][configDigest] = false;
    }

    function deactivateFeed(bytes32 feedId) external {
        s_inactiveFeeds[feedId] = true;
    }

    function activateFeed(bytes32 feedId) external {
        s_inactiveFeeds[feedId] = false;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == this.verify.selector;
    }
}
