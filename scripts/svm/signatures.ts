// Local committee keys and the CommitteeVerifier results blob.
//
// Ported in part from the prototype by Stefano Magini (magiodev-cll/chainlink-local, feat/svm-local,
// src/ccip-svm/src/codec.ts): `signVerifierResults`, `committeeKey` and `addressOf`. The prototype's
// PLAN.md found that ethers' `SigningKey.sign()` works while `@noble/curves` recovered signatures were
// rejected on chain, so ethers is kept.

import { SigningKey, computeAddress, getBytes, keccak256 } from "ethers";
import { CCV_VERSION_TAG } from "./constants.ts";

const SECP256K1_N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;

/** Deterministic local committee key: the same index always yields the same key. */
export function committeeKey(index: number): Uint8Array {
  return getBytes(keccak256(Buffer.from(`chainlink-local-svm:${index}`)));
}

/** Lower-case `0x` Ethereum address of a private key. */
export function addressOf(privateKey: Uint8Array): string {
  return computeAddress(new SigningKey(Buffer.from(privateKey))).toLowerCase();
}

/** The verifier requires signer addresses in ascending order. */
export function sortedCommittee(size: number): Uint8Array[] {
  return Array.from({ length: size }, (_, i) => committeeKey(i)).sort((a, b) =>
    addressOf(a).localeCompare(addressOf(b)),
  );
}

/** `keccak256(version_tag || message_id)`, the hash every committee member signs. */
export function signedHash(messageIdBytes: Uint8Array): string {
  return keccak256(Buffer.concat([CCV_VERSION_TAG, messageIdBytes]));
}

/** Compact 64-byte signature of `hash` whose recovery id is 0, as the on-chain verifier assumes. */
export function signWithRecoveryIdZero(privateKey: Uint8Array, hash: string): Buffer {
  const signature = new SigningKey(Buffer.from(privateKey)).sign(hash);
  // v = 28 means recovery id 1. Replacing s with n - s flips the parity, giving recovery id 0.
  const s = signature.v === 28 ? SECP256K1_N - BigInt(signature.s) : BigInt(signature.s);
  return Buffer.concat([
    Buffer.from(signature.r.slice(2), "hex"),
    Buffer.from(s.toString(16).padStart(64, "0"), "hex"),
  ]);
}

/**
 * CommitteeVerifier verifier results: `u8[4] version_tag | u16 BE signatures_len | N x 64-byte
 * signatures`, signed by the first `threshold` keys.
 */
export function signVerifierResults(messageIdBytes: Uint8Array, privateKeys: Uint8Array[], threshold: number): Buffer {
  if (privateKeys.length < threshold) throw new Error(`need ${threshold} signers, have ${privateKeys.length}`);
  const hash = signedHash(messageIdBytes);
  const signatures = Buffer.concat(privateKeys.slice(0, threshold).map((key) => signWithRecoveryIdZero(key, hash)));
  const length = Buffer.alloc(2);
  length.writeUInt16BE(signatures.length);
  return Buffer.concat([CCV_VERSION_TAG, length, signatures]);
}
