// CCIP 1.6 wire formats for a single-message Solana-bound report: the execution report, its Merkle leaf, the
// commit report and the digest the OCR3 committee signs.
//
// Mirrors chainlink-ccip solana-v1.6.4, chains/solana/contracts/programs/ccip-offramp/src:
// `messages.rs` (Borsh layout), `instructions/v1/execute.rs` `hash` (leaf), `context.rs` `CommitInput`
// (commit report) and `instructions/v1/ocr3impl.rs` `hash` (signed digest). A tree of one message has the
// leaf as its root and an empty proof.

import { PublicKey } from "@solana/web3.js";
import { SigningKey, getBytes, keccak256 } from "ethers";

/** One entry of `Any2SVMRampMessage.token_amounts`. */
export interface TokenAmount16 {
  sourcePool: Uint8Array;
  destToken: PublicKey;
  /** Gas the source reserved for the destination pool call; the SVM OffRamp does not use it. */
  destGasAmount: number;
  extraData: Uint8Array;
  /** Source-token units. */
  amount: bigint;
}

export interface Message16 {
  messageId: Uint8Array;
  sourceChainSelector: bigint;
  destChainSelector: bigint;
  sequenceNumber: bigint;
  sender: Uint8Array;
  data: Uint8Array;
  computeUnits: number;
  writableBitmap: bigint;
  /** Receiver program followed by the message accounts, as the OffRamp hashes them. */
  receiverAndAccounts: PublicKey[];
  /** The onRamp bytes the source chain config holds. */
  onRamp: Uint8Array;
  /** Wallet that receives `tokenAmounts`. Default: none (the zero address, no tokens). */
  tokenReceiver?: PublicKey;
  tokenAmounts?: TokenAmount16[];
}

const u16le = (n: number) => { const b = Buffer.alloc(2); b.writeUInt16LE(n); return b; };
const u16be = (n: number) => { const b = Buffer.alloc(2); b.writeUInt16BE(n); return b; };
const u32le = (n: number) => { const b = Buffer.alloc(4); b.writeUInt32LE(n); return b; };
const u64le = (n: bigint) => { const b = Buffer.alloc(8); b.writeBigUInt64LE(n); return b; };
const u64be = (n: bigint) => { const b = Buffer.alloc(8); b.writeBigUInt64BE(n); return b; };
/** Borsh `Vec<u8>`. */
const vec = (bytes: Uint8Array) => Buffer.concat([u32le(bytes.length), bytes]);
const keccak = (...parts: Uint8Array[]) => Buffer.from(getBytes(keccak256(Buffer.concat(parts))));

/** Borsh `Vec<Any2SVMTokenAmount>`: the amount is a 32-byte little-endian `CrossChainAmount`. */
function tokenAmountsBorsh(tokens: TokenAmount16[] = []): Buffer {
  return Buffer.concat([
    u32le(tokens.length),
    ...tokens.map((t) => {
      const amount = Buffer.alloc(32);
      amount.writeBigUInt64LE(t.amount & 0xffffffffffffffffn, 0);
      amount.writeBigUInt64LE((t.amount >> 64n) & 0xffffffffffffffffn, 8);
      amount.writeBigUInt64LE((t.amount >> 128n) & 0xffffffffffffffffn, 16);
      amount.writeBigUInt64LE((t.amount >> 192n) & 0xffffffffffffffffn, 24);
      return Buffer.concat([vec(t.sourcePool), t.destToken.toBuffer(), u32le(t.destGasAmount), vec(t.extraData), amount]);
    }),
  ]);
}

/** Borsh `Any2SVMRampExtraArgs`. */
const extraArgs = (m: Message16) => Buffer.concat([u32le(m.computeUnits), u64le(m.writableBitmap)]);

/**
 * `keccak256` over the same fields, in the same order, as `execute.rs::hash`. Without tokens the token receiver is
 * the zero address and `token_amounts` is empty.
 */
export function leafHash(m: Message16): Buffer {
  return keccak(
    Buffer.alloc(32), // leaf domain separator
    Buffer.from("Any2SVMMessageHashV1"),
    u64be(m.sourceChainSelector),
    u64be(m.destChainSelector),
    u16be(m.onRamp.length),
    m.onRamp,
    m.messageId,
    (m.tokenReceiver ?? PublicKey.default).toBuffer(),
    u64be(m.sequenceNumber),
    extraArgs(m),
    u64be(0n), // nonce: the OffRamp requires 0
    u16be(m.sender.length),
    m.sender,
    u16be(m.data.length),
    m.data,
    tokenAmountsBorsh(m.tokenAmounts),
    ...m.receiverAndAccounts.map((key) => key.toBuffer()),
  );
}

/** Borsh `ExecutionReportSingleChain` with an empty proof. */
export function encodeExecutionReport(m: Message16): Buffer {
  return Buffer.concat([
    u64le(m.sourceChainSelector),
    // Any2SVMRampMessage: header, sender, data, token_receiver, token_amounts, extra_args
    Buffer.from(m.messageId),
    u64le(m.sourceChainSelector),
    u64le(m.destChainSelector),
    u64le(m.sequenceNumber),
    u64le(0n),
    vec(m.sender),
    vec(m.data),
    (m.tokenReceiver ?? PublicKey.default).toBuffer(),
    tokenAmountsBorsh(m.tokenAmounts),
    extraArgs(m),
    // offchain_token_data: one empty entry per token (a BurnMint pool needs no attestation)
    u32le((m.tokenAmounts ?? []).length),
    ...(m.tokenAmounts ?? []).map(() => vec(Buffer.alloc(0))),
    u32le(0), // proofs
  ]);
}

/** Borsh `CommitInput` for one Merkle root: no price updates, no RMN signatures. */
export function encodeCommitReport(m: Message16, root: Uint8Array): Buffer {
  return Buffer.concat([
    u32le(0), // token_price_updates
    u32le(0), // gas_price_updates
    Buffer.from([1]), // merkle_root: Some
    u64le(m.sourceChainSelector),
    vec(m.onRamp),
    u64le(m.sequenceNumber), // min
    u64le(m.sequenceNumber), // max
    root,
    u32le(0), // rmn_signatures
  ]);
}

/** The `report_context_byte_words` argument: the config digest, then 24 zero bytes and the sequence number. */
export function reportContext(configDigest: Uint8Array, sequenceNumber: bigint): [number[], number[]] {
  return [[...configDigest], [...Buffer.concat([Buffer.alloc(24), u64be(sequenceNumber)])]];
}

export interface CommitSignatures {
  rs: number[][];
  ss: number[][];
  /** 32 bytes: the recovery id (0 or 1) of each signature, zero padded. */
  rawVs: number[];
}

/**
 * Signs `ocr3impl.rs::hash` = keccak256(u16 LE report length | report | 64-byte report context) with each key.
 * ethers produces canonical low-s signatures; the program wants the recovery id as 0 or 1, not 27 or 28.
 */
export function signCommit(report: Buffer, context: [number[], number[]], keys: Uint8Array[]): CommitSignatures {
  const digest = keccak256(Buffer.concat([u16le(report.length), report, Buffer.from(context.flat())]));
  const signatures = keys.map((key) => new SigningKey(Buffer.from(key)).sign(digest));
  const rawVs = Buffer.alloc(32);
  signatures.forEach((signature, i) => rawVs.writeUInt8(signature.v - 27, i));
  return {
    rs: signatures.map((s) => [...getBytes(s.r)]),
    ss: signatures.map((s) => [...getBytes(s.s)]),
    rawVs: [...rawVs],
  };
}

/** Id of a locally delivered 1.6 message. The OffRamp treats the id as opaque, so any unique 32 bytes work. */
export function localMessageId(m: Pick<Message16, "sourceChainSelector" | "destChainSelector" | "sequenceNumber" | "sender" | "data" | "onRamp">, receiver: PublicKey): Buffer {
  return keccak(
    Buffer.from("chainlink-local-svm-1.6:message"),
    u64be(m.sourceChainSelector),
    u64be(m.destChainSelector),
    u64be(m.sequenceNumber),
    m.onRamp,
    m.sender,
    receiver.toBuffer(),
    m.data,
  );
}
