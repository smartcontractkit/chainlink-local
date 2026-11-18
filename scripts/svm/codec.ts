// The CCIP 2.0 `MessageV1` wire format: a custom versioned big-endian codec, not Borsh.
//
// Ported in part from the prototype by Stefano Magini (magiodev-cll/chainlink-local, feat/svm-local,
// src/ccip-svm/src/codec.ts): `encodeMessage`, `decodeMessage`, `messageId`, `encodeDestBlob` and the
// length-prefix helpers. Token transfers are out of scope here: the field is carried as raw bytes.

import { PublicKey } from "@solana/web3.js";
import { getBytes, keccak256 } from "ethers";

export interface MessageV1 {
  sourceChainSelector: bigint;
  destChainSelector: bigint;
  messageNumber: bigint;
  executionGasLimit: number;
  ccipReceiveGasLimit: number;
  finalityFlags?: number;
  finalityBlockDepth?: number;
  ccvAndExecutorHash?: Uint8Array;
  onRampAddress: Uint8Array;
  offRampAddress: Uint8Array;
  sender: Uint8Array;
  receiver: Uint8Array;
  destBlob: Uint8Array;
  /** Encoded TokenTransferV1, empty for a data-only message. */
  tokenTransfer?: Uint8Array;
  data: Uint8Array;
}

export type DecodedMessage = Required<MessageV1>;

const MESSAGE_V1_VERSION = 1;

function be(bytes: number, write: (buf: Buffer) => void): Buffer {
  const buf = Buffer.alloc(bytes);
  write(buf);
  return buf;
}
const beU64 = (n: bigint) => be(8, (b) => b.writeBigUInt64BE(n));
const beU32 = (n: number) => be(4, (b) => b.writeUInt32BE(n));
const beU16 = (n: number) => be(2, (b) => b.writeUInt16BE(n));

function lenU8(value: Uint8Array): Buffer {
  if (value.length > 0xff) throw new Error(`field of ${value.length} bytes does not fit a u8 length prefix`);
  return Buffer.concat([Buffer.from([value.length]), value]);
}
function lenU16(value: Uint8Array): Buffer {
  if (value.length > 0xffff) throw new Error(`field of ${value.length} bytes does not fit a u16 length prefix`);
  return Buffer.concat([beU16(value.length), value]);
}

export function encodeMessage(message: MessageV1): Buffer {
  const ccvAndExecutorHash = message.ccvAndExecutorHash ?? new Uint8Array(32);
  if (ccvAndExecutorHash.length !== 32) throw new Error("ccvAndExecutorHash must be 32 bytes");
  return Buffer.concat([
    Buffer.from([MESSAGE_V1_VERSION]),
    beU64(message.sourceChainSelector),
    beU64(message.destChainSelector),
    beU64(message.messageNumber),
    beU32(message.executionGasLimit),
    beU32(message.ccipReceiveGasLimit),
    beU16(message.finalityFlags ?? 0),
    beU16(message.finalityBlockDepth ?? 0),
    ccvAndExecutorHash,
    lenU8(message.onRampAddress),
    lenU8(message.offRampAddress),
    lenU8(message.sender),
    lenU8(message.receiver),
    lenU16(message.destBlob),
    lenU16(message.tokenTransfer ?? new Uint8Array(0)),
    lenU16(message.data),
  ]);
}

/** Inverse of {@link encodeMessage}. Throws on an unknown version, truncation or trailing bytes. */
export function decodeMessage(encoded: Uint8Array): DecodedMessage {
  const buf = Buffer.from(encoded);
  let offset = 0;
  const take = (n: number): Buffer => {
    if (offset + n > buf.length) throw new Error("truncated MessageV1");
    const slice = buf.subarray(offset, offset + n);
    offset += n;
    return slice;
  };
  const u8 = () => take(1)[0];
  const u16 = () => take(2).readUInt16BE();
  const u32 = () => take(4).readUInt32BE();
  const u64 = () => take(8).readBigUInt64BE();
  const bytesU8 = () => Uint8Array.from(take(u8()));
  const bytesU16 = () => Uint8Array.from(take(u16()));

  const version = u8();
  if (version !== MESSAGE_V1_VERSION) throw new Error(`unsupported MessageV1 version ${version}`);
  const decoded: DecodedMessage = {
    sourceChainSelector: u64(),
    destChainSelector: u64(),
    messageNumber: u64(),
    executionGasLimit: u32(),
    ccipReceiveGasLimit: u32(),
    finalityFlags: u16(),
    finalityBlockDepth: u16(),
    ccvAndExecutorHash: Uint8Array.from(take(32)),
    onRampAddress: bytesU8(),
    offRampAddress: bytesU8(),
    sender: bytesU8(),
    receiver: bytesU8(),
    destBlob: bytesU16(),
    tokenTransfer: bytesU16(),
    data: bytesU16(),
  };
  if (offset !== buf.length) throw new Error("trailing bytes in MessageV1");
  return decoded;
}

/** The CCIP message id: keccak256 of the encoded message. */
export function messageId(encoded: Uint8Array): Buffer {
  return Buffer.from(getBytes(keccak256(encoded)));
}

/** Tag of the `abi.encodePacked` layout of the SVM executor args (the little-endian tag is Borsh). */
const DEST_BLOB_TAG_PACKED = Buffer.from([0x1a, 0x2b, 0x3c, 0x4d]);

/**
 * SVM destination blob (the message's `destBlob`): tag, `token_receiver` mode, writable bitmap of
 * the receiver accounts, then the account list.
 */
export function encodeDestBlob(blob: {
  accounts: PublicKey[];
  accountIsWritableBitmap?: bigint;
  /** 0 = derive and create the receiver's ATA. Irrelevant for data-only messages. */
  useAta?: number;
}): Buffer {
  if (blob.accounts.length > 0xff) throw new Error("a destBlob carries at most 255 accounts");
  return Buffer.concat([
    DEST_BLOB_TAG_PACKED,
    Buffer.from([blob.useAta ?? 0]),
    beU64(blob.accountIsWritableBitmap ?? 0n),
    Buffer.from([blob.accounts.length]),
    ...blob.accounts.map((account) => account.toBuffer()),
  ]);
}
