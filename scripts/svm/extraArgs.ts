// `svmExtraArgs()`: the `extraArgs` of a CCIP message to Solana, encoded as Solidity's
// `Client._svmArgsToBytes(Client.SVMExtraArgsV1(...))` does.

import { AbiCoder, getBytes, hexlify, concat } from "ethers";
import type { PublicKey } from "@solana/web3.js";

/** `Client.SVM_EXTRA_ARGS_V1_TAG`, the first 4 bytes of the extra args. */
const SVM_EXTRA_ARGS_V1_TAG = "0x1f3b3aba";
/** Limits the local router enforces at send time, as an OnRamp 2.0 lane does (`CCIPLocalRouter`). */
const MAX_COMPUTE_UNITS = 3_000_000;
const MAX_ACCOUNTS = 255;
const MAX_UINT32 = 0xffffffff;
const MAX_UINT64 = (1n << 64n) - 1n;

const SVM_EXTRA_ARGS_TYPE = "tuple(uint32,uint64,bool,bytes32,bytes32[])";

export interface SvmExtraArgsOptions {
  /** Compute-unit limit of the receiver call. At most 3,000,000, as on a CCIP 2.0 lane. */
  computeUnits: number;
  /** Accounts the receiver needs after the fixed CCIP ones: a `PublicKey` or its 32 bytes. At most 255. */
  accounts: (PublicKey | Uint8Array)[];
  /** Bit i set = `accounts[i]` is writable. */
  writableBitmap: bigint;
  /** Recipient of tokens on Solana. Default: all zero (data-only messages). */
  tokenReceiver?: PublicKey | Uint8Array;
  /** Default true: CCIP 2.0 requires it for Solana. */
  allowOutOfOrderExecution?: boolean;
}

function bytes32(value: PublicKey | Uint8Array, name: string): string {
  const raw = "toBytes" in value ? value.toBytes() : value;
  if (raw.length !== 32) throw new Error(`svmExtraArgs: ${name} must be 32 bytes, got ${raw.length}`);
  return hexlify(raw);
}

/**
 * Returns the tagged, ABI-encoded `SVMExtraArgsV1` as a hex string, ready for `EVM2AnyMessage.extraArgs`.
 * Throws what the local router would revert with for the same extra args (`MessageComputeUnitLimitTooHigh`,
 * `InvalidDataLength`). Like the router, it does not check the writable bitmap against the accounts.
 */
export function svmExtraArgs(options: SvmExtraArgsOptions): string {
  const { computeUnits, accounts, writableBitmap } = options;
  if (!Number.isInteger(computeUnits) || computeUnits < 0 || computeUnits > MAX_UINT32) {
    throw new Error(`svmExtraArgs: computeUnits must be an integer in 0..${MAX_UINT32}, got ${computeUnits}`);
  }
  if (computeUnits > MAX_COMPUTE_UNITS) {
    throw new Error(`svmExtraArgs: MessageComputeUnitLimitTooHigh: ${computeUnits} compute units, the limit is ${MAX_COMPUTE_UNITS}`);
  }
  if (accounts.length > MAX_ACCOUNTS) {
    throw new Error(`svmExtraArgs: InvalidDataLength: ${accounts.length} accounts, the limit is ${MAX_ACCOUNTS}`);
  }
  if (typeof writableBitmap !== "bigint" || writableBitmap < 0n || writableBitmap > MAX_UINT64) {
    throw new Error(`svmExtraArgs: writableBitmap must be a bigint in 0..2^64-1, got ${String(writableBitmap)}`);
  }
  const encoded = AbiCoder.defaultAbiCoder().encode(
    [SVM_EXTRA_ARGS_TYPE],
    [
      [
        computeUnits,
        writableBitmap,
        options.allowOutOfOrderExecution ?? true,
        options.tokenReceiver ? bytes32(options.tokenReceiver, "tokenReceiver") : "0x" + "00".repeat(32),
        accounts.map((account, i) => bytes32(account, `accounts[${i}]`)),
      ],
    ],
  );
  return hexlify(concat([getBytes(SVM_EXTRA_ARGS_V1_TAG), getBytes(encoded)]));
}
