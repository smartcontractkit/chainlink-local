// Local trust layer: initialises the deployed CCIP 2.0 programs with local keys so that a message
// signed by the local committee passes the real OffRamp.
//
// Ported in part from the prototype by Stefano Magini (magiodev-cll/chainlink-local, feat/svm-local,
// src/ccip-svm/src/simulator.ts, `bootstrap`). Differences: instructions are packed into a few
// transactions instead of one each, the LINK stand-in mint is written with a cheatcode (no spl-token
// dependency), and the executor is not initialised: `ccip_send_v2` uses the NO_EXECUTION executor (send20.ts).

import anchor from "@anchor-lang/core";
import { Keypair, PublicKey, SystemProgram, Transaction, TransactionInstruction } from "@solana/web3.js";
import { readIdl } from "./artifacts.ts";
import { addressOf, sortedCommittee } from "./signatures.ts";
import { CCIP_PROGRAMS } from "./programs.ts";
import {
  EVM_CHAIN_SELECTOR,
  SEEDS,
  SVM_CHAIN_SELECTOR,
  pda,
  programDataAddress,
  selectorSeed,
} from "./constants.ts";
import type { SvmRuntime } from "./runtime.ts";

const { AnchorProvider, BN, Program, Wallet } = anchor;

export const COMMITTEE_SIZE = 8;
export const COMMITTEE_THRESHOLD = 1;

const TOKEN_PROGRAM_ID = new PublicKey("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
const MAX_TRANSACTION_BYTES = 1232;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type AnchorProgram = any;

/** Anchor programs of the CCIP deployment, built from the bundle IDLs. */
export function loadPrograms(runtime: SvmRuntime, bundleDir: string) {
  const provider = new AnchorProvider(runtime.connection, new Wallet(runtime.payer), { commitment: "confirmed" });
  const program = (name: string): AnchorProgram => new Program(readIdl(bundleDir, name) as never, provider);
  return {
    offRamp: program("ccip_offramp"),
    router: program("ccip_router"),
    feeQuoter: program("fee_quoter"),
    rmnRemote: program("rmn_remote"),
    committeeVerifier: program("committee_verifier"),
  };
}

export type CcipPrograms = ReturnType<typeof loadPrograms>;

/** Sends `instructions` in as few transactions as fit the size limit, preserving their order. */
export async function sendPacked(runtime: SvmRuntime, instructions: TransactionInstruction[]): Promise<void> {
  const fits = async (batch: TransactionInstruction[]) => {
    const tx = new Transaction({ feePayer: runtime.payer.publicKey, recentBlockhash: "11111111111111111111111111111111" });
    tx.add(...batch);
    try {
      return tx.serializeMessage().length + 1 + 64 <= MAX_TRANSACTION_BYTES;
    } catch {
      return false;
    }
  };
  let batch: TransactionInstruction[] = [];
  for (const instruction of instructions) {
    if (batch.length > 0 && !(await fits([...batch, instruction]))) {
      await runtime.sendAndConfirm(new Transaction().add(...batch));
      batch = [];
    }
    batch.push(instruction);
  }
  if (batch.length > 0) await runtime.sendAndConfirm(new Transaction().add(...batch));
}

/** Writes an initialised SPL mint (the LINK stand-in the FeeQuoter and Router validate) with a cheatcode. */
export async function createStandInMint(runtime: SvmRuntime, decimals = 6): Promise<PublicKey> {
  const mint = Keypair.generate().publicKey;
  const data = Buffer.alloc(82);
  data.writeUInt32LE(1, 0); // mint authority: Some
  runtime.payer.publicKey.toBuffer().copy(data, 4);
  data[44] = decimals;
  data[45] = 1; // is_initialized
  await runtime.setAccount(mint, {
    lamports: await runtime.connection.getMinimumBalanceForRentExemption(82),
    owner: TOKEN_PROGRAM_ID,
    data,
  });
  return mint;
}

/** Initialises RMN Remote (uncursed), FeeQuoter, Router, OffRamp, CommitteeVerifier and the EVM source chain. */
export async function initializeTrustLayer(runtime: SvmRuntime, programs: CcipPrograms): Promise<void> {
  const authority = runtime.payer.publicKey;
  const ids = Object.fromEntries(Object.entries(CCIP_PROGRAMS).map(([name, id]) => [name, new PublicKey(id)])) as Record<
    keyof typeof CCIP_PROGRAMS,
    PublicKey
  >;
  const config = (program: PublicKey) => pda([Buffer.from(SEEDS.config)], program);
  const evmSelector = new BN(EVM_CHAIN_SELECTOR.toString());
  const svmSelector = new BN(SVM_CHAIN_SELECTOR.toString());
  const linkMint = await createStandInMint(runtime);
  const remoteChain = pda([Buffer.from(SEEDS.remoteChain), selectorSeed(EVM_CHAIN_SELECTOR)], ids.committee_verifier);
  const committee = sortedCommittee(COMMITTEE_SIZE);

  const instructions = [
    await programs.offRamp.methods
      .initialize()
      .accounts({
        referenceAddresses: pda([Buffer.from(SEEDS.referenceAddresses)], ids.ccip_offramp),
        router: ids.ccip_router,
        feeQuoter: ids.fee_quoter,
        rmnRemote: ids.rmn_remote,
        offrampLookupTable: PublicKey.default,
        authority,
        systemProgram: SystemProgram.programId,
        program: ids.ccip_offramp,
        programData: programDataAddress(ids.ccip_offramp),
      })
      .instruction(),
    await programs.offRamp.methods
      .initializeConfig(svmSelector)
      .accounts({
        config: config(ids.ccip_offramp),
        authority,
        systemProgram: SystemProgram.programId,
        program: ids.ccip_offramp,
        programData: programDataAddress(ids.ccip_offramp),
      })
      .instruction(),
    // RMN Remote is initialised and left uncursed.
    await programs.rmnRemote.methods
      .initialize()
      .accounts({
        config: config(ids.rmn_remote),
        curses: pda([Buffer.from(SEEDS.curses)], ids.rmn_remote),
        authority,
        systemProgram: SystemProgram.programId,
        program: ids.rmn_remote,
        programData: programDataAddress(ids.rmn_remote),
      })
      .instruction(),
    await programs.feeQuoter.methods
      .initialize(new BN("1000000000000000000"), ids.ccip_router)
      .accounts({
        config: config(ids.fee_quoter),
        linkTokenMint: linkMint,
        authority,
        systemProgram: SystemProgram.programId,
        program: ids.fee_quoter,
        programData: programDataAddress(ids.fee_quoter),
      })
      .instruction(),
    await programs.router.methods
      .initialize(svmSelector, authority, ids.fee_quoter, linkMint, ids.rmn_remote)
      .accounts({
        config: config(ids.ccip_router),
        authority,
        systemProgram: SystemProgram.programId,
        program: ids.ccip_router,
        programData: programDataAddress(ids.ccip_router),
      })
      .instruction(),
    // Creates the router-owned `allowed_offramp` PDA that receivers check in `ccip_receive`.
    await programs.router.methods
      .addOfframp(evmSelector, ids.ccip_offramp)
      .accounts({ config: config(ids.ccip_router), authority, systemProgram: SystemProgram.programId })
      .instruction(),
    await programs.committeeVerifier.methods
      .initialize()
      .accounts({
        config: config(ids.committee_verifier),
        storageLocations: pda([Buffer.from(SEEDS.storageLocations)], ids.committee_verifier),
        authority,
        systemProgram: SystemProgram.programId,
        program: ids.committee_verifier,
        programData: programDataAddress(ids.committee_verifier),
      })
      .instruction(),
    await programs.committeeVerifier.methods
      .initChainConfig({
        remoteChainSelector: evmSelector,
        chainConfig: {
          // The Router's per-verifier signer: the PDA `ccip_send_v2` signs the verifier CPI with.
          routerSigner: pda([Buffer.from(SEEDS.ccvSigner), ids.committee_verifier.toBuffer()], ids.ccip_router),
          fee: 0,
          gasForVerification: 500_000,
          payloadSizeBytes: 390,
        },
      })
      .accounts({
        config: config(ids.committee_verifier),
        authority,
        remoteChainConfig: remoteChain,
        systemProgram: SystemProgram.programId,
      })
      .instruction(),
    await programs.committeeVerifier.methods
      .setSignerConfig({
        sourceChainSelector: evmSelector,
        threshold: COMMITTEE_THRESHOLD,
        signers: committee.map((key) => Array.from(Buffer.from(addressOf(key).slice(2), "hex"))),
      })
      .accounts({
        config: config(ids.committee_verifier),
        authority,
        remoteChainConfig: remoteChain,
        systemProgram: SystemProgram.programId,
      })
      .instruction(),
    await programs.offRamp.methods
      .addSourceChain({
        newChainSelector: evmSelector,
        sourceChainConfig: {
          isEnabled: true,
          onRamps: [{ bytes: Array.from(Buffer.alloc(64, 1)), len: 20 }],
          defaultCcvs: [ids.committee_verifier],
          laneMandatedCcvs: [],
          legacyAddressLength: 20,
        },
      })
      .accounts({
        sourceChain: pda([Buffer.from(SEEDS.sourceChain), selectorSeed(EVM_CHAIN_SELECTOR)], ids.ccip_offramp),
        config: config(ids.ccip_offramp),
        authority,
        systemProgram: SystemProgram.programId,
      })
      .instruction(),
  ];

  await sendPacked(runtime, instructions);
}
