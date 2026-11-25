// The generic staged account resolver every CCIP 2.0 program exposes (`resolve_accounts_start`).
//
// Ported in part from the prototype by Stefano Magini (magiodev-cll/chainlink-local, feat/svm-local,
// src/ccip-svm/src/resolver.ts): `encodeResolveParams`, `decodeResponse` and the resolution loop.
// Resolution is read-only simulation, so it never changes state.

import {
  Keypair,
  PublicKey,
  TransactionInstruction,
  TransactionMessage,
  VersionedTransaction,
  type Connection,
} from "@solana/web3.js";

export interface ResolvedAccount {
  pubkey: PublicKey;
  isSigner: boolean;
  isWritable: boolean;
}

export interface ResolveResult {
  accounts: ResolvedAccount[];
  /** Metadata to pass back to the final instruction. */
  metadata: Uint8Array;
  /** Names of the resolver stages that ran, in order. */
  trace: string[];
}

interface IdlInstruction {
  name: string;
  discriminator: number[];
}

const u32le = (n: number) => {
  const buf = Buffer.alloc(4);
  buf.writeUInt32LE(n);
  return buf;
};

/** Borsh `ResolveAccountsParams { caller: Pubkey, ix_data: Vec<u8>, metadata: Vec<u8> }`. */
function encodeResolveParams(caller: PublicKey, ixData: Uint8Array, metadata: Uint8Array): Buffer {
  return Buffer.concat([caller.toBuffer(), u32le(ixData.length), ixData, u32le(metadata.length), metadata]);
}

function decodeResponse(buf: Buffer) {
  let offset = 0;
  const u32 = () => {
    const value = buf.readUInt32LE(offset);
    offset += 4;
    return value;
  };
  const pubkey = () => new PublicKey(buf.subarray(offset, (offset += 32)));

  const askAgain = Array.from({ length: u32() }, pubkey);
  const accounts: ResolvedAccount[] = [];
  for (let i = 0, count = u32(); i < count; i++) {
    accounts.push({ pubkey: pubkey(), isSigner: buf[offset++] === 1, isWritable: buf[offset++] === 1 });
  }
  const lookupTableCount = u32();
  offset += 32 * lookupTableCount;
  const nextDiscriminator = buf[offset++] ? Buffer.from(buf.subarray(offset, (offset += 8))) : null;
  const metadataLength = u32();
  const metadata = Buffer.from(buf.subarray(offset, offset + metadataLength));
  return { askAgain, accounts, nextDiscriminator, metadata };
}

/**
 * Drives `resolve_accounts_start` and the stages it names until none is left. `ixData` is the
 * Borsh-encoded data of the instruction being resolved (called with empty resolution metadata).
 */
export async function resolveAccounts(opts: {
  connection: Connection;
  programId: PublicKey;
  idl: { instructions: IdlInstruction[] };
  payer: Keypair;
  config: PublicKey;
  ixData: Uint8Array;
  maxRounds?: number;
}): Promise<ResolveResult> {
  const { connection, programId, idl, payer } = opts;
  const stageName = new Map(idl.instructions.map((ix) => [Buffer.from(ix.discriminator).toString("hex"), ix.name]));
  const start = idl.instructions.find((ix) => ix.name === "resolve_accounts_start");
  if (!start) throw new Error("program IDL has no resolve_accounts_start");

  const accounts: ResolvedAccount[] = [];
  const trace: string[] = [];
  let discriminator = Buffer.from(start.discriminator);
  let metadata: Uint8Array = new Uint8Array(0);
  let askKeys = [opts.config];

  for (let round = 0; round < (opts.maxRounds ?? 32); round++) {
    const stage = stageName.get(discriminator.toString("hex")) ?? discriminator.toString("hex");
    const message = new TransactionMessage({
      payerKey: payer.publicKey,
      // Replaced by the node: Surfnet rejects a simulated blockhash once a few hundred slots old.
      recentBlockhash: PublicKey.default.toBase58(),
      instructions: [
        new TransactionInstruction({
          programId,
          keys: askKeys.map((pubkey) => ({ pubkey, isSigner: false, isWritable: false })),
          data: Buffer.concat([discriminator, encodeResolveParams(payer.publicKey, opts.ixData, metadata)]),
        }),
      ],
    }).compileToV0Message();
    const { value } = await connection.simulateTransaction(new VersionedTransaction(message), {
      replaceRecentBlockhash: true,
      sigVerify: false,
    });
    if (value.err) {
      throw new Error(`account resolution failed at ${stage}: ${JSON.stringify(value.err)}\n${(value.logs ?? []).join("\n")}`);
    }
    const prefix = `Program return: ${programId.toBase58()} `;
    const line = (value.logs ?? []).find((l) => l.startsWith(prefix));
    if (!line) throw new Error(`account resolution at ${stage} returned no data`);

    const response = decodeResponse(Buffer.from(line.slice(prefix.length), "base64"));
    accounts.push(...response.accounts);
    trace.push(stage);
    if (!response.nextDiscriminator) return { accounts, metadata: response.metadata, trace };

    discriminator = response.nextDiscriminator;
    metadata = response.metadata;
    askKeys = response.askAgain;
  }
  throw new Error("account resolution exceeded the maximum number of rounds");
}
