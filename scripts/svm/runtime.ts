// The Solana validator: an embedded, offline Surfnet running inside the test process.
//
// Ported in part from the prototype by Stefano Magini (magiodev-cll/chainlink-local, feat/svm-local,
// src/ccip-svm/src/surfpool.ts): the cheatcode wrappers (`surfnet_writeProgram` chunking,
// `surfnet_setProgramAuthority`, `surfnet_setAccount`) and the polling `confirmSignature`. The
// prototype spawned the `surfpool` binary; this uses the in-process `@solana/surfpool` package.

import { Surfnet } from "@solana/surfpool";
import { Connection, Keypair, PublicKey, type Transaction } from "@solana/web3.js";

/** Largest slice of a program sent in one `surfnet_writeProgram` call. */
export const PROGRAM_CHUNK_BYTES = 1024 * 1024;

/** Subset of the `surfnet_setAccount` update the harness needs. Omitted fields stay unchanged. */
export interface AccountPatch {
  lamports?: number | bigint;
  owner?: PublicKey;
  data?: Uint8Array;
  executable?: boolean;
}

/** Subset of the `surfnet_setTokenAccount` update. */
export interface TokenAccountPatch {
  amount?: number | bigint;
  delegate?: PublicKey;
  clearDelegate?: boolean;
  state?: "initialized" | "frozen" | "uninitialized";
  delegatedAmount?: number | bigint;
}

/** Slot, epoch or Unix timestamp (ms) to jump to. Exactly one. */
export type TimeTarget =
  | { absoluteSlot: number }
  | { absoluteEpoch: number }
  | { absoluteTimestamp: number };

/**
 * Wait for a transaction without WebSocket subscriptions.
 *
 * `connection.confirmTransaction` subscribes over WebSocket, which the prototype found unreliable
 * against Surfpool. Polling `getSignatureStatuses` always works and fails after a bounded wait.
 */
export async function confirmSignature(
  connection: Connection,
  signature: string,
  timeoutMs = 30_000,
): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const { value } = await connection.getSignatureStatuses([signature]);
    const status = value[0];
    if (status?.err) {
      throw new Error(`transaction ${signature} failed: ${JSON.stringify(status.err)}`);
    }
    if (status?.confirmationStatus === "confirmed" || status?.confirmationStatus === "finalized") {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(`transaction ${signature} was not confirmed within ${timeoutMs}ms`);
}

export class SvmRuntime {
  readonly rpcUrl: string;
  readonly wsUrl: string;
  readonly connection: Connection;
  /** Funded by the Surfnet at boot. Also the upgrade authority of the deployed programs. */
  readonly payer: Keypair;
  private surfnet: Surfnet | undefined;

  private constructor(surfnet: Surfnet) {
    this.surfnet = surfnet;
    this.rpcUrl = surfnet.rpcUrl;
    this.wsUrl = surfnet.wsUrl;
    // Pass the real WebSocket endpoint: web3.js otherwise guesses the HTTP port + 1, which is only right when the
    // free ports happen to be consecutive (usually on macOS, not on Linux). With a wrong guess, subscriptions such as
    // `connection.confirmTransaction` never connect, and the client keeps reconnecting forever.
    this.connection = new Connection(this.rpcUrl, { commitment: "confirmed", wsEndpoint: this.wsUrl });
    this.payer = Keypair.fromSecretKey(surfnet.payerSecretKey);
  }

  /** Boots an offline Surfnet (no remote datasource) on free local ports. Synchronous underneath. */
  static start(): SvmRuntime {
    return new SvmRuntime(Surfnet.startWithConfig({ offline: true }));
  }

  /** Frees the Surfnet's ports. Safe to call more than once. */
  stop(): void {
    // Close the connection's WebSocket first (web3.js keeps it private). A normal close (code 1000) stops its
    // reconnect loop, so a subscription left open cannot keep the process alive against the stopped Surfnet.
    (this.connection as unknown as { _rpcWebSocket?: { close(): void } })._rpcWebSocket?.close();
    this.surfnet?.stop();
    this.surfnet = undefined;
  }

  /** Calls any JSON-RPC method, including `surfnet_*` cheatcodes. Throws on an RPC error. */
  async rpc(method: string, params: unknown[]): Promise<unknown> {
    const response = await fetch(this.rpcUrl, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
    });
    const body = (await response.json()) as { result?: unknown; error?: unknown };
    if (body.error) throw new Error(`${method} failed: ${JSON.stringify(body.error)}`);
    return body.result;
  }

  /** Writes program bytes at `programId` in chunks. The program has no upgrade authority until one is set. */
  async writeProgram(programId: PublicKey, bytes: Uint8Array): Promise<void> {
    for (let offset = 0; offset < bytes.length; offset += PROGRAM_CHUNK_BYTES) {
      const chunk = bytes.subarray(offset, offset + PROGRAM_CHUNK_BYTES);
      await this.rpc("surfnet_writeProgram", [
        programId.toBase58(),
        Buffer.from(chunk).toString("hex"),
        offset,
      ]);
    }
  }

  async setProgramAuthority(programId: PublicKey, authority: PublicKey): Promise<void> {
    await this.rpc("surfnet_setProgramAuthority", [programId.toBase58(), authority.toBase58()]);
  }

  async setAccount(address: PublicKey, patch: AccountPatch): Promise<void> {
    const update: Record<string, unknown> = {};
    if (patch.lamports !== undefined) update.lamports = Number(patch.lamports);
    if (patch.owner) update.owner = patch.owner.toBase58();
    if (patch.data) update.data = Buffer.from(patch.data).toString("hex");
    if (patch.executable !== undefined) update.executable = patch.executable;
    await this.rpc("surfnet_setAccount", [address.toBase58(), update]);
  }

  /** Creates or updates the token account (associated token account) of `owner` for `mint`. */
  async setTokenAccount(
    owner: PublicKey,
    mint: PublicKey,
    patch: TokenAccountPatch,
    tokenProgram?: PublicKey,
  ): Promise<void> {
    const update: Record<string, unknown> = { ...patch };
    if (patch.amount !== undefined) update.amount = Number(patch.amount);
    if (patch.delegatedAmount !== undefined) update.delegatedAmount = Number(patch.delegatedAmount);
    if (patch.delegate) update.delegate = patch.delegate.toBase58();
    const params = [owner.toBase58(), mint.toBase58(), update];
    if (tokenProgram) params.push(tokenProgram.toBase58());
    await this.rpc("surfnet_setTokenAccount", params);
  }

  /** Jumps the clock. Returns the new epoch info. */
  async timeTravel(target: TimeTarget): Promise<{ absoluteSlot: number; epoch: number }> {
    return (await this.rpc("surfnet_timeTravel", [target])) as { absoluteSlot: number; epoch: number };
  }

  /** Signs with the payer plus `signers`, sends, and waits by polling. Returns the signature. */
  async sendAndConfirm(transaction: Transaction, signers: Keypair[] = []): Promise<string> {
    transaction.feePayer ??= this.payer.publicKey;
    transaction.recentBlockhash = (await this.connection.getLatestBlockhash()).blockhash;
    transaction.sign(this.payer, ...signers);
    const signature = await this.connection.sendRawTransaction(transaction.serialize());
    await confirmSignature(this.connection, signature);
    return signature;
  }
}
