// The CCIP programs deployed on the local Surfnet, at their production program ids.
// 2.0: ids are the ones in the prototype's constants.ts, re-checked against the `address` field of each
// IDL in the pinned bundle (contracts/v2.1.0).
// 1.6: ids from the `declare_id!` of each program in chainlink-ccip solana-v1.6.4. Its IDLs (Anchor 0.29
// format) carry no address, so they cannot be re-checked here; a wrong id fails at the first execution
// with DeclaredProgramIdMismatch.

import { PublicKey } from "@solana/web3.js";
import { readIdl, readProgram, type CcipVersion } from "./artifacts.ts";
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

/** The CCIP 1.6 programs. There is no CommitteeVerifier: 1.6 verifies the commit with OCR3 signatures in the OffRamp. */
export const CCIP_PROGRAMS_1_6 = {
  ccip_offramp: "offqSMQWgQud6WJz694LRzkeN5kMYpCHTpXQr3Rkcjm",
  ccip_router: "Ccip842gzYHhvdDkSyi2YVCoAWPbYJoApMFzSxQroE9C",
  fee_quoter: "FeeQPGkKDeRV1MgoYfMH6L8o3KeuYjwUZrgn4LRKfjHi",
  rmn_remote: "RmnXLft1mSEwDgMKu2okYuHkiazxntFFcZFrrcXxYg7",
  test_ccip_receiver: "EvhgrPhTDt4LcSPS2kfJgH6T6XWZ6wT3X9ncDGLT1vui",
} as const;

export const programIds = (version: CcipVersion): Record<string, string> =>
  version === "1.6" ? CCIP_PROGRAMS_1_6 : CCIP_PROGRAMS;

/**
 * Writes every program from the bundle at its id and makes the runtime's payer the upgrade
 * authority. Throws if a bundle IDL disagrees with the pinned id.
 */
export async function deployCcipPrograms(
  runtime: SvmRuntime,
  bundleDir: string,
  ccipVersion: CcipVersion = "2.0",
): Promise<void> {
  for (const [name, id] of Object.entries(programIds(ccipVersion))) {
    if (ccipVersion === "2.0") {
      const idlAddress = readIdl(bundleDir, name).address;
      if (idlAddress !== id) {
        throw new Error(`${name}: bundle IDL address ${idlAddress} differs from pinned id ${id}`);
      }
    }
    const programId = new PublicKey(id);
    await runtime.writeProgram(programId, readProgram(bundleDir, name));
    await runtime.setProgramAuthority(programId, runtime.payer.publicKey);
  }
}
