// `startSvmLocal()`: a local Solana chain with the real CCIP 2.0 programs, and `deliver()` to run an
// EVM-originated message through the real OffRamp into a receiver program.
//
// Ported in part from the prototype by Stefano Magini (magiodev-cll/chainlink-local, feat/svm-local,
// src/ccip-svm/src/simulator.ts, `deliver`): message construction, signing, the staged resolution and
// the v0 transaction with a lookup table. The lookup table is written with a cheatcode instead of
// being created and extended with transactions.

import fs from "node:fs";
import {
  AddressLookupTableAccount,
  ComputeBudgetProgram,
  Keypair,
  PublicKey,
  SystemProgram,
  Transaction,
  TransactionInstruction,
  TransactionMessage,
  VersionedTransaction,
  type Connection,
} from "@solana/web3.js";
import anchor from "@anchor-lang/core";
import { readIdl, resolveArtifacts } from "./artifacts.ts";
import { encodeDestBlob, encodeMessage, messageId } from "./codec.ts";
import {
  ADDRESS_LOOKUP_TABLE_PROGRAM,
  EVM_CHAIN_SELECTOR,
  SEEDS,
  SVM_CHAIN_SELECTOR,
  pda,
  selectorSeed,
} from "./constants.ts";
import { CCIP_PROGRAMS, deployCcipPrograms } from "./programs.ts";
import { resolveAccounts } from "./resolver.ts";
import { SvmRuntime } from "./runtime.ts";
import { COMMITTEE_SIZE, COMMITTEE_THRESHOLD, initializeTrustLayer, loadPrograms } from "./trust.ts";
import { signVerifierResults, sortedCommittee } from "./signatures.ts";

const { BN } = anchor;

const DEFAULT_COMPUTE_UNITS = 200_000;
const MAX_UINT64 = (1n << 64n) - 1n;
/** Placeholder onRamp that `trust.ts` registers at startup, until a real one replaces it; and the default sender. */
const LOCAL_ON_RAMP = Buffer.alloc(20, 1);
const DEFAULT_SENDER = Buffer.alloc(20, 2);

export interface DeliverOptions {
  /** Program that receives the message through `ccip_receive`. Must be deployed. */
  receiverProgram: PublicKey;
  /** Accounts the receiver needs after the fixed CCIP ones, in the order the receiver expects. */
  receiverAccounts: PublicKey[];
  /** Bit i set = `receiverAccounts[i]` is writable. */
  receiverWritableBitmap: bigint;
  /** Message payload. A string is sent as its UTF-8 bytes. */
  data: string | Uint8Array;
  /** Source-chain sender address bytes. Default: a fixed 20-byte address. */
  sender?: Uint8Array;
  /** Default: the EVM selector (Ethereum Sepolia). */
  sourceChainSelector?: bigint;
  /** Default: auto-increment, so identical calls get distinct message ids. */
  messageNumber?: bigint;
  /**
   * Compute-unit limit of the execution transaction. Default 200,000. Not capped here: a CCIP 2.0 lane
   * accepts up to 3,000,000 at send time, and what the runtime does with more is returned in the result.
   */
  computeUnits?: number;
  /**
   * 20-byte address of the source chain's OnRamp (for messages from `CCIPLocalRouter`, the router address).
   * Like a live lane, the OffRamp accepts one onRamp per source chain. It is a placeholder at startup, and the
   * first explicit `onRampAddress` replaces it. A message from any other onRamp runs and fails on Solana.
   * Default: the onRamp the source chain currently accepts.
   */
  onRampAddress?: Uint8Array;
}

export interface DeliverResult {
  /** `0x`-prefixed keccak256 of the encoded message. */
  messageId: string;
  state: "Success" | "Failure";
  computeUnitsUsed: number;
  logs: string[];
  /** Readable reason when `state` is `Failure`. */
  error?: string;
}

export interface SvmLocal {
  connection: Connection;
  payer: Keypair;
  ccip: { router: PublicKey; offRamp: PublicKey; chainSelector: bigint };
  /** Loads a compiled program (`.so`) at `programId`, with the payer as upgrade authority. */
  deployProgram(soPath: string, programId: PublicKey | string): Promise<void>;
  /** Runs a message through the real OffRamp. Whatever Solana does is returned; only harness misuse throws. */
  deliver(options: DeliverOptions): Promise<DeliverResult>;
  /** Signs with the payer plus `signers`, sends and waits for confirmation. Returns the signature. */
  sendAndConfirm(transaction: Transaction, signers?: Keypair[]): Promise<string>;
  /** Stops the Surfnet. Safe to call more than once. */
  stop(): void;
}

/** Boots a Surfnet, deploys the pinned CCIP 2.0 programs and initialises them with local keys. */
export async function startSvmLocal(): Promise<SvmLocal> {
  const bundleDir = await resolveArtifacts();
  const runtime = SvmRuntime.start();
  try {
    await deployCcipPrograms(runtime, bundleDir);
    const programs = loadPrograms(runtime, bundleDir);
    await initializeTrustLayer(runtime, programs);
    return new Local(runtime, bundleDir, programs.offRamp);
  } catch (error) {
    runtime.stop();
    throw error;
  }
}

class Local implements SvmLocal {
  readonly connection: Connection;
  readonly payer: Keypair;
  readonly ccip = {
    router: new PublicKey(CCIP_PROGRAMS.ccip_router),
    offRamp: new PublicKey(CCIP_PROGRAMS.ccip_offramp),
    chainSelector: SVM_CHAIN_SELECTOR,
  };
  private nextMessageNumber = 1n;
  /** The one onRamp the OffRamp accepts, per source chain selector. */
  private readonly laneOnRamps = new Map<bigint, Buffer>();
  private readonly runtime: SvmRuntime;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  private readonly offRamp: any;
  private readonly offRampIdl: { instructions: { name: string; discriminator: number[] }[] };

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  constructor(runtime: SvmRuntime, bundleDir: string, offRamp: any) {
    this.runtime = runtime;
    this.offRamp = offRamp;
    this.connection = runtime.connection;
    this.payer = runtime.payer;
    this.offRampIdl = readIdl(bundleDir, "ccip_offramp") as never;
  }

  async deployProgram(soPath: string, programId: PublicKey | string): Promise<void> {
    if (!fs.existsSync(soPath)) throw new Error(`deployProgram: ${soPath} does not exist`);
    const id = new PublicKey(programId);
    await this.runtime.writeProgram(id, fs.readFileSync(soPath));
    await this.runtime.setProgramAuthority(id, this.payer.publicKey);
  }

  sendAndConfirm(transaction: Transaction, signers: Keypair[] = []): Promise<string> {
    return this.runtime.sendAndConfirm(transaction, signers);
  }

  stop(): void {
    this.runtime.stop();
  }

  async deliver(options: DeliverOptions): Promise<DeliverResult> {
    const computeUnits = options.computeUnits ?? DEFAULT_COMPUTE_UNITS;
    // 0 is not misuse: a CCIP 2.0 EVM send accepts it, so the message runs and Solana decides the outcome.
    if (!Number.isInteger(computeUnits) || computeUnits < 0) {
      throw new Error(`deliver: computeUnits must be a non-negative integer, got ${computeUnits}`);
    }
    if (!(options.receiverProgram instanceof PublicKey) || !options.receiverAccounts.every((a) => a instanceof PublicKey)) {
      throw new Error("deliver: receiverProgram and receiverAccounts must be PublicKeys");
    }
    const bitmap = options.receiverWritableBitmap;
    if (typeof bitmap !== "bigint" || bitmap < 0n || bitmap > MAX_UINT64) {
      throw new Error(`deliver: receiverWritableBitmap must be a bigint in 0..2^64-1, got ${String(bitmap)}`);
    }
    // No other pre-checks: a bitmap with stray bits, a receiver that is not a program and a compute-unit
    // limit above the runtime's cap are all accepted by a CCIP 2.0 EVM send, and fail (or not) on Solana.
    const sourceChainSelector = options.sourceChainSelector ?? EVM_CHAIN_SELECTOR;
    if (options.onRampAddress !== undefined && options.onRampAddress.length !== 20) {
      throw new Error(`deliver: onRampAddress must be 20 bytes, got ${options.onRampAddress.length}`);
    }
    const onRampAddress = await this.laneOnRamp(sourceChainSelector, options.onRampAddress);

    const messageNumber = options.messageNumber ?? this.nextMessageNumber++;
    const encodedMessage = encodeMessage({
      sourceChainSelector,
      destChainSelector: SVM_CHAIN_SELECTOR,
      messageNumber,
      executionGasLimit: computeUnits,
      ccipReceiveGasLimit: computeUnits,
      onRampAddress,
      offRampAddress: this.ccip.offRamp.toBuffer(),
      sender: options.sender ?? DEFAULT_SENDER,
      receiver: options.receiverProgram.toBuffer(),
      destBlob: encodeDestBlob({
        accounts: options.receiverAccounts,
        accountIsWritableBitmap: bitmap,
      }),
      data: typeof options.data === "string" ? Buffer.from(options.data) : options.data,
    });
    const id = messageId(encodedMessage);
    const verifierResults = signVerifierResults(id, sortedCommittee(COMMITTEE_SIZE), COMMITTEE_THRESHOLD);

    const instructionData = (resolutionMetadata: Uint8Array): Buffer =>
      this.offRamp.coder.instruction.encode("executeV2", {
        params: {
          execInputs: {
            encodedMessage,
            ccvs: [new PublicKey(CCIP_PROGRAMS.committee_verifier)],
            verifierResults: [verifierResults],
          },
          resolutionMetadata: Buffer.from(resolutionMetadata),
        },
      });

    const resolved = await resolveAccounts({
      connection: this.connection,
      programId: this.ccip.offRamp,
      idl: this.offRampIdl,
      payer: this.payer,
      config: pda([Buffer.from(SEEDS.config)], this.ccip.offRamp),
      ixData: instructionData(new Uint8Array(0)),
    });
    const execute = new TransactionInstruction({
      programId: this.ccip.offRamp,
      keys: resolved.accounts,
      data: instructionData(resolved.metadata),
    });

    // The resolved account list does not fit a legacy transaction, so the accounts go in a lookup table.
    const lookupTable = await this.writeLookupTable(resolved.accounts.map((account) => account.pubkey));
    const message = new TransactionMessage({
      payerKey: this.payer.publicKey,
      recentBlockhash: (await this.connection.getLatestBlockhash()).blockhash,
      instructions: [ComputeBudgetProgram.setComputeUnitLimit({ units: computeUnits }), execute],
    }).compileToV0Message([lookupTable]);
    const transaction = new VersionedTransaction(message);
    transaction.sign([this.payer]);

    const outcome = await this.run(transaction);
    return {
      messageId: "0x" + id.toString("hex"),
      state: outcome.err === null ? "Success" : "Failure",
      computeUnitsUsed: outcome.computeUnitsUsed,
      logs: outcome.logs,
      ...(outcome.err === null ? {} : { error: describeFailure(outcome.err, outcome.logs, outcome.computeUnitsUsed, computeUnits) }),
    };
  }

  /**
   * Returns the onRamp a message from `sourceChainSelector` carries. The OffRamp accepts exactly one onRamp
   * per source chain, as on a live lane: the placeholder from startup until the first explicit `requested`
   * onRamp replaces it, through the OffRamp's own admin instruction (`update_source_chain_config`).
   * After that, a different `requested` onRamp is returned as is, and the real OffRamp rejects the message.
   */
  private async laneOnRamp(sourceChainSelector: bigint, requested?: Uint8Array): Promise<Buffer> {
    const sourceChain = pda([Buffer.from(SEEDS.sourceChain), selectorSeed(sourceChainSelector)], this.ccip.offRamp);
    let accepted = this.laneOnRamps.get(sourceChainSelector);
    if (!accepted) {
      const state = await this.offRamp.account.sourceChain.fetchNullable(sourceChain, "confirmed");
      if (!state) {
        throw new Error(`deliver: source chain ${sourceChainSelector} is not configured; only ${EVM_CHAIN_SELECTOR} is`);
      }
      const [entry] = state.config.onRamps as { bytes: number[]; len: number }[];
      accepted = Buffer.from(entry.bytes.slice(0, entry.len));
      this.laneOnRamps.set(sourceChainSelector, accepted);
    }
    if (requested === undefined) return accepted;
    const onRamp = Buffer.from(requested);
    if (!accepted.equals(LOCAL_ON_RAMP) || onRamp.equals(accepted)) return onRamp;

    const state = await this.offRamp.account.sourceChain.fetch(sourceChain, "confirmed");
    const padded = Buffer.alloc(64);
    onRamp.copy(padded);
    const update = await this.offRamp.methods
      .updateSourceChainConfig({
        sourceChainSelector: new BN(sourceChainSelector.toString()),
        sourceChainConfig: { ...state.config, onRamps: [{ bytes: Array.from(padded), len: onRamp.length }] },
      })
      .accounts({
        sourceChain,
        config: pda([Buffer.from(SEEDS.config)], this.ccip.offRamp),
        authority: this.payer.publicKey,
        systemProgram: SystemProgram.programId,
      })
      .instruction();
    await this.runtime.sendAndConfirm(new Transaction().add(update));
    this.laneOnRamps.set(sourceChainSelector, onRamp);
    return onRamp;
  }

  /** Sends without preflight (so a failing execution still lands) and reads its logs and compute units. */
  private async run(transaction: VersionedTransaction) {
    const signature = await this.connection.sendRawTransaction(transaction.serialize(), { skipPreflight: true });
    const deadline = Date.now() + 30_000;
    let fetched = null;
    while (Date.now() < deadline && !fetched) {
      fetched = await this.connection.getTransaction(signature, {
        commitment: "confirmed",
        maxSupportedTransactionVersion: 0,
      });
      if (!fetched) await new Promise((resolve) => setTimeout(resolve, 50));
    }
    if (!fetched?.meta) throw new Error(`deliver: transaction ${signature} was not confirmed within 30s`);
    return {
      err: fetched.meta.err,
      logs: fetched.meta.logMessages ?? [],
      computeUnitsUsed: fetched.meta.computeUnitsConsumed ?? 0,
    };
  }

  /** Creates an active lookup table holding `addresses` by writing the account directly. */
  private async writeLookupTable(addresses: PublicKey[]): Promise<AddressLookupTableAccount> {
    const key = Keypair.generate().publicKey;
    // Layout: u32 type (1 = table) | u64 deactivation slot (max = active) | u64 last extended slot |
    // u8 start index | Option<Pubkey> authority (none) | u16 padding | addresses.
    const header = Buffer.alloc(56);
    header.writeUInt32LE(1, 0);
    header.writeBigUInt64LE(0xffffffffffffffffn, 4);
    const data = Buffer.concat([header, ...addresses.map((address) => address.toBuffer())]);
    await this.runtime.setAccount(key, {
      lamports: await this.connection.getMinimumBalanceForRentExemption(data.length),
      owner: ADDRESS_LOOKUP_TABLE_PROGRAM,
      data,
    });
    const table = (await this.connection.getAddressLookupTable(key)).value;
    if (!table) throw new Error("deliver: the lookup table was not created");
    return table;
  }
}

/** Turns a failed transaction into a sentence: the Anchor error, the compute budget, or the raw error. */
function describeFailure(err: unknown, logs: string[], used: number, limit: number): string {
  const anchorLine = logs.find((line) => line.includes("AnchorError"));
  if (anchorLine) return anchorLine.replace(/^Program log: /, "");
  if (/exceeded CUs meter|ComputationalBudgetExceeded/.test(logs.join("\n") + JSON.stringify(err))) {
    return `compute budget exceeded: used ${used} of ${limit} compute units; raise computeUnits`;
  }
  const lastLog = logs.filter((line) => line.startsWith("Program log:")).at(-1);
  return `${JSON.stringify(err)}${lastLog ? ` (${lastLog.replace(/^Program log: /, "")})` : ""}`;
}
