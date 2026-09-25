// Offline unit tests for the JS helper `scripts/CCIPLocalSimulatorFork.js`. No RPC or Hardhat network needed:
// `_selectCCVs` is a pure function, and the hardhat-ethers guard only needs a plain object as `connection`.
// Run with `npm run js-unit-test` (part of `npm test`).
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { ethers } from "ethers";

import {
    _selectCCVs,
    _gasLimitFromExtraArgs,
    _decodeEVMAddress,
    _stampedOffRamp,
    getCCIPMessages,
} from "../../../scripts/CCIPLocalSimulatorFork.js";

const connection = { ethers };

const A = "0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
const B = "0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";
const C = "0xCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC";
const D = "0xDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD";

describe("_selectCCVs", () => {
    it("required-only: returns every required CCV regardless of threshold", () => {
        assert.deepEqual(_selectCCVs([A, B], [], 0), [A, B]);
    });

    it("optional-only, threshold 0: no optional CCVs are added", () => {
        assert.deepEqual(_selectCCVs([], [A, B, C], 0), []);
    });

    it("optional-only, threshold 1: the first optional CCV is added", () => {
        assert.deepEqual(_selectCCVs([], [A, B, C], 1), [A]);
    });

    it("optional-only, threshold equal to all optionals: every optional CCV is added", () => {
        assert.deepEqual(_selectCCVs([], [A, B, C], 3), [A, B, C]);
    });

    it("required + optional, threshold 0: only the required CCVs are returned", () => {
        assert.deepEqual(_selectCCVs([A], [B, C], 0), [A]);
    });

    it("required + optional, threshold 1: required CCVs plus one optional CCV", () => {
        assert.deepEqual(_selectCCVs([A], [B, C], 1), [A, B]);
    });

    it("required + optional, threshold equal to all optionals: required plus every optional CCV", () => {
        assert.deepEqual(_selectCCVs([A], [B, C], 2), [A, B, C]);
    });

    it("overlap: an optional CCV that is also required counts toward the threshold without being re-added", () => {
        // required=[A], optional=[A, B], threshold=1 -> A (already required) satisfies the threshold; B is not needed.
        assert.deepEqual(_selectCCVs([A], [A, B], 1), [A]);
    });

    it("overlap: once the overlapping CCV satisfies the threshold, later optionals are not pulled in", () => {
        assert.deepEqual(_selectCCVs([A, B], [B, C, D], 1), [A, B]);
    });

    it("overlap: threshold higher than what the overlap covers still pulls in the remaining optionals in order", () => {
        // required=[A], optional=[A, B, C], threshold=2 -> A covers 1, then B is added to cover the 2nd.
        assert.deepEqual(_selectCCVs([A], [A, B, C], 2), [A, B]);
    });

    it("overlap later in the optional list: no unneeded optional CCV is added (matches the Solidity selection)", () => {
        // required=[C], optional=[B, C], threshold=1: C is already present and satisfies the threshold, so B is not needed.
        assert.deepEqual(_selectCCVs([C], [B, C], 1), [C]);
    });

    it("duplicates in required: deduplicates keeping the first occurrence order", () => {
        assert.deepEqual(_selectCCVs([A, B, A], [], 0), [A, B]);
    });

    it("duplicates in required do not throw off optional threshold accounting", () => {
        assert.deepEqual(_selectCCVs([A, A, B], [C], 1), [A, B, C]);
    });
});

describe("hardhat-ethers guard", () => {
    it("getCCIPMessages throws a clear error naming @nomicfoundation/hardhat-ethers when connection.ethers is missing", () => {
        assert.throws(() => getCCIPMessages({}, { logs: [] }), (err) => {
            assert.match(err.message, /@nomicfoundation\/hardhat-ethers/);
            return true;
        });
    });
});

describe("_gasLimitFromExtraArgs", () => {
    const GENERIC_EXTRA_ARGS_V2_TAG = "0x181dcf10";
    const EVM_EXTRA_ARGS_V1_TAG = "0x97a657c9";
    const DEFAULT_GAS_LIMIT = 200_000n;
    const coder = ethers.AbiCoder.defaultAbiCoder();

    it("empty extraArgs: returns the default gas limit", () => {
        assert.equal(_gasLimitFromExtraArgs(connection, "0x"), DEFAULT_GAS_LIMIT);
    });

    it("EVMExtraArgsV1 tag (0x97a657c9): decodes the packed uint256 gas limit", () => {
        const body = coder.encode(["uint256"], [123456n]);
        const extraArgs = ethers.concat([EVM_EXTRA_ARGS_V1_TAG, body]);
        assert.equal(_gasLimitFromExtraArgs(connection, extraArgs), 123456n);
    });

    it("GenericExtraArgsV2 tag (0x181dcf10): decodes gasLimit from the (gasLimit, allowOutOfOrderExecution) tuple", () => {
        const body = coder.encode(["tuple(uint256 gasLimit, bool allowOutOfOrderExecution)"], [[654321n, true]]);
        const extraArgs = ethers.concat([GENERIC_EXTRA_ARGS_V2_TAG, body]);
        assert.equal(_gasLimitFromExtraArgs(connection, extraArgs), 654321n);
    });

    it("unknown 4-byte tag: throws a clear error naming the tag", () => {
        const extraArgs = ethers.concat(["0xdeadbeef", coder.encode(["uint256"], [1n])]);
        assert.throws(() => _gasLimitFromExtraArgs(connection, extraArgs), /Unsupported 1\.6 extraArgs tag: 0xdeadbeef/);
    });
});

describe("_decodeEVMAddress", () => {
    const address = "0x1234567890123456789012345678901234567890";

    it("32-byte ABI-encoded address: decodes to the checksummed address", () => {
        const encoded = ethers.AbiCoder.defaultAbiCoder().encode(["address"], [address]);
        assert.equal(_decodeEVMAddress(connection, encoded), address);
    });

    it("20-byte raw address: decodes to the checksummed address", () => {
        assert.equal(_decodeEVMAddress(connection, address), address);
    });

    it("invalid length (e.g. 19 bytes): throws a clear error", () => {
        const tooShort = ethers.dataSlice(address, 0, 19);
        assert.throws(() => _decodeEVMAddress(connection, tooShort), /Invalid EVM address encoding/);
    });

    it("invalid length (e.g. empty): throws a clear error", () => {
        assert.throws(() => _decodeEVMAddress(connection, "0x"), /Invalid EVM address encoding/);
    });
});

describe("_stampedOffRamp", () => {
    // Builds a minimal well-formed MessageV1 header (69 bytes) followed by onRampLen/onRamp/offRampLen/offRamp, per
    // `MessageV1Codec._encodeMessageV1`'s documented layout — verified against the real codec's output in
    // `CCIPLocalSimulatorForkRoutingHelper.unit.test.js`.
    function header() {
        return ethers.solidityPacked(
            ["uint8", "uint64", "uint64", "uint64", "uint32", "uint32", "bytes4", "bytes32"],
            [1, 1n, 2n, 3n, 200000, 100000, "0x00000000", ethers.ZeroHash]
        );
    }

    it("well-formed 20-byte offRampAddress: returns the checksummed address", () => {
        const onRamp = ethers.AbiCoder.defaultAbiCoder().encode(["address"], ["0x1111111111111111111111111111111111111111"]);
        const offRamp = "0x2222222222222222222222222222222222222222";
        const encoded = ethers.solidityPacked(
            ["bytes", "uint8", "bytes", "uint8", "bytes"],
            [header(), 32, onRamp, 20, offRamp]
        );
        assert.equal(_stampedOffRamp(connection, encoded), ethers.getAddress(offRamp));
    });

    it("offRampAddress of a non-20-byte length (e.g. a non-EVM chain): returns null", () => {
        const onRamp = ethers.AbiCoder.defaultAbiCoder().encode(["address"], ["0x1111111111111111111111111111111111111111"]);
        const offRamp = "0x22222222"; // 4 bytes
        const encoded = ethers.solidityPacked(
            ["bytes", "uint8", "bytes", "uint8", "bytes"],
            [header(), 32, onRamp, 4, offRamp]
        );
        assert.equal(_stampedOffRamp(connection, encoded), null);
    });

    it("message shorter than the fixed 69-byte header: returns null", () => {
        assert.equal(_stampedOffRamp(connection, ethers.dataSlice(header(), 0, 40)), null);
    });

    it("onRampLen makes the offRampLen byte fall outside the buffer: returns null (bounds-checked)", () => {
        // onRampLen claims 200 bytes, but there is nothing after the header: reading the offRampLen byte would
        // overrun the buffer.
        const encoded = ethers.solidityPacked(["bytes", "uint8"], [header(), 200]);
        assert.equal(_stampedOffRamp(connection, encoded), null);
    });

    it("offRampLen makes the address content fall outside the buffer: returns null (bounds-checked)", () => {
        const onRamp = ethers.AbiCoder.defaultAbiCoder().encode(["address"], ["0x1111111111111111111111111111111111111111"]);
        // offRampLen claims 20 bytes, but only 5 are actually present.
        const encoded = ethers.solidityPacked(
            ["bytes", "uint8", "bytes", "uint8", "bytes"],
            [header(), 32, onRamp, 20, "0x1122334455"]
        );
        assert.equal(_stampedOffRamp(connection, encoded), null);
    });

    it("malformed / garbage bytes: returns null instead of throwing", () => {
        assert.equal(_stampedOffRamp(connection, "0x"), null);
    });
});
