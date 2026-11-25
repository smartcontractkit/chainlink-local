// `startSvmLocal({ ccipVersion: "1.6" })`: a local Solana chain with the real CCIP 1.6 programs, and `deliver()`
// that runs an EVM-originated message through the real OffRamp `commit` and `execute`.
//
// A live 1.6 lane has a commit DON that signs a Merkle root and an execution DON that submits the message
// with its proof. Locally the harness plays both: the commit is signed by 2 of 4 local keys (OCR3, F = 1) and
// both transactions are sent by the one configured transmitter, the payer. The message is a one-leaf tree.

import fs from "node:fs";
import anchor from "@anchor-lang/core";
import {
  ComputeBudgetProgram,
  PublicKey,
  SYSVAR_INSTRUCTIONS_PUBKEY,
  SystemProgram,
  Transaction,
  TransactionInstruction,
  TransactionMessage,
  VersionedTransaction,
  type Connection,
  type Keypair,
} from "@solana/web3.js";
import { resolveArtifacts } from "./artifacts.ts";
import { EVM_CHAIN_SELECTOR, SEEDS, SVM_CHAIN_SELECTOR, pda, selectorSeed } from "./constants.ts";
import { checkDeliverOptions, describeFailure, sendForOutcome, writeLookupTable } from "./execution.ts";
import {
  encodeCommitReport,
  encodeExecutionReport,
  leafHash,
  localMessageId,
  reportContext,
  signCommit,
  type Message16,
} from "./leaf16.ts";
import { CCIP_PROGRAMS_1_6, deployCcipPrograms } from "./programs.ts";
import { SvmRuntime } from "./runtime.ts";
import { Sender16 } from "./send16.ts";
import type { SentMessagesOptions, SvmSendOptions, SvmSentMessage } from "./send.ts";
import type { DeliverOptions, DeliverResult, SvmLocal } from "./local.ts";
import { TokenSupport, encodeDecimals, type BurnMintToken, type LinkTokenOptions } from "./tokens.ts";
import {
  COMMIT_CONFIG_DIGEST,
  EXECUTION_CONFIG_DIGEST,
  F_1_6,
  PLACEHOLDER_ON_RAMP_1_6,
  allowedOfframp,
  committee16,
  initializeTrustLayer16,
  loadPrograms16,
  type CcipPrograms16,
} from "./trust16.ts";

const { BN } = anchor;

const DEFAULT_SENDER = Buffer.alloc(20, 2);
/** Two secp256k1 recoveries and a PDA creation: well under 400,000, and unrelated to the message's limit. */
const COMMIT_COMPUTE_UNITS = 400_000;

export async function startSvmLocal16(): Promise<SvmLocal> {
  const bundleDir = await resolveArtifacts({ ccipVersion: "1.6" });
  const runtime = SvmRuntime.start();
  try {
    await deployCcipPrograms(runtime, bundleDir, "1.6");
    const programs = loadPrograms16(runtime, bundleDir);
    await initializeTrustLayer16(runtime, programs);
    const tokens = new TokenSupport({ runtime, ccipVersion: "1.6", bundleDir, router: programs.router, offRamp: new PublicKey(CCIP_PROGRAMS_1_6.ccip_offramp) });
    const sender = await Sender16.create(runtime, programs, tokens);
    return new Local16(runtime, programs, tokens, sender);
  } catch (error) {
    runtime.stop();
    throw error;
  }
}

class Local16 implements SvmLocal {
  readonly ccipVersion = "1.6" as const;
  readonly connection: Connection;
  readonly payer: Keypair;
  readonly ccip = {
    router: new PublicKey(CCIP_PROGRAMS_1_6.ccip_router),
    offRamp: new PublicKey(CCIP_PROGRAMS_1_6.ccip_offramp),
    chainSelector: SVM_CHAIN_SELECTOR,
  };
  private readonly runtime: SvmRuntime;
  private readonly programs: CcipPrograms16;
  private readonly tokens: TokenSupport;
  private readonly sender: Sender16;
  private readonly offRampConfig = pda([Buffer.from(SEEDS.config)], this.ccip.offRamp);

  constructor(runtime: SvmRuntime, programs: CcipPrograms16, tokens: TokenSupport, sender: Sender16) {
    this.runtime = runtime;
    this.programs = programs;
    this.tokens = tokens;
    this.sender = sender;
    this.connection = runtime.connection;
    this.payer = runtime.payer;
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

  mintTokens(mint: PublicKey, owner: PublicKey, amount: bigint): Promise<PublicKey> {
    return this.tokens.mintTokens(mint, owner, amount);
  }

  send(options: SvmSendOptions): Promise<SvmSentMessage> {
    return this.sender.send(options);
  }

  sentMessages(options?: SentMessagesOptions): Promise<SvmSentMessage[]> {
    return this.sender.sentMessages(options);
  }

  sendAndConfirm(transaction: Transaction, signers: Keypair[] = []): Promise<string> {
    return this.runtime.sendAndConfirm(transaction, signers);
  }

  stop(): void {
    this.runtime.stop();
  }

  /**
   * Commits a one-message root and executes the message. `messageNumber` is ignored: on a 1.6 lane the sequence
   * number of a message is the OffRamp's next expected one (the commit must start there).
   */
  async deliver(options: DeliverOptions): Promise<DeliverResult> {
    const { computeUnits, receiverAccounts, receiverWritableBitmap, data } = checkDeliverOptions(options);
    const token = options.token ? this.tokens.resolve(options.token) : undefined;
    const sourceChainSelector = options.sourceChainSelector ?? EVM_CHAIN_SELECTOR;
    const { onRamp, sequenceNumber } = await this.laneState(sourceChainSelector, options.onRampAddress);

    const sender = Buffer.from(options.sender ?? DEFAULT_SENDER);
    const idFields = { sourceChainSelector, destChainSelector: SVM_CHAIN_SELECTOR, sequenceNumber, sender, data, onRamp };
    const message: Message16 = {
      ...idFields,
      messageId: localMessageId(idFields, options.receiverProgram ?? PublicKey.default),
      computeUnits,
      writableBitmap: receiverWritableBitmap,
      // A token-only message has no receiver program and no messaging accounts.
      receiverAndAccounts: options.receiverProgram ? [options.receiverProgram, ...receiverAccounts] : [],
      ...(token && {
        tokenReceiver: token.receiver,
        tokenAmounts: [
          {
            sourcePool: token.evmPool,
            destToken: token.mint,
            destGasAmount: 100,
            extraData: encodeDecimals(token.evmDecimals),
            amount: token.amount,
          },
        ],
      }),
    };
    const messageId = "0x" + Buffer.from(message.messageId).toString("hex");

    // Commit: the leaf is the root of a one-message tree.
    const root = leafHash(message);
    const commitReport = encodeCommitReport(message, root);
    const commitContext = reportContext(COMMIT_CONFIG_DIGEST, sequenceNumber);
    const { rs, ss, rawVs } = signCommit(commitReport, commitContext, committee16().slice(0, F_1_6 + 1));
    const commit = await this.programs.offRamp.methods
      .commit(commitContext, commitReport, rs, ss, rawVs)
      .accounts(this.commitAccounts(sourceChainSelector, root))
      .instruction();
    const committed = await this.sendInstructions([ComputeBudgetProgram.setComputeUnitLimit({ units: COMMIT_COMPUTE_UNITS }), commit]);
    if (committed.err !== null) {
      return {
        messageId,
        state: "Failure",
        computeUnitsUsed: committed.computeUnitsUsed,
        logs: committed.logs,
        error: `commit failed: ${describeFailure(committed.err, committed.logs, committed.computeUnitsUsed, COMMIT_COMPUTE_UNITS)}`,
      };
    }

    // Execute: message accounts follow the receiver and its external-execution signer. A bit set in the
    // bitmap makes the account writable in the transaction, which the OffRamp checks. The token accounts come
    // after them, and `token_indexes` tells the OffRamp where they start.
    const messageAccounts = options.receiverProgram
      ? [
          { pubkey: options.receiverProgram, isWritable: false, isSigner: false },
          {
            pubkey: pda([Buffer.from("external_execution_config"), options.receiverProgram.toBuffer()], this.ccip.offRamp),
            isWritable: false,
            isSigner: false,
          },
          ...receiverAccounts.map((pubkey, i) => ({
            pubkey,
            isWritable: i < 64 && ((receiverWritableBitmap >> BigInt(i)) & 1n) === 1n,
            isSigner: false,
          })),
        ]
      : [];
    const tokenAccounts = token
      ? this.tokens.accounts16(token, sourceChainSelector).map((account) => ({ ...account, isSigner: false }))
      : [];
    const execute = await this.programs.offRamp.methods
      .execute(
        encodeExecutionReport(message),
        reportContext(EXECUTION_CONFIG_DIGEST, sequenceNumber),
        token ? Buffer.from([messageAccounts.length]) : Buffer.alloc(0),
      )
      .accounts(this.executeAccounts(sourceChainSelector, root))
      .remainingAccounts([...messageAccounts, ...tokenAccounts])
      .instruction();
    const outcome = await this.sendWithLookupTable(computeUnits, execute);
    return {
      messageId,
      state: outcome.err === null ? "Success" : "Failure",
      computeUnitsUsed: outcome.computeUnitsUsed,
      logs: outcome.logs,
      ...(outcome.err === null ? {} : { error: describeFailure(outcome.err, outcome.logs, outcome.computeUnitsUsed, computeUnits) }),
    };
  }

  private commitAccounts(sourceChainSelector: bigint, root: Buffer) {
    const feeBillingSigner = pda([Buffer.from("fee_billing_signer")], this.ccip.offRamp);
    const feeQuoter = new PublicKey(CCIP_PROGRAMS_1_6.fee_quoter);
    const rmn = new PublicKey(CCIP_PROGRAMS_1_6.rmn_remote);
    return {
      config: this.offRampConfig,
      referenceAddresses: pda([Buffer.from(SEEDS.referenceAddresses)], this.ccip.offRamp),
      sourceChain: pda([Buffer.from(SEEDS.sourceChain), selectorSeed(sourceChainSelector)], this.ccip.offRamp),
      commitReport: pda([Buffer.from("commit_report"), selectorSeed(sourceChainSelector), root], this.ccip.offRamp),
      authority: this.payer.publicKey,
      systemProgram: SystemProgram.programId,
      sysvarInstructions: SYSVAR_INSTRUCTIONS_PUBKEY,
      feeBillingSigner,
      feeQuoter,
      feeQuoterAllowedPriceUpdater: pda([Buffer.from("allowed_price_updater"), feeBillingSigner.toBuffer()], feeQuoter),
      feeQuoterConfig: pda([Buffer.from(SEEDS.config)], feeQuoter),
      rmnRemote: rmn,
      rmnRemoteCurses: pda([Buffer.from(SEEDS.curses)], rmn),
      rmnRemoteConfig: pda([Buffer.from(SEEDS.config)], rmn),
    };
  }

  private executeAccounts(sourceChainSelector: bigint, root: Buffer) {
    const rmn = new PublicKey(CCIP_PROGRAMS_1_6.rmn_remote);
    return {
      config: this.offRampConfig,
      referenceAddresses: pda([Buffer.from(SEEDS.referenceAddresses)], this.ccip.offRamp),
      sourceChain: pda([Buffer.from(SEEDS.sourceChain), selectorSeed(sourceChainSelector)], this.ccip.offRamp),
      commitReport: pda([Buffer.from("commit_report"), selectorSeed(sourceChainSelector), root], this.ccip.offRamp),
      offramp: this.ccip.offRamp,
      allowedOfframp: allowedOfframp(this.ccip.router, this.ccip.offRamp, sourceChainSelector),
      authority: this.payer.publicKey,
      systemProgram: SystemProgram.programId,
      sysvarInstructions: SYSVAR_INSTRUCTIONS_PUBKEY,
      rmnRemote: rmn,
      rmnRemoteCurses: pda([Buffer.from(SEEDS.curses)], rmn),
      rmnRemoteConfig: pda([Buffer.from(SEEDS.config)], rmn),
    };
  }

  /**
   * The onRamp a message from `sourceChainSelector` carries and the sequence number the next commit must start
   * at, both read from the OffRamp's source-chain account. The OffRamp accepts exactly one onRamp per source
   * chain, as on a live lane: the placeholder from startup until the first explicit `requested` onRamp replaces
   * it through the OffRamp's own admin instruction. After that, a different `requested` onRamp is returned as is,
   * and the real OffRamp rejects the commit.
   */
  private async laneState(sourceChainSelector: bigint, requested?: Uint8Array): Promise<{ onRamp: Buffer; sequenceNumber: bigint }> {
    const sourceChain = pda([Buffer.from(SEEDS.sourceChain), selectorSeed(sourceChainSelector)], this.ccip.offRamp);
    const read = async () => this.programs.offRamp.account.sourceChain.fetchNullable(sourceChain, "confirmed");
    let state = await read();
    if (!state) {
      throw new Error(`deliver: source chain ${sourceChainSelector} is not configured; only ${EVM_CHAIN_SELECTOR} is`);
    }
    const accepted = (): Buffer => Buffer.from(state.config.onRamp.bytes.slice(0, state.config.onRamp.len));
    if (requested !== undefined) {
      const onRamp = Buffer.from(requested);
      if (accepted().equals(PLACEHOLDER_ON_RAMP_1_6) && !onRamp.equals(accepted())) {
        const padded = Buffer.alloc(64);
        onRamp.copy(padded);
        const update = await this.programs.offRamp.methods
          .updateSourceChainConfig(new BN(sourceChainSelector.toString()), {
            ...state.config,
            onRamp: { bytes: Array.from(padded), len: onRamp.length },
          })
          .accounts({ sourceChain, config: this.offRampConfig, authority: this.payer.publicKey })
          .instruction();
        await this.runtime.sendAndConfirm(new Transaction().add(update));
        state = await read();
      } else if (!onRamp.equals(accepted())) {
        // A different onRamp than the lane accepts: it goes into the leaf and the OffRamp's commit rejects it.
        return { onRamp, sequenceNumber: BigInt(state.state.minSeqNr.toString()) };
      }
    }
    return { onRamp: accepted(), sequenceNumber: BigInt(state.state.minSeqNr.toString()) };
  }

  private async sendInstructions(instructions: TransactionInstruction[]) {
    const message = new TransactionMessage({
      payerKey: this.payer.publicKey,
      recentBlockhash: (await this.connection.getLatestBlockhash()).blockhash,
      instructions,
    }).compileToV0Message();
    const transaction = new VersionedTransaction(message);
    transaction.sign([this.payer]);
    return sendForOutcome(this.runtime, transaction);
  }

  /** The execute account list does not always fit a legacy transaction, so its accounts go in a lookup table. */
  private async sendWithLookupTable(computeUnits: number, execute: TransactionInstruction) {
    const lookupTable = await writeLookupTable(this.runtime, execute.keys.map((key) => key.pubkey));
    const message = new TransactionMessage({
      payerKey: this.payer.publicKey,
      recentBlockhash: (await this.connection.getLatestBlockhash()).blockhash,
      instructions: [ComputeBudgetProgram.setComputeUnitLimit({ units: computeUnits }), execute],
    }).compileToV0Message([lookupTable]);
    const transaction = new VersionedTransaction(message);
    transaction.sign([this.payer]);
    return sendForOutcome(this.runtime, transaction);
  }
}
