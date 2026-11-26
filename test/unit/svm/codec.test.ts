import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { PublicKey } from "@solana/web3.js";
import { decodeMessage, decodeTokenTransfer, encodeDestBlob, encodeMessage, encodeTokenTransfer, messageId, type MessageV1 } from "../../../scripts/svm/codec.ts";

const message: MessageV1 = {
  sourceChainSelector: 16015286601757825753n,
  destChainSelector: 16423721717087811551n,
  messageNumber: 7n,
  executionGasLimit: 200_000,
  ccipReceiveGasLimit: 100_000,
  finalityFlags: 3,
  finalityBlockDepth: 12,
  ccvAndExecutorHash: new Uint8Array(32).fill(9),
  onRampAddress: new Uint8Array(20).fill(1),
  offRampAddress: new Uint8Array(32).fill(2),
  sender: new Uint8Array(20).fill(3),
  receiver: new Uint8Array(32).fill(4),
  destBlob: Uint8Array.from([0xaa, 0xbb]),
  tokenTransfer: new Uint8Array(0),
  data: Buffer.from("hello"),
};

// Layout written out by hand from the field order (all integers big-endian), so the test does not
// depend on the encoder it checks.
const EXPECTED_HEX =
  "01" + // version
  "de41ba4fc9d91ad9" + // source selector
  "e3ecc7e294e337df" + // dest selector
  "0000000000000007" + // message number
  "00030d40" + // execution gas limit
  "000186a0" + // receive gas limit
  "0003" + // finality flags
  "000c" + // finality block depth
  "09".repeat(32) + // ccv and executor hash
  "14" + "01".repeat(20) + // on ramp
  "20" + "02".repeat(32) + // off ramp
  "14" + "03".repeat(20) + // sender
  "20" + "04".repeat(32) + // receiver
  "0002aabb" + // dest blob
  "0000" + // token transfer
  "000568656c6c6f"; // data

describe("MessageV1 codec", () => {
  it("encodes the documented big-endian layout", () => {
    assert.equal(encodeMessage(message).toString("hex"), EXPECTED_HEX);
  });

  it("round-trips through decode", () => {
    assert.deepEqual(decodeMessage(encodeMessage(message)), {
      ...message,
      destBlob: Uint8Array.from(message.destBlob),
      data: Uint8Array.from(message.data),
    });
  });

  it("hashes the encoded bytes to a fixed message id", () => {
    // keccak256 of EXPECTED_HEX, computed independently with `cast keccak`.
    assert.equal(messageId(Buffer.from(EXPECTED_HEX, "hex")).toString("hex"), FIXED_MESSAGE_ID);
  });

  it("rejects truncated, trailing and unversioned input", () => {
    const encoded = encodeMessage(message);
    assert.throws(() => decodeMessage(encoded.subarray(0, encoded.length - 1)), /truncated/);
    assert.throws(() => decodeMessage(Buffer.concat([encoded, Buffer.from([0])])), /trailing/);
    assert.throws(() => decodeMessage(Buffer.concat([Buffer.from([2]), encoded.subarray(1)])), /version/);
  });

  it("encodes the dest blob as tag, mode, bitmap, count, accounts", () => {
    const account = new PublicKey(new Uint8Array(32).fill(5));
    assert.equal(
      encodeDestBlob({ accounts: [account], accountIsWritableBitmap: 1n }).toString("hex"),
      "1a2b3c4d" + "00" + "0000000000000001" + "01" + "05".repeat(32),
    );
  });
});

describe("TokenTransferV1 codec", () => {
  const transfer = {
    amount: 1_500_000_000n,
    sourcePool: new Uint8Array(20).fill(1),
    sourceToken: new Uint8Array(20).fill(2),
    destToken: new PublicKey(new Uint8Array(32).fill(3)),
    tokenReceiver: new PublicKey(new Uint8Array(32).fill(4)),
    extraData: Uint8Array.from({ length: 32 }, (_, i) => (i === 31 ? 9 : 0)),
  };

  it("decodes what encodeTokenTransfer encodes", () => {
    const decoded = decodeTokenTransfer(encodeTokenTransfer(transfer));
    assert.equal(decoded.amount, transfer.amount);
    assert.deepEqual(decoded.sourcePool, transfer.sourcePool);
    assert.deepEqual(decoded.sourceToken, transfer.sourceToken);
    assert.deepEqual(decoded.destToken, transfer.destToken.toBytes());
    assert.deepEqual(decoded.tokenReceiver, transfer.tokenReceiver.toBytes());
    assert.deepEqual(decoded.extraData, transfer.extraData);
  });

  it("rejects an unknown version, truncation and trailing bytes", () => {
    const encoded = encodeTokenTransfer(transfer);
    assert.throws(() => decodeTokenTransfer(encoded.subarray(0, encoded.length - 1)), /truncated/);
    assert.throws(() => decodeTokenTransfer(Buffer.concat([encoded, Buffer.from([0])])), /trailing/);
    assert.throws(() => decodeTokenTransfer(Buffer.concat([Buffer.from([2]), encoded.subarray(1)])), /version/);
  });
});

const FIXED_MESSAGE_ID = "3595c5d4a05b8f264821323335eae8b4a859e4d6486dfd904dccc2396cefed48";
