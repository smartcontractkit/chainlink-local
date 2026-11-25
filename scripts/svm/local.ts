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

/** Largest compute-unit limit a transaction can request. */
const MAX_COMPUTE_UNITS = 1_400_000;
const DEFAULT_COMPUTE_UNITS = 200_000;
/** The on-ramp address the source chain config accepts, and the default source-chain sender. */
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
  /** Compute-unit limit of the execution transaction. Default 200,000. */
  computeUnits?: number;
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
  /** Runs a message through the real OffRamp. Destination failures are returned, misuse throws. */
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
    if (!Number.isInteger(computeUnits) || computeUnits < 1 || computeUnits > MAX_COMPUTE_UNITS) {
      throw new Error(`deliver: computeUnits must be an integer in 1..${MAX_COMPUTE_UNITS}, got ${computeUnits}`);
    }
    const bitmap = options.receiverWritableBitmap;
    if (bitmap < 0n || bitmap >= 1n << BigInt(Math.max(options.receiverAccounts.length, 1))) {
      throw new Error(
        `deliver: receiverWritableBitmap ${bitmap} has bits beyond the ${options.receiverAccounts.length} receiver accounts`,
      );
    }
    const receiver = await this.connection.getAccountInfo(options.receiverProgram);
    if (!receiver?.executable) {
      throw new Error(`deliver: ${options.receiverProgram.toBase58()} is not a deployed program; call deployProgram first`);
    }
    const sourceChainSelector = options.sourceChainSelector ?? EVM_CHAIN_SELECTOR;
    const sourceChainConfig = await this.connection.getAccountInfo(
      pda([Buffer.from(SEEDS.sourceChain), selectorSeed(sourceChainSelector)], this.ccip.offRamp),
    );
    if (!sourceChainConfig) {
      throw new Error(`deliver: source chain ${sourceChainSelector} is not configured; only ${EVM_CHAIN_SELECTOR} is`);
    }

    const messageNumber = options.messageNumber ?? this.nextMessageNumber++;
    const encodedMessage = encodeMessage({
      sourceChainSelector,
      destChainSelector: SVM_CHAIN_SELECTOR,
      messageNumber,
      executionGasLimit: computeUnits,
      ccipReceiveGasLimit: computeUnits,
      onRampAddress: LOCAL_ON_RAMP,
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
