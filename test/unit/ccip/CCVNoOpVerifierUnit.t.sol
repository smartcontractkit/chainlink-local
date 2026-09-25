// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ICrossChainVerifierV1} from "@chainlink/contracts-ccip/contracts/interfaces/ICrossChainVerifierV1.sol";
import {
    ICrossChainVerifierResolver
} from "@chainlink/contracts-ccip/contracts/interfaces/ICrossChainVerifierResolver.sol";
import {ICCVNoOpVerifierFork} from "../../../src/test/ccip/CCVNoOpVerifier.sol";

/// @dev `CCVNoOpVerifier` mirrors the CCIP 2.0 verifier types locally. If a dependency bump changes `MessageV1` or the
///      verifier interfaces (as the `finality` uint16 -> bytes4 change did), the OffRamp would call selectors the mock
///      does not implement. Pin the mirrors to the pinned chainlink-ccip interfaces.
contract CCVNoOpVerifierUnitTest is Test {
    function test_selectorsMatchPinnedCrossChainVerifierV1() public pure {
        assertEq(ICCVNoOpVerifierFork.verifyMessage.selector, ICrossChainVerifierV1.verifyMessage.selector);
        assertEq(ICCVNoOpVerifierFork.getFee.selector, ICrossChainVerifierV1.getFee.selector);
        assertEq(ICCVNoOpVerifierFork.forwardToVerifier.selector, ICrossChainVerifierV1.forwardToVerifier.selector);
    }

    function test_selectorsMatchPinnedCrossChainVerifierResolver() public pure {
        assertEq(
            ICCVNoOpVerifierFork.getInboundImplementation.selector,
            ICrossChainVerifierResolver.getInboundImplementation.selector
        );
        assertEq(
            ICCVNoOpVerifierFork.getOutboundImplementation.selector,
            ICrossChainVerifierResolver.getOutboundImplementation.selector
        );
    }
}
