// Transaction helpers shared by the CCIP 2.0 and 1.6 lanes: running a transaction without preflight, the
// lookup table for long account lists, and the readable failure reason.

import {
  AddressLookupTableAccount,
  Keypair,
  PublicKey,
  type VersionedTransaction,
} from "@solana/web3.js";
import { ADDRESS_LOOKUP_TABLE_PROGRAM } from "./constants.ts";
import type { SvmRuntime } from "./runtime.ts";

export const DEFAULT_COMPUTE_UNITS = 200_000;
/**
 * Added on top of the message's `computeUnits` when a token is delivered, as a live executor covers the token's
 * destination gas overhead (charged separately by the FeeQuoter) on top of the receiver's compute units: the pool
 * CPI, the mint and (on 2.0) the receiver's token account creation took 170,000 to 255,000 compute units in total.
 */
export const TOKEN_COMPUTE_UNITS = 300_000;
const MAX_UINT64 = (1n << 64n) - 1n;
const MAX_UINT256 = (1n << 256n) - 1n;

export interface CheckedDeliver {
  /** The compute-unit limit of the execution transaction. */
  computeUnits: number;
  receiverAccounts: PublicKey[];
  receiverWritableBitmap: bigint;
  data: Buffer;
}

/** The `deliver()` arguments both lanes validate the same way, with the optional ones defaulted. */
export function checkDeliverOptions(options: {
  receiverProgram?: PublicKey;
  receiverAccounts?: PublicKey[];
  receiverWritableBitmap?: bigint;
  data?: string | Uint8Array;
  token?: { evmToken: string; amount: bigint; receiver: PublicKey };
  computeUnits?: number;
  onRampAddress?: Uint8Array;
}): CheckedDeliver {
  const computeUnits = (options.computeUnits ?? DEFAULT_COMPUTE_UNITS) + (options.token ? TOKEN_COMPUTE_UNITS : 0);
  // 0 is not misuse: a CCIP 2.0 EVM send accepts it, so the message runs and Solana decides the outcome.
  if (!Number.isInteger(computeUnits) || computeUnits < 0) {
    throw new Error(`deliver: computeUnits must be a non-negative integer, got ${computeUnits}`);
  }
  const receiverAccounts = options.receiverAccounts ?? [];
  const receiverWritableBitmap = options.receiverWritableBitmap ?? 0n;
  const data = typeof options.data === "string" ? Buffer.from(options.data) : Buffer.from(options.data ?? []);
  if (
    (options.receiverProgram !== undefined && !(options.receiverProgram instanceof PublicKey)) ||
    !receiverAccounts.every((a) => a instanceof PublicKey)
  ) {
    throw new Error("deliver: receiverProgram and receiverAccounts must be PublicKeys");
  }
  const bitmap = receiverWritableBitmap;
  if (typeof bitmap !== "bigint" || bitmap < 0n || bitmap > MAX_UINT64) {
    throw new Error(`deliver: receiverWritableBitmap must be a bigint in 0..2^64-1, got ${String(bitmap)}`);
  }
  if (options.receiverProgram === undefined) {
    if (!options.token) throw new Error("deliver: receiverProgram is required unless a token is delivered");
    if (receiverAccounts.length > 0 || bitmap !== 0n || data.length > 0) {
      throw new Error("deliver: a token-only delivery (no receiverProgram) cannot carry receiverAccounts, receiverWritableBitmap or data");
    }
  }
  if (options.token) {
    const { amount, receiver } = options.token;
    if (typeof amount !== "bigint" || amount < 0n || amount > MAX_UINT256) {
      throw new Error(`deliver: token.amount must be a bigint in 0..2^256-1 (source units), got ${String(amount)}`);
    }
    if (!(receiver instanceof PublicKey)) throw new Error("deliver: token.receiver must be a PublicKey");
  }
  // No other pre-checks: a bitmap with stray bits, a receiver that is not a program and a compute-unit
  // limit above the runtime's cap are all accepted by a CCIP EVM send, and fail (or not) on Solana.
  if (options.onRampAddress !== undefined && options.onRampAddress.length !== 20) {
    throw new Error(`deliver: onRampAddress must be 20 bytes, got ${options.onRampAddress.length}`);
  }
  return { computeUnits, receiverAccounts, receiverWritableBitmap, data };
}

/** Sends without preflight (so a failing execution still lands) and reads its logs and compute units. */
export async function sendForOutcome(runtime: SvmRuntime, transaction: VersionedTransaction) {
  const { connection } = runtime;
  const signature = await connection.sendRawTransaction(transaction.serialize(), { skipPreflight: true });
  const deadline = Date.now() + 30_000;
  let fetched = null;
  while (Date.now() < deadline && !fetched) {
    fetched = await connection.getTransaction(signature, {
      commitment: "confirmed",
      maxSupportedTransactionVersion: 0,
    });
    if (!fetched) await new Promise((resolve) => setTimeout(resolve, 50));
  }
  if (!fetched?.meta) throw new Error(`deliver: transaction ${signature} was not confirmed within 30s`);
  return {
    signature,
    /** The confirmed transaction, for callers that read its inner instructions. */
    transaction: fetched,
    err: fetched.meta.err,
    logs: fetched.meta.logMessages ?? [],
    computeUnitsUsed: fetched.meta.computeUnitsConsumed ?? 0,
  };
}

/** Creates an active lookup table holding `addresses` by writing the account directly, at `key` (default: a new address). */
export async function writeLookupTable(
  runtime: SvmRuntime,
  addresses: PublicKey[],
  key: PublicKey = Keypair.generate().publicKey,
): Promise<AddressLookupTableAccount> {
  // Layout: u32 type (1 = table) | u64 deactivation slot (max = active) | u64 last extended slot |
  // u8 start index | Option<Pubkey> authority (none) | u16 padding | addresses.
  const header = Buffer.alloc(56);
  header.writeUInt32LE(1, 0);
  header.writeBigUInt64LE(0xffffffffffffffffn, 4);
  const data = Buffer.concat([header, ...addresses.map((address) => address.toBuffer())]);
  await runtime.setAccount(key, {
    lamports: await runtime.connection.getMinimumBalanceForRentExemption(data.length),
    owner: ADDRESS_LOOKUP_TABLE_PROGRAM,
    data,
  });
  const table = (await runtime.connection.getAddressLookupTable(key)).value;
  if (!table) throw new Error("deliver: the lookup table was not created");
  return table;
}

/** Turns a failed transaction into a sentence: the Anchor error, the compute budget, or the raw error. */
export function describeFailure(err: unknown, logs: string[], used: number, limit: number): string {
  const anchorLine = logs.find((line) => line.includes("AnchorError"));
  if (anchorLine) return anchorLine.replace(/^Program log: /, "");
  if (/exceeded CUs meter|ComputationalBudgetExceeded/.test(logs.join("\n") + JSON.stringify(err))) {
    return `compute budget exceeded: used ${used} of ${limit} compute units; raise computeUnits`;
  }
  const lastLog = logs.filter((line) => line.startsWith("Program log:")).at(-1);
  return `${JSON.stringify(err)}${lastLog ? ` (${lastLog.replace(/^Program log: /, "")})` : ""}`;
}
