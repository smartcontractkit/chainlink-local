// Solana -> EVM: the part of `send()` and `sentMessages()` both CCIP versions share. A version's class (`send16.ts`,
// `send20.ts`) builds the real `ccip_send` / `ccip_send_v2` instruction and decodes the event the Router emits for it;
// this class checks the options, funds the sender, sends the transaction and finds messages in transactions.

import { createHash } from "node:crypto";
import anchor from "@anchor-lang/core";
import {
  ComputeBudgetProgram,
  PublicKey,
  TransactionInstruction,
  TransactionMessage,
  VersionedTransaction,
  type Keypair,
  type VersionedTransactionResponse,
} from "@solana/web3.js";
import { pda } from "./constants.ts";
import { describeFailure, sendForOutcome, writeLookupTable } from "./execution.ts";
import type { SvmRuntime } from "./runtime.ts";
import { TOKEN_PROGRAM, associatedTokenAddress, parseEvmAddress, type TokenSupport } from "./tokens.ts";

/** A message sent from the local Solana chain through the real Router, decoded from the event the Router emitted. */
export interface SvmSentMessage {
  ccipVersion: "1.6" | "2.0";
  signature: string;
  /** `0x` + 32 bytes. */
  messageId: string;
  sourceChainSelector: bigint;
  destChainSelector: bigint;
  /** 1.6: `header.sequence_number`. 2.0: `message_number`. */
  sequenceNumber: bigint;
  /** 1.6 only; `0n` on 2.0. */
  nonce: bigint;
  /** The 32-byte Solana address of the sender. */
  sender: Uint8Array;
  /** `0x` + 20 bytes, checksummed. */
  receiver: string;
  data: Uint8Array;
  /** 1.6: from the extra args. 2.0: `ccip_receive_gas_limit`. */
  gasLimit: bigint;
  /** bytes4 as hex: `"0x00000000"` on 1.6. */
  finality: string;
  token?: {
    mint: PublicKey;
    /** 1.6: the pool state PDA. 2.0: the pool address the message carries. */
    sourcePool: Uint8Array;
    /** `0x` + 20 bytes, checksummed. */
    destToken: string;
    /** In the mint's smallest units. */
    amount: bigint;
    /** `abi.encode(uint8 mintDecimals)`: the EVM side converts the amount with it. */
    extraData: Uint8Array;
  };
  /** 2.0 only: the `MessageV1` wire bytes, whose keccak256 is `messageId`. */
  encodedMessage?: Uint8Array;
}

export interface SvmSendOptions {
  /** Signs the send and pays the fee, in native SOL. Topped up with SOL when it holds less than 1. */
  sender: Keypair;
  /** `0x` + 20-byte EVM address. */
  receiver: string;
  /** Default: empty. */
  data?: Uint8Array;
  /** Gas the EVM receiver gets. Default 200,000. */
  gasLimit?: bigint;
  /** One token, linked with `linkToken`, taken from the sender's associated token account. `amount` in mint decimals. */
  token?: { mint: PublicKey; amount: bigint };
}

export interface SentMessagesOptions {
  /** Only the messages sent in this transaction. */
  signature?: string;
  /** Only the messages sent in Router transactions after this one, oldest first. Default: all since start. */
  afterSignature?: string;
}

/** The wrapped SOL mint, the billing token of a native-SOL fee. Surfnet has it from genesis. */
export const NATIVE_MINT = new PublicKey("So11111111111111111111111111111111111111112");

/** A FeeQuoter `u224` (28 big-endian bytes) as the byte array Anchor expects. */
export function u224(value: bigint): number[] {
  return Array.from(Buffer.from(value.toString(16).padStart(56, "0"), "hex"));
}

export const DEFAULT_SEND_GAS_LIMIT = 200_000n;
/** A send used 107,000 to 250,000 compute units in measurements; the cap of one transaction. */
const SEND_COMPUTE_UNITS = 1_400_000;
const MAX_UINT32 = 0xffffffffn;
const MAX_UINT64 = (1n << 64n) - 1n;
const SIGNATURES_PAGE = 1000;
/** A send is one transaction (1,232 bytes) whose instruction carries the data: 600 bytes fit on both lanes, 700 or more do not on 2.0. */
const MAX_SEND_DATA_BYTES = 600;

/** The `send()` arguments both lanes validate the same way, with the optional ones defaulted. */
export interface CheckedSend {
  sender: Keypair;
  /** 20 raw bytes. */
  receiver: Buffer;
  data: Buffer;
  gasLimit: bigint;
  token?: { mint: PublicKey; amount: bigint };
}

export function checkSendOptions(options: SvmSendOptions, tokens: TokenSupport): CheckedSend {
  const { sender, token } = options;
  if (!(sender?.publicKey instanceof PublicKey) || !(sender.secretKey instanceof Uint8Array)) {
    throw new Error("send: sender must be a Keypair");
  }
  const receiver = parseEvmAddress("send: receiver", options.receiver);
  if (options.data !== undefined && !(options.data instanceof Uint8Array)) throw new Error("send: data must be a Uint8Array");
  if ((options.data?.length ?? 0) > MAX_SEND_DATA_BYTES) {
    throw new Error(`send: data is ${options.data!.length} bytes; a send is one Solana transaction and carries at most ${MAX_SEND_DATA_BYTES} bytes of data`);
  }
  const gasLimit = options.gasLimit ?? DEFAULT_SEND_GAS_LIMIT;
  if (typeof gasLimit !== "bigint" || gasLimit < 0n || gasLimit > MAX_UINT32) {
    throw new Error(`send: gasLimit must be a bigint in 0..2^32-1, got ${String(gasLimit)}`);
  }
  if (token !== undefined) {
    if (!(token.mint instanceof PublicKey)) throw new Error("send: token.mint must be a PublicKey");
    if (typeof token.amount !== "bigint" || token.amount <= 0n || token.amount > MAX_UINT64) {
      throw new Error(`send: token.amount must be a bigint in 1..2^64-1 (mint decimals), got ${String(token.amount)}`);
    }
    if (!tokens.isLinked(token.mint)) {
      throw new Error(
        `send: mint ${token.mint.toBase58()} is not linked to an EVM token; call createBurnMintToken and linkToken first`,
      );
    }
  }
  return { sender, receiver, data: Buffer.from(options.data ?? []), gasLimit, token };
}

/** First 8 bytes of `sha256("event:<name>")`, the Anchor event discriminator. */
export const eventDiscriminator = (name: string): Buffer => createHash("sha256").update(`event:${name}`).digest().subarray(0, 8);

/** Little-endian (1.6 `CrossChainAmount`) or big-endian (2.0) 256-bit integer. */
export function readUint256(bytes: ArrayLike<number>, order: "le" | "be"): bigint {
  const be = order === "le" ? Buffer.from(bytes).reverse() : Buffer.from(bytes);
  return BigInt("0x" + be.toString("hex"));
}

export abstract class SendSupport {
  protected readonly runtime: SvmRuntime;
  protected readonly tokens: TokenSupport;
  protected readonly router: PublicKey;
  /** The PDA the Router bills fees and pulls tokens with: what the sender approves as delegate. */
  protected readonly billingSigner: PublicKey;
  /** Newest Router signature once the setup is done: later transactions are the ones `sentMessages()` looks at. */
  private baseline: string | undefined;

  protected constructor(runtime: SvmRuntime, tokens: TokenSupport, router: PublicKey) {
    this.runtime = runtime;
    this.tokens = tokens;
    this.router = router;
    this.billingSigner = pda([Buffer.from("fee_billing_signer")], router);
  }

  /** Builds the real send instruction (without the approve) for checked options. */
  protected abstract buildSend(send: CheckedSend): Promise<TransactionInstruction>;
  /** Decodes the message an inner instruction of `programId` carries, or undefined if it carries none. */
  protected abstract decodeEvent(programId: PublicKey, data: Buffer, signature: string): SvmSentMessage | undefined;

  /** Called once the version's setup transactions are done: the messages of later transactions are the user's. */
  protected async markSetupDone(): Promise<void> {
    const [newest] = await this.runtime.connection.getSignaturesForAddress(this.router, { limit: 1 }, "confirmed");
    this.baseline = newest?.signature;
  }

  async send(options: SvmSendOptions): Promise<SvmSentMessage> {
    const send = checkSendOptions(options, this.tokens);
    const { runtime } = this;
    const { payer, connection } = runtime;
    const senderKey = send.sender.publicKey;
    // The fee is native SOL taken from the sender (and the nonce account's rent, on 1.6). As on a real chain, the
    // sender must already hold it; an unfunded sender fails with the Router's own error.

    const instruction = await this.buildSend(send);
    const instructions = [ComputeBudgetProgram.setComputeUnitLimit({ units: SEND_COMPUTE_UNITS })];
    if (send.token) {
      // SPL Token `Approve` (tag 4): the Router's billing signer becomes the delegate that lets the pool burn.
      const data = Buffer.alloc(9);
      data[0] = 4;
      data.writeBigUInt64LE(send.token.amount, 1);
      instructions.push(
        new TransactionInstruction({
          programId: TOKEN_PROGRAM,
          keys: [
            { pubkey: associatedTokenAddress(send.token.mint, senderKey), isSigner: false, isWritable: true },
            { pubkey: this.billingSigner, isSigner: false, isWritable: false },
            { pubkey: senderKey, isSigner: true, isWritable: false },
          ],
          data,
        }),
      );
    }
    instructions.push(instruction);

    // The account list of a send does not fit a legacy transaction, so its accounts go in a lookup table.
    const lookupTable = await writeLookupTable(runtime, instruction.keys.map((key) => key.pubkey));
    const message = new TransactionMessage({
      payerKey: payer.publicKey,
      recentBlockhash: (await connection.getLatestBlockhash()).blockhash,
      instructions,
    }).compileToV0Message([lookupTable]);
    const transaction = new VersionedTransaction(message);
    transaction.sign(senderKey.equals(payer.publicKey) ? [payer] : [payer, send.sender]);

    const outcome = await sendForOutcome(runtime, transaction);
    if (outcome.err !== null) {
      throw new Error(`send failed: ${describeFailure(outcome.err, outcome.logs, outcome.computeUnitsUsed, SEND_COMPUTE_UNITS)}`);
    }
    const [sent] = this.decodeTransaction(outcome.signature, outcome.transaction);
    if (!sent) throw new Error(`send: transaction ${outcome.signature} succeeded but emitted no CCIP message`);
    return sent;
  }

  async sentMessages(options: SentMessagesOptions = {}): Promise<SvmSentMessage[]> {
    const { signature, afterSignature } = options;
    const { connection } = this.runtime;
    if (signature !== undefined && afterSignature !== undefined) {
      throw new Error("sentMessages: pass signature or afterSignature, not both");
    }
    if (signature !== undefined) {
      const transaction = await connection.getTransaction(signature, { commitment: "confirmed", maxSupportedTransactionVersion: 0 });
      if (!transaction) throw new Error(`sentMessages: transaction ${signature} was not found`);
      return this.decodeTransaction(signature, transaction);
    }

    // Router transactions, newest first, down to the one to start after.
    const stop = afterSignature ?? this.baseline;
    const signatures: string[] = [];
    let before: string | undefined;
    for (let reachedStop = false; !reachedStop; ) {
      const page = await connection.getSignaturesForAddress(this.router, { before, limit: SIGNATURES_PAGE }, "confirmed");
      for (const entry of page) {
        if (entry.signature === stop) {
          reachedStop = true;
          break;
        }
        if (!entry.err) signatures.push(entry.signature);
      }
      if (page.length < SIGNATURES_PAGE) {
        if (!reachedStop && afterSignature !== undefined) {
          throw new Error(`sentMessages: ${afterSignature} is not a transaction of the Router`);
        }
        break;
      }
      before = page[page.length - 1].signature;
    }

    const messages: SvmSentMessage[] = [];
    for (const sig of signatures.reverse()) {
      const transaction = await connection.getTransaction(sig, { commitment: "confirmed", maxSupportedTransactionVersion: 0 });
      if (transaction) messages.push(...this.decodeTransaction(sig, transaction));
    }
    return messages;
  }

  /** The messages sent in one confirmed transaction, in order: every inner instruction is offered to the version's decoder. */
  private decodeTransaction(signature: string, transaction: VersionedTransactionResponse): SvmSentMessage[] {
    const { meta } = transaction;
    if (!meta || meta.err) return [];
    const loaded = meta.loadedAddresses;
    const keys = transaction.transaction.message.getAccountKeys({
      accountKeysFromLookups: loaded && {
        writable: loaded.writable.map((key) => new PublicKey(key)),
        readonly: loaded.readonly.map((key) => new PublicKey(key)),
      },
    });
    const messages: SvmSentMessage[] = [];
    for (const { instructions } of meta.innerInstructions ?? []) {
      for (const instruction of instructions) {
        const programId = keys.get(instruction.programIdIndex);
        if (!programId) continue;
        const sent = this.decodeEvent(programId, Buffer.from(anchor.utils.bytes.bs58.decode(instruction.data)), signature);
        if (sent) messages.push(sent);
      }
    }
    return messages;
  }
}
