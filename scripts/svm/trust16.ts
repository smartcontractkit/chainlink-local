// Local trust layer of a CCIP 1.6 lane: initialises the deployed 1.6 programs and configures OCR3 with local
// keys, so that a report signed by the local committee passes the real OffRamp `commit` and the transmitter
// passes `execute`.
//
// 1.6 has no CommitteeVerifier: the OffRamp itself holds the OCR3 config (signers and transmitters per plugin)
// and checks the commit signatures. There is no executor and the FeeQuoter is deployed but not initialised:
// a commit without price updates never touches it.

import anchor from "@anchor-lang/core";
import { PublicKey, SystemProgram } from "@solana/web3.js";
import { keccak256 } from "ethers";
import { readIdl } from "./artifacts.ts";
import { EVM_CHAIN_SELECTOR, SEEDS, SVM_CHAIN_SELECTOR, pda, programDataAddress, selectorSeed } from "./constants.ts";
import { convertLegacyIdl } from "./legacyIdl.ts";
import { CCIP_PROGRAMS_1_6 } from "./programs.ts";
import type { SvmRuntime } from "./runtime.ts";
import { addressOf, committeeKey } from "./signatures.ts";
import { sendPacked, type AnchorProgram } from "./trust.ts";

const { AnchorProvider, BN, Program, Wallet } = anchor;

/** The committee is 4 local keys with F = 1: commit needs more than 3F signers and exactly F + 1 signatures. */
export const COMMITTEE_SIZE_1_6 = 4;
export const F_1_6 = 1;
/** Placeholder onRamp registered at startup, replaced by the first explicit one (as in the 2.0 lane). */
export const PLACEHOLDER_ON_RAMP_1_6 = Buffer.alloc(20, 1);

const configDigest = (plugin: "commit" | "execution"): Buffer =>
  Buffer.from(keccak256(Buffer.from(`chainlink-local-svm-1.6:${plugin}`)).slice(2), "hex");

export const COMMIT_CONFIG_DIGEST = configDigest("commit");
export const EXECUTION_CONFIG_DIGEST = configDigest("execution");

/** Local committee keys of the 1.6 lane. Indexes 0..3 are keys the 2.0 committee also contains. */
export const committee16 = (): Uint8Array[] => Array.from({ length: COMMITTEE_SIZE_1_6 }, (_, i) => committeeKey(i));

/** Anchor programs of the 1.6 deployment, built from the bundle IDLs (converted from the Anchor 0.29 format). */
export function loadPrograms16(runtime: SvmRuntime, bundleDir: string) {
  const provider = new AnchorProvider(runtime.connection, new Wallet(runtime.payer), { commitment: "confirmed" });
  const program = (name: keyof typeof CCIP_PROGRAMS_1_6): AnchorProgram =>
    new Program(convertLegacyIdl(readIdl(bundleDir, name), CCIP_PROGRAMS_1_6[name]) as never, provider);
  return {
    offRamp: program("ccip_offramp"),
    router: program("ccip_router"),
    rmnRemote: program("rmn_remote"),
  };
}

export type CcipPrograms16 = ReturnType<typeof loadPrograms16>;

/** Initialises RMN Remote (uncursed), Router, OffRamp, the EVM source chain and both OCR3 plugins. */
export async function initializeTrustLayer16(runtime: SvmRuntime, programs: CcipPrograms16): Promise<void> {
  const authority = runtime.payer.publicKey;
  const ids = Object.fromEntries(Object.entries(CCIP_PROGRAMS_1_6).map(([name, id]) => [name, new PublicKey(id)])) as Record<
    keyof typeof CCIP_PROGRAMS_1_6,
    PublicKey
  >;
  const config = (program: PublicKey) => pda([Buffer.from(SEEDS.config)], program);
  const evmSelector = new BN(EVM_CHAIN_SELECTOR.toString());
  const svmSelector = new BN(SVM_CHAIN_SELECTOR.toString());
  const offRampConfig = config(ids.ccip_offramp);
  const ocrAccounts = { config: offRampConfig, state: pda([Buffer.from("state")], ids.ccip_offramp), authority };
  const signers = committee16().map((key) => Array.from(Buffer.from(addressOf(key).slice(2), "hex")));
  const onRampBytes = Buffer.concat([PLACEHOLDER_ON_RAMP_1_6, Buffer.alloc(44)]);

  const instructions = [
    await programs.offRamp.methods
      .initialize()
      .accounts({
        referenceAddresses: pda([Buffer.from(SEEDS.referenceAddresses)], ids.ccip_offramp),
        router: ids.ccip_router,
        feeQuoter: ids.fee_quoter,
        rmnRemote: ids.rmn_remote,
        offrampLookupTable: PublicKey.default,
        state: ocrAccounts.state,
        authority,
        systemProgram: SystemProgram.programId,
        program: ids.ccip_offramp,
        programData: programDataAddress(ids.ccip_offramp),
      })
      .instruction(),
    await programs.offRamp.methods
      .initializeConfig(svmSelector, new BN(0))
      .accounts({
        config: offRampConfig,
        authority,
        systemProgram: SystemProgram.programId,
        program: ids.ccip_offramp,
        programData: programDataAddress(ids.ccip_offramp),
      })
      .instruction(),
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
    // The Router only has to exist and list the OffRamp: its `allowed_offramp` PDA is what receivers check.
    // The fee aggregator and LINK mint are never read by an inbound execution.
    await programs.router.methods
      .initialize(svmSelector, authority, ids.fee_quoter, authority, ids.rmn_remote)
      .accounts({
        config: config(ids.ccip_router),
        authority,
        systemProgram: SystemProgram.programId,
        program: ids.ccip_router,
        programData: programDataAddress(ids.ccip_router),
      })
      .instruction(),
    await programs.router.methods
      .addOfframp(evmSelector, ids.ccip_offramp)
      .accounts({
        allowedOfframp: allowedOfframp(ids.ccip_router, ids.ccip_offramp),
        config: config(ids.ccip_router),
        authority,
        systemProgram: SystemProgram.programId,
      })
      .instruction(),
    await programs.offRamp.methods
      .addSourceChain(evmSelector, {
        isEnabled: true,
        isRmnVerificationDisabled: true,
        laneCodeVersion: { default: {} },
        onRamp: { bytes: Array.from(onRampBytes), len: PLACEHOLDER_ON_RAMP_1_6.length },
      })
      .accounts({
        sourceChain: pda([Buffer.from(SEEDS.sourceChain), selectorSeed(EVM_CHAIN_SELECTOR)], ids.ccip_offramp),
        config: offRampConfig,
        authority,
        systemProgram: SystemProgram.programId,
      })
      .instruction(),
    // Commit: 4 signers, F = 1 (so 2 signatures per report), the payer as the only transmitter.
    await programs.offRamp.methods
      .setOcrConfig({ commit: {} }, { configDigest: [...COMMIT_CONFIG_DIGEST], f: F_1_6, n: 0, isSignatureVerificationEnabled: 0 }, signers, [authority])
      .accounts(ocrAccounts)
      .instruction(),
    // Execution: no signatures, so no signers; the OffRamp only checks the transmitter.
    await programs.offRamp.methods
      .setOcrConfig({ execution: {} }, { configDigest: [...EXECUTION_CONFIG_DIGEST], f: F_1_6, n: 0, isSignatureVerificationEnabled: 0 }, [], [authority])
      .accounts(ocrAccounts)
      .instruction(),
  ];

  await sendPacked(runtime, instructions);
}

/** The router-owned PDA that receivers check in `ccip_receive`, one per (source chain, OffRamp). */
export function allowedOfframp(router: PublicKey, offRamp: PublicKey, sourceChain = EVM_CHAIN_SELECTOR): PublicKey {
  return pda([Buffer.from("allowed_offramp"), selectorSeed(sourceChain), offRamp.toBuffer()], router);
}
