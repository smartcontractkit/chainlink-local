// The stand-in receiver program shipped in the pinned CCIP Solana bundle of each version, for examples and tests.

import { PublicKey } from "@solana/web3.js";
import path from "node:path";
import { readIdl, resolveArtifacts, type CcipVersion } from "./artifacts.ts";
import { convertLegacyIdl } from "./legacyIdl.ts";
import { programIds } from "./programs.ts";

/** Types the 1.6 receiver IDL uses but omits (`example-ccip-receiver/src/lib.rs`, chainlink-ccip solana-v1.6.4). */
const RECEIVER_1_6_MISSING_TYPES = [
  {
    name: "BaseState",
    type: {
      kind: "struct",
      fields: [
        { name: "owner", type: "publicKey" },
        { name: "proposedOwner", type: "publicKey" },
        { name: "router", type: "publicKey" },
      ],
    },
  },
  {
    name: "SVMTokenAmount",
    type: {
      kind: "struct",
      fields: [
        { name: "token", type: "publicKey" },
        { name: "amount", type: "u64" },
      ],
    },
  },
  {
    name: "Any2SVMMessage",
    type: {
      kind: "struct",
      fields: [
        { name: "messageId", type: { array: ["u8", 32] } },
        { name: "sourceChainSelector", type: "u64" },
        { name: "sender", type: "bytes" },
        { name: "data", type: "bytes" },
        { name: "tokenAmounts", type: { vec: { defined: "SVMTokenAmount" } } },
      ],
    },
  },
];

export interface ExampleReceiver {
  /** Program id the receiver is built for: pass it to `deployProgram` unchanged. */
  programId: PublicKey;
  /** Path of the compiled `test_ccip_receiver.so`, for `svm.deployProgram`. */
  programPath: string;
  /** Anchor IDL, for `new anchor.Program(idl as never, provider)`. */
  idl: { address: string } & Record<string, unknown>;
}

/**
 * Resolves the pinned artifact bundle of `ccipVersion` (default "2.0", downloading it on first use) and describes
 * its `test_ccip_receiver`. The 1.6 bundle ships Anchor 0.29 IDLs, which `anchor.Program` 1.x cannot read; the
 * returned 1.6 `idl` is converted, so both versions are used the same way.
 */
export async function exampleReceiver(options: { ccipVersion?: CcipVersion } = {}): Promise<ExampleReceiver> {
  const ccipVersion = options.ccipVersion ?? "2.0";
  const bundleDir = await resolveArtifacts({ ccipVersion });
  const id = programIds(ccipVersion).test_ccip_receiver;
  const idl = readIdl(bundleDir, "test_ccip_receiver");
  return {
    programId: new PublicKey(id),
    programPath: path.join(bundleDir, "target", "deploy", "test_ccip_receiver.so"),
    idl: ccipVersion === "1.6" ? convertLegacyIdl(idl, id, RECEIVER_1_6_MISSING_TYPES) : idl,
  };
}
