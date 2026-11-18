// The CCIP 2.0 programs deployed on the local Surfnet, at their production program ids.
// Ids are the ones in the prototype's constants.ts, re-checked against the `address` field of each
// IDL in the pinned bundle (contracts/v2.1.0).

import { PublicKey } from "@solana/web3.js";
import { readIdl, readProgram } from "./artifacts.ts";
import type { SvmRuntime } from "./runtime.ts";

/** Program name = file name of `<name>.so` and `<name>.json` in the bundle. */
export const CCIP_PROGRAMS = {
  ccip_offramp: "off43sBHBsmWTU6VbfwKYCNwyJ4rSDhunYvz3QL7bF9",
  ccip_router: "Ccip842gzYHhvdDkSyi2YVCoAWPbYJoApMFzSxQroE9C",
  fee_quoter: "FeeQPGkKDeRV1MgoYfMH6L8o3KeuYjwUZrgn4LRKfjHi",
  rmn_remote: "RmnXLft1mSEwDgMKu2okYuHkiazxntFFcZFrrcXxYg7",
  committee_verifier: "CV2s8jsYhx9th8pyZ4pN7apLELAB42e5j4XqWhqTdWCm",
  executor: "Exex3nkLcxMFASH75gudot5ZSQXUMRc8BrYaYHTDJrt4",
  test_ccip_receiver: "GsgXbSfG226vCVMfamUhwFgY4kF9HkNiu3wk8Ho8cky5",
} as const;

export type CcipProgramName = keyof typeof CCIP_PROGRAMS;

/**
 * Writes every program from the bundle at its id and makes the runtime's payer the upgrade
 * authority. Throws if a bundle IDL disagrees with the pinned id.
 */
export async function deployCcipPrograms(runtime: SvmRuntime, bundleDir: string): Promise<void> {
  for (const [name, id] of Object.entries(CCIP_PROGRAMS)) {
    const idlAddress = readIdl(bundleDir, name).address;
    if (idlAddress !== id) {
      throw new Error(`${name}: bundle IDL address ${idlAddress} differs from pinned id ${id}`);
    }
    const programId = new PublicKey(id);
    await runtime.writeProgram(programId, readProgram(bundleDir, name));
    await runtime.setProgramAuthority(programId, runtime.payer.publicKey);
  }
}
