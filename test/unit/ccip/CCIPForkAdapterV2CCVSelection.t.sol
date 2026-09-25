// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {CCIPForkAdapterV2} from "../../../src/ccip/adapters/CCIPForkAdapterV2.sol";

/// @dev CCV selection must satisfy OffRamp 2.0 `_ensureCCVQuorumIsReached`: every required CCV, plus `optionalThreshold`
///      of the optional CCVs (an optional CCV that is also required counts, because it is present in `ccvs`).
contract CCIPForkAdapterV2CCVSelectionTest is Test {
    address internal constant A = address(0xA);
    address internal constant B = address(0xB);
    address internal constant C = address(0xC);
    address internal constant D = address(0xD);

    error RequiredCCVMissing(address requiredCCV);
    error OptionalCCVQuorumNotReached(uint256 wanted, uint256 got);

    /// @dev Line-for-line port of production `OffRamp._ensureCCVQuorumIsReached` (contracts-ccip-v2.0.0), minus the
    ///      data-index bookkeeping. Reverts exactly where the OffRamp reverts.
    function productionQuorumCheck(
        address[] memory requiredCCV,
        address[] memory optionalCCVs,
        uint8 optionalThreshold,
        address[] memory ccvs
    ) public pure {
        for (uint256 i = 0; i < requiredCCV.length; ++i) {
            bool found = false;
            for (uint256 j = 0; j < ccvs.length; ++j) {
                if (ccvs[j] == requiredCCV[i]) {
                    found = true;
                    break;
                }
            }
            if (!found) revert RequiredCCVMissing(requiredCCV[i]);
        }
        uint256 optionalCCVsToFind = optionalThreshold;
        for (uint256 i = 0; i < optionalCCVs.length; ++i) {
            for (uint256 j = 0; j < ccvs.length && optionalCCVsToFind > 0; ++j) {
                if (ccvs[j] == optionalCCVs[i]) {
                    optionalCCVsToFind--;
                    break;
                }
            }
        }
        if (optionalCCVsToFind > 0) {
            revert OptionalCCVQuorumNotReached(optionalThreshold, optionalThreshold - optionalCCVsToFind);
        }
    }

    function _list(address a) internal pure returns (address[] memory l) {
        l = new address[](1);
        l[0] = a;
    }

    function _list(address a, address b) internal pure returns (address[] memory l) {
        l = new address[](2);
        l[0] = a;
        l[1] = b;
    }

    function _list(address a, address b, address c) internal pure returns (address[] memory l) {
        l = new address[](3);
        l[0] = a;
        l[1] = b;
        l[2] = c;
    }

    function _assertSelection(
        address[] memory required,
        address[] memory optional,
        uint8 threshold,
        address[] memory expected
    ) internal view {
        address[] memory ccvs = CCIPForkAdapterV2.selectCCVs(required, optional, threshold);
        assertEq(ccvs, expected);
        this.productionQuorumCheck(required, optional, threshold, ccvs);
    }

    function test_requiredOnly() public view {
        _assertSelection(_list(A, B), new address[](0), 0, _list(A, B));
    }

    function test_optionalOnly_thresholds() public view {
        _assertSelection(new address[](0), _list(B, C), 0, new address[](0));
        _assertSelection(new address[](0), _list(B, C), 1, _list(B));
        _assertSelection(new address[](0), _list(B, C), 2, _list(B, C));
    }

    /// @dev The review repro: required=[A], optional=[B,C], threshold=1 needs A plus one of B or C.
    function test_requiredPlusOptional_thresholds() public view {
        _assertSelection(_list(A), _list(B, C), 0, _list(A));
        _assertSelection(_list(A), _list(B, C), 1, _list(A, B));
        _assertSelection(_list(A), _list(B, C), 2, _list(A, B, C));
    }

    /// @dev An optional CCV that is also required already counts toward the threshold.
    function test_overlap_optionalAlsoRequired() public view {
        _assertSelection(_list(A, B), _list(B, C), 1, _list(A, B));
        _assertSelection(_list(A, B), _list(B, C), 2, _list(A, B, C));
    }

    function test_duplicateRequired_deduplicated() public view {
        _assertSelection(_list(A, A, B), _list(C), 1, _list(A, B, C));
    }

    /// @dev Property: for any lists drawn from 4 CCVs (overlap and duplicate required CCVs included) and any valid threshold, the
    ///      selection passes the production quorum check, contains no duplicates, and adds no unneeded optional CCV.
    function testFuzz_selectionSatisfiesProductionQuorum(uint256 seed) public view {
        address[4] memory pool = [A, B, C, D];
        uint256 requiredLength = seed % 4;
        uint256 optionalLength = (seed >> 8) % 5; // 0..4 unique optional CCVs
        address[] memory required = new address[](requiredLength);
        address[] memory optional = new address[](optionalLength);
        for (uint256 i; i < requiredLength; ++i) {
            required[i] = pool[(seed >> (16 + 2 * i)) % 4];
        }
        // Optional CCVs are unique, as in production: `OffRamp._getCCVsFromReceiver` rejects duplicate optional CCVs
        // (`CCVConfigValidation._assertNoDuplicates`) before the quorum check. Required CCVs may repeat.
        uint256 start = (seed >> 32) % 4;
        for (uint256 i; i < optionalLength; ++i) {
            optional[i] = pool[(start + i) % 4];
        }
        uint8 threshold = uint8((seed >> 64) % (optionalLength + 1));

        address[] memory ccvs = CCIPForkAdapterV2.selectCCVs(required, optional, threshold);
        this.productionQuorumCheck(required, optional, threshold, ccvs);

        for (uint256 i; i < ccvs.length; ++i) {
            for (uint256 j = i + 1; j < ccvs.length; ++j) {
                assertTrue(ccvs[i] != ccvs[j], "duplicate CCV selected");
            }
        }
        // Minimality: removing any optional-only CCV must break the quorum (no extra verifier is ever required).
        for (uint256 k; k < ccvs.length; ++k) {
            bool isRequired;
            for (uint256 r; r < required.length; ++r) {
                if (required[r] == ccvs[k]) isRequired = true;
            }
            if (isRequired) continue;
            address[] memory reduced = new address[](ccvs.length - 1);
            uint256 n;
            for (uint256 i; i < ccvs.length; ++i) {
                if (i != k) reduced[n++] = ccvs[i];
            }
            try this.productionQuorumCheck(required, optional, threshold, reduced) {
                revert("selection contains an unneeded optional CCV");
            } catch {}
        }
    }
}
