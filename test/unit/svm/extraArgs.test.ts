import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { PublicKey } from "@solana/web3.js";
import { svmExtraArgs } from "../../../scripts/svm/extraArgs.ts";

function accountBytes(last: number[]): Uint8Array {
  const bytes = new Uint8Array(32);
  bytes.set(last, 32 - last.length);
  return bytes;
}

describe("svmExtraArgs", () => {
  // Produced by `Client._svmArgsToBytes` in a Foundry test (forge-std console.logBytes), with
  // computeUnits 200000, bitmap 5, out-of-order true, tokenReceiver 0x77 and accounts 0x11, 0xabcdef.
  const SOLIDITY_VECTOR =
    "0x1f3b3aba" +
    "0000000000000000000000000000000000000000000000000000000000000020" +
    "0000000000000000000000000000000000000000000000000000000000030d40" +
    "0000000000000000000000000000000000000000000000000000000000000005" +
    "0000000000000000000000000000000000000000000000000000000000000001" +
    "0000000000000000000000000000000000000000000000000000000000000077" +
    "00000000000000000000000000000000000000000000000000000000000000a0" +
    "0000000000000000000000000000000000000000000000000000000000000002" +
    "0000000000000000000000000000000000000000000000000000000000000011" +
    "0000000000000000000000000000000000000000000000000000000000abcdef";

  it("matches the bytes Solidity's Client._svmArgsToBytes produces", () => {
    const encoded = svmExtraArgs({
      computeUnits: 200_000,
      accounts: [new PublicKey(accountBytes([0x11])), accountBytes([0xab, 0xcd, 0xef])],
      writableBitmap: 5n,
      tokenReceiver: accountBytes([0x77]),
    });
    assert.equal(encoded, SOLIDITY_VECTOR);
  });

  it("matches the Solidity bytes for the minimal args, with out-of-order execution off", () => {
    const expected =
      "0x1f3b3aba" +
      "0000000000000000000000000000000000000000000000000000000000000020" +
      "0000000000000000000000000000000000000000000000000000000000000001" +
      "0000000000000000000000000000000000000000000000000000000000000000".repeat(3) +
      "00000000000000000000000000000000000000000000000000000000000000a0" +
      "0000000000000000000000000000000000000000000000000000000000000000";
    const encoded = svmExtraArgs({ computeUnits: 1, accounts: [], writableBitmap: 0n, allowOutOfOrderExecution: false });
    assert.equal(encoded, expected);
  });

  it("defaults to out-of-order execution and a zero token receiver", () => {
    const encoded = svmExtraArgs({ computeUnits: 1, accounts: [], writableBitmap: 0n });
    assert.equal(encoded.slice(2 + 8 + 64 * 3, 2 + 8 + 64 * 4), "0".repeat(63) + "1");
    assert.equal(encoded.slice(2 + 8 + 64 * 4, 2 + 8 + 64 * 5), "0".repeat(64));
  });

  it("rejects what the local router rejects, with the router's error names", () => {
    assert.throws(() => svmExtraArgs({ computeUnits: 3_000_001, accounts: [], writableBitmap: 0n }), /MessageComputeUnitLimitTooHigh/);
    assert.doesNotThrow(() => svmExtraArgs({ computeUnits: 3_000_000, accounts: [], writableBitmap: 0n }));
    const tooMany = Array.from({ length: 256 }, () => new Uint8Array(32));
    assert.throws(() => svmExtraArgs({ computeUnits: 1, accounts: tooMany, writableBitmap: 0n }), /InvalidDataLength/);
    assert.doesNotThrow(() => svmExtraArgs({ computeUnits: 1, accounts: tooMany.slice(0, 255), writableBitmap: 0n }));
  });

  it("does not check the bitmap against the accounts, as the router does not", () => {
    assert.doesNotThrow(() => svmExtraArgs({ computeUnits: 1, accounts: [], writableBitmap: 0xffn }));
  });

  it("rejects values that cannot be encoded", () => {
    assert.throws(() => svmExtraArgs({ computeUnits: 1.5, accounts: [], writableBitmap: 0n }), /computeUnits/);
    assert.throws(() => svmExtraArgs({ computeUnits: 1, accounts: [new Uint8Array(31)], writableBitmap: 0n }), /32 bytes/);
    assert.throws(() => svmExtraArgs({ computeUnits: 1, accounts: [], writableBitmap: 1n << 64n }), /writableBitmap/);
  });
});
