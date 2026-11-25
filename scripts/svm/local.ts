// `startSvmLocal()`: a local Solana chain with the real CCIP 2.0 programs, and `deliver()` to run an
// EVM-originated message through the real OffRamp into a receiver program.
//
// Ported in part from the prototype by Stefano Magini (magiodev-cll/chainlink-local, feat/svm-local,
// src/ccip-svm/src/simulator.ts, `deliver`): message construction, signing, the staged resolution and
// the v0 transaction with a lookup table. The lookup table is written with a cheatcode instead of
// being created and extended with transactions.

import fs from "node:fs";
import {
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
import { readIdl, resolveArtifacts, type CcipVersion } from "./artifacts.ts";
import { encodeDestBlob, encodeMessage, encodeTokenTransfer, messageId } from "./codec.ts";
import {
  EVM_CHAIN_SELECTOR,
  SEEDS,
  SVM_CHAIN_SELECTOR,
  pda,
  selectorSeed,
} from "./constants.ts";
import { checkDeliverOptions, describeFailure, sendForOutcome, writeLookupTable } from "./execution.ts";
import { startSvmLocal16 } from "./local16.ts";
import { CCIP_PROGRAMS, deployCcipPrograms } from "./programs.ts";
import { resolveAccounts } from "./resolver.ts";
import { SvmRuntime } from "./runtime.ts";
import { TokenSupport, encodeDecimals, type BurnMintToken, type DeliverToken, type LinkTokenOptions } from "./tokens.ts";
import { COMMITTEE_SIZE, COMMITTEE_THRESHOLD, initializeTrustLayer, loadPrograms } from "./trust.ts";
import { signVerifierResults, sortedCommittee } from "./signatures.ts";

const { BN } = anchor;

/** Placeholder onRamp that `trust.ts` registers at startup, until a real one replaces it; and the default sender. */
const LOCAL_ON_RAMP = Buffer.alloc(20, 1);
const DEFAULT_SENDER = Buffer.alloc(20, 2);

export interface DeliverOptions {
  /**
   * Program that receives the message through `ccip_receive`. Must be deployed. Absent = a token-only delivery
   * (`token` is then required, and `receiverAccounts`, `receiverWritableBitmap` and `data` must be left out).
   */
  receiverProgram?: PublicKey;
  /** Accounts the receiver needs after the fixed CCIP ones, in the order the receiver expects. Default none. */
  receiverAccounts?: PublicKey[];
  /** Bit i set = `receiverAccounts[i]` is writable. Default 0. */
  receiverWritableBitmap?: bigint;
  /** Message payload. A string is sent as its UTF-8 bytes. Default empty. */
  data?: string | Uint8Array;
  /**
   * Tokens delivered with the message: `amount` of a token linked with `linkToken`, in the EVM token's smallest
   * units, minted to `receiver`'s associated token account. See the README for decimals and for the account
   * creation difference between CCIP versions.
   */
  token?: DeliverToken;
  /** Source-chain sender address bytes. Default: a fixed 20-byte address. */
  sender?: Uint8Array;
  /** Default: the EVM selector (Ethereum Sepolia). */
  sourceChainSelector?: bigint;
  /** Default: auto-increment, so identical calls get distinct message ids. */
  messageNumber?: bigint;
  /**
   * Compute-unit limit of the execution transaction. Default 200,000, or 500,000 when a token is delivered (a token
   * delivery used 203,000 to 273,000 in measurements). Not capped here: a CCIP 2.0 lane
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

export interface StartOptions {
  /**
   * Which CCIP lane the local Solana chain runs. "2.0" (default) deploys the CCIP 2.0 programs and delivers
   * through `execute_v2` with a CommitteeVerifier signature. "1.6" deploys the CCIP 1.6 programs and delivers
   * through the OffRamp's `commit` (OCR3 signatures) and `execute`.
   */
  ccipVersion?: CcipVersion;
}

export interface SvmLocal {
  /** The lane version chosen at start. */
  readonly ccipVersion: CcipVersion;
  connection: Connection;
  payer: Keypair;
  ccip: { router: PublicKey; offRamp: PublicKey; chainSelector: bigint };
  /** Loads a compiled program (`.so`) at `programId`, with the payer as upgrade authority. */
  deployProgram(soPath: string, programId: PublicKey | string): Promise<void>;
  /**
   * Makes a token on the local chain: an SPL mint (`decimals`, default 9) whose mint authority is the real BurnMint
   * pool, registered in the real Router. The pool program is deployed on the first call. Classic SPL Token only.
   */
  createBurnMintToken(options?: { decimals?: number }): Promise<BurnMintToken>;
  /** Connects the token to an EVM token, so `deliver({ token })` can mint it. Throws if either side is already linked. */
  linkToken(token: { mint: PublicKey }, options: LinkTokenOptions): Promise<void>;
  /** The Solana mint linked to `evmToken` (case-insensitive), if any. */
  linkedMint(evmToken: string): PublicKey | undefined;
  /** Creates the associated token account of `owner` for `mint` and returns its address. An existing one is left untouched. */
  createTokenAccount(mint: PublicKey, owner: PublicKey): Promise<PublicKey>;
  /** Balance of the associated token account of `owner` for `mint`, in the mint's smallest units; 0n if it does not exist. */
  tokenBalance(mint: PublicKey, owner: PublicKey): Promise<bigint>;
  /** Runs a message through the real OffRamp. Whatever Solana does is returned; only harness misuse throws. */
  deliver(options: DeliverOptions): Promise<DeliverResult>;
  /** Signs with the payer plus `signers`, sends and waits for confirmation. Returns the signature. */
  sendAndConfirm(transaction: Transaction, signers?: Keypair[]): Promise<string>;
  /** Stops the Surfnet. Safe to call more than once. */
  stop(): void;
}

/** Boots a Surfnet, deploys the pinned CCIP programs of `ccipVersion` (default "2.0") and initialises them with local keys. */
export async function startSvmLocal(options: StartOptions = {}): Promise<SvmLocal> {
  const ccipVersion = options.ccipVersion ?? "2.0";
  if (ccipVersion === "1.6") return startSvmLocal16();
  if (ccipVersion !== "2.0") throw new Error(`startSvmLocal: ccipVersion must be "2.0" or "1.6", got ${JSON.stringify(ccipVersion)}`);
  const bundleDir = await resolveArtifacts();
  const runtime = SvmRuntime.start();
  try {
    await deployCcipPrograms(runtime, bundleDir);
    const programs = loadPrograms(runtime, bundleDir);
    await initializeTrustLayer(runtime, programs);
    return new Local(runtime, bundleDir, programs);
  } catch (error) {
    runtime.stop();
    throw error;
  }
}

class Local implements SvmLocal {
  readonly ccipVersion = "2.0" as const;
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
  private readonly tokens: TokenSupport;
  private readonly offRampIdl: { instructions: { name: string; discriminator: number[] }[] };

  constructor(runtime: SvmRuntime, bundleDir: string, programs: ReturnType<typeof loadPrograms>) {
    this.runtime = runtime;
    this.offRamp = programs.offRamp;
    this.tokens = new TokenSupport({ runtime, ccipVersion: "2.0", bundleDir, router: programs.router, offRamp: this.ccip.offRamp });
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

  createBurnMintToken(options?: { decimals?: number }): Promise<BurnMintToken> {
    return this.tokens.createBurnMintToken(options);
  }

  linkToken(token: { mint: PublicKey }, options: LinkTokenOptions): Promise<void> {
    return this.tokens.linkToken(token, options);
  }

  linkedMint(evmToken: string): PublicKey | undefined {
    return this.tokens.linkedMint(evmToken);
  }

  createTokenAccount(mint: PublicKey, owner: PublicKey): Promise<PublicKey> {
    return this.tokens.createTokenAccount(mint, owner);
  }

  tokenBalance(mint: PublicKey, owner: PublicKey): Promise<bigint> {
    return this.tokens.tokenBalance(mint, owner);
  }

  sendAndConfirm(transaction: Transaction, signers: Keypair[] = []): Promise<string> {
    return this.runtime.sendAndConfirm(transaction, signers);
  }

  stop(): void {
    this.runtime.stop();
  }

  async deliver(options: DeliverOptions): Promise<DeliverResult> {
    const { computeUnits, receiverAccounts, receiverWritableBitmap, data } = checkDeliverOptions(options);
    const token = options.token ? this.tokens.resolve(options.token) : undefined;
    const sourceChainSelector = options.sourceChainSelector ?? EVM_CHAIN_SELECTOR;
    const onRampAddress = await this.laneOnRamp(sourceChainSelector, options.onRampAddress);

    const messageNumber = options.messageNumber ?? this.nextMessageNumber++;
    const encodedMessage = encodeMessage({
      sourceChainSelector,
      destChainSelector: SVM_CHAIN_SELECTOR,
      messageNumber,
      executionGasLimit: computeUnits,
      ccipReceiveGasLimit: options.receiverProgram ? computeUnits : 0,
      onRampAddress,
      offRampAddress: this.ccip.offRamp.toBuffer(),
      sender: options.sender ?? DEFAULT_SENDER,
      // A token-only message has a zero receiver, as the executor sends it.
      receiver: options.receiverProgram?.toBuffer() ?? Buffer.alloc(32),
      // useAta 0 = DeriveAtaAndCreate: the OffRamp creates the receiver's associated token account.
      destBlob: encodeDestBlob({ accounts: receiverAccounts, accountIsWritableBitmap: receiverWritableBitmap, useAta: 0 }),
      tokenTransfer: token && encodeTokenTransfer({
        amount: token.amount,
        sourcePool: token.evmPool,
        sourceToken: token.evmToken,
        destToken: token.mint,
        tokenReceiver: token.receiver,
        extraData: encodeDecimals(token.evmDecimals),
      }),
      data,
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
    const lookupTable = await writeLookupTable(this.runtime, resolved.accounts.map((account) => account.pubkey));
    const message = new TransactionMessage({
      payerKey: this.payer.publicKey,
      recentBlockhash: (await this.connection.getLatestBlockhash()).blockhash,
      instructions: [ComputeBudgetProgram.setComputeUnitLimit({ units: computeUnits }), execute],
    }).compileToV0Message([lookupTable]);
    const transaction = new VersionedTransaction(message);
    transaction.sign([this.payer]);

    const outcome = await sendForOutcome(this.runtime, transaction);
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
}
