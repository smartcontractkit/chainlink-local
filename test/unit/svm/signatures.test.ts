import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { Signature, SigningKey, recoverAddress } from "ethers";
import {
  addressOf,
  committeeKey,
  signVerifierResults,
  signWithRecoveryIdZero,
  signedHash,
  sortedCommittee,
} from "../../../scripts/svm/signatures.ts";

const N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;

/**
 * Recovers the signer of a compact signature interpreted with recovery id 0, as the on-chain
 * verifier does. ethers only accepts low-s signatures, so a high s is mapped to the equivalent
 * (n - s, recovery id 1) pair, which has the same signer.
 */
function recoverWithIdZero(compact: Uint8Array, hash: string): string {
  const s = BigInt("0x" + Buffer.from(compact.subarray(32, 64)).toString("hex"));
  const high = s > N / 2n;
  const signature = Signature.from({
    r: "0x" + Buffer.from(compact.subarray(0, 32)).toString("hex"),
    s: "0x" + (high ? N - s : s).toString(16).padStart(64, "0"),
    v: high ? 28 : 27,
  });
  return recoverAddress(hash, signature).toLowerCase();
}

describe("committee signatures", () => {
  it("recovers to the committee address with recovery id 0, also for signatures that needed normalising", () => {
    const hash = signedHash(Buffer.alloc(32, 0xab));
    let normalised = 0;
    for (let index = 0; index < 16; index++) {
      const key = committeeKey(index);
      const natural = new SigningKey(Buffer.from(key)).sign(hash);
      if (natural.v === 28) normalised++;
      assert.equal(recoverWithIdZero(signWithRecoveryIdZero(key, hash), hash), addressOf(key), `key ${index}`);
    }
    // A vector with natural v = 28 must exist among the 16 keys, or this test proves nothing.
    assert.ok(normalised > 0, "no key needed normalising; widen the key range");
  });

  it("lays out the verifier results as tag, big-endian length, signatures", () => {
    const id = Buffer.alloc(32, 1);
    const results = signVerifierResults(id, sortedCommittee(8), 2);
    assert.equal(results.subarray(0, 4).toString("hex"), "e9a05a20");
    assert.equal(results.readUInt16BE(4), 128);
    assert.equal(results.length, 4 + 2 + 128);
    const addresses = [0, 1].map((i) => recoverWithIdZero(results.subarray(6 + 64 * i, 70 + 64 * i), signedHash(id)));
    assert.deepEqual(addresses, sortedCommittee(8).slice(0, 2).map(addressOf));
  });

  it("refuses a threshold larger than the committee", () => {
    assert.throws(() => signVerifierResults(Buffer.alloc(32), [committeeKey(0)], 2), /need 2 signers/);
  });

  it("derives the same committee every time, in ascending address order", () => {
    const addresses = sortedCommittee(8).map(addressOf);
    assert.deepEqual(addresses, [...addresses].sort());
    assert.deepEqual(addresses, sortedCommittee(8).map(addressOf));
  });
});
