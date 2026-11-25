// Entry point of `@chainlink/local/svm`.
//
// The Solana libraries are optional peer dependencies. A static `import` of a missing package
// fails with a generic ERR_MODULE_NOT_FOUND before any code here runs, so the check below uses
// `import.meta.resolve` (no module is loaded) and later modules must only be imported after it.

/** Solana peer packages, with the version range the package is tested against. */
export const SVM_PEER_PACKAGES = {
  "@solana/surfpool": "1.7.0",
  "@solana/web3.js": "^1.98",
  "@anchor-lang/core": "^1.2",
  // keccak256 and secp256k1 signing of the committee results.
  ethers: "^6.17.0",
} as const;

function assertPeersInstalled(): void {
  const missing = Object.entries(SVM_PEER_PACKAGES).filter(([name]) => {
    try {
      import.meta.resolve(name);
      return false;
    } catch {
      return true;
    }
  });
  if (missing.length === 0) return;

  const specs = missing.map(([name, range]) => `${name}@${range}`);
  throw new Error(
    `@chainlink/local/svm requires these peer packages, which are not installed: ` +
      `${missing.map(([name]) => name).join(", ")}.\n` +
      `Install them with:\n  npm i -D ${specs.join(" ")}`,
  );
}

assertPeersInstalled();

// Loaded only now: a static `export ... from` would load @solana/web3.js before the check above.
const implementation = await import("./local.ts");
const extraArgs = await import("./extraArgs.ts");
const route = await import("./route.ts");
const receiver = await import("./exampleReceiver.ts");
const send20 = await import("./send20.ts");

export const startSvmLocal = implementation.startSvmLocal;
export const svmExtraArgs = extraArgs.svmExtraArgs;
export const routeToSvm = route.routeToSvm;
export const exampleReceiver = receiver.exampleReceiver;
export const PLACEHOLDER_OFFRAMP_2_0 = send20.PLACEHOLDER_OFFRAMP_2_0;
export const NO_EXECUTION_EXECUTOR = send20.NO_EXECUTION_EXECUTOR;
export type { SvmExtraArgsOptions } from "./extraArgs.ts";
export type { ExampleReceiver } from "./exampleReceiver.ts";
export type { EvmReceiptLike, RouteResult } from "./route.ts";
export type { DeliverOptions, DeliverResult, StartOptions, SvmLocal } from "./local.ts";
export type { SentMessagesOptions, SvmSendOptions, SvmSentMessage } from "./send.ts";
export type { CcipVersion } from "./artifacts.ts";
export type { BurnMintToken, DeliverToken, LinkTokenOptions } from "./tokens.ts";
