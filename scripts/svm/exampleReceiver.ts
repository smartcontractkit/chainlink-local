// The stand-in receiver program shipped in the pinned CCIP Solana bundle, for examples and tests.

import { PublicKey } from "@solana/web3.js";
import path from "node:path";
import { readIdl, resolveArtifacts } from "./artifacts.ts";
import { CCIP_PROGRAMS } from "./programs.ts";

export interface ExampleReceiver {
  /** Program id the receiver is built for: pass it to `deployProgram` unchanged. */
  programId: PublicKey;
  /** Path of the compiled `test_ccip_receiver.so`, for `svm.deployProgram`. */
  programPath: string;
  /** Anchor IDL, for `new anchor.Program(idl as never, provider)`. */
  idl: { address: string } & Record<string, unknown>;
}

/** Resolves the pinned artifact bundle (downloading it on first use) and describes `test_ccip_receiver`. */
export async function exampleReceiver(): Promise<ExampleReceiver> {
  const bundleDir = await resolveArtifacts();
  return {
    programId: new PublicKey(CCIP_PROGRAMS.test_ccip_receiver),
    programPath: path.join(bundleDir, "target", "deploy", "test_ccip_receiver.so"),
    idl: readIdl(bundleDir, "test_ccip_receiver"),
  };
}
