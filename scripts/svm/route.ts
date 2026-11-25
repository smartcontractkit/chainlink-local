// `routeToSvm()`: delivers the Solana-bound messages of an EVM transaction through the real OffRamp of the local Solana side (CCIP 2.0 or 1.6).

import { Interface, ZeroAddress, getAddress, getBytes } from "ethers";
import { PublicKey } from "@solana/web3.js";
import { EVM_CHAIN_SELECTOR } from "./constants.ts";
import type { CcipVersion } from "./artifacts.ts";
import type { DeliverResult, SvmLocal } from "./local.ts";
import type { DeliverToken } from "./tokens.ts";

const SVM_MESSAGE_SENT = new Interface([
  "event SvmMessageSent(bytes32 indexed messageId, uint64 indexed destinationChainSelector, address indexed sender, " +
    "bytes32 receiver, bytes data, (uint32 computeUnits, uint64 accountIsWritableBitmap, bool allowOutOfOrderExecution, " +
    "bytes32 tokenReceiver, bytes32[] accounts) extraArgs, address feeToken, uint256 feeTokenAmount, uint256 nonce, " +
    "address token, uint256 tokenAmount)",
]);
const SVM_MESSAGE_SENT_TOPIC = SVM_MESSAGE_SENT.getEvent("SvmMessageSent")!.topicHash;
const LANE_VERSION = new Interface(["function getSvmLaneVersion() view returns (uint8)"]);
/** `CCIPLocalRouter.SvmLaneVersion` by enum value. */
const LANE_VERSIONS: readonly CcipVersion[] = ["2.0", "1.6"];

/** What `routeToSvm` reads from an ethers transaction receipt. */
export interface EvmReceiptLike {
  logs: readonly { address: string; topics: readonly string[]; data: string }[];
  /** An ethers v6 receipt has one. When present, `routeToSvm` checks the router's lane version against `svm`. */
  provider?: { call(tx: { to: string; data: string }): Promise<string> };
}

export interface RouteResult extends DeliverResult {
  /** The id `ccipSend` returned on the EVM side. `messageId` is the Solana-side id, computed differently. */
  evmMessageId: string;
}

/**
 * Delivers every `SvmMessageSent` log of `receipt`, in log order, to its Solana program through the real
 * OffRamp, and returns one result per message. The emitting router becomes the OffRamp's onRamp for the
 * EVM source chain, so the message comes from the address a live lane would use.
 */
export async function routeToSvm(svm: SvmLocal, receipt: EvmReceiptLike): Promise<RouteResult[]> {
  const logs = receipt.logs.filter((log) => log.topics[0] === SVM_MESSAGE_SENT_TOPIC);
  if (logs.length === 0) {
    throw new Error(
      "routeToSvm: the receipt has no SvmMessageSent log. Send to the Solana chain selector 16423721717087811551 " +
        "through the CCIPLocalSimulator router, and pass the receipt of that transaction.",
    );
  }
  if (receipt.provider) {
    for (const router of new Set(logs.map((log) => getAddress(log.address)))) {
      await checkLaneVersion(receipt.provider, router, svm.ccipVersion);
    }
  }
  const events = logs.map((log) => SVM_MESSAGE_SENT.parseLog({ topics: [...log.topics], data: log.data })!.args);
  // Check every token before delivering anything, so a receipt with an unlinked token delivers none of its messages.
  for (const event of events) {
    if (event.token !== ZeroAddress && !svm.linkedMint(event.token as string)) {
      throw new Error(
        `routeToSvm: the message carries the EVM token ${event.token}, which is not linked to a Solana token. ` +
          `Call svm.createBurnMintToken() and svm.linkToken(token, { evmToken: "${event.token}" }) before routing.`,
      );
    }
  }
  const results: RouteResult[] = [];
  for (const [index, log] of logs.entries()) {
    const event = events[index];
    const common = {
      sender: getBytes(event.sender),
      onRampAddress: getBytes(getAddress(log.address)),
      sourceChainSelector: EVM_CHAIN_SELECTOR,
      messageNumber: event.nonce as bigint,
      computeUnits: Number(event.extraArgs.computeUnits),
    };
    const receiverBytes = getBytes(event.receiver);
    const message = {
      receiverProgram: new PublicKey(receiverBytes),
      receiverAccounts: (event.extraArgs.accounts as string[]).map((account) => new PublicKey(getBytes(account))),
      receiverWritableBitmap: event.extraArgs.accountIsWritableBitmap as bigint,
      data: getBytes(event.data),
    };
    let token: DeliverToken | undefined;
    if (event.token !== ZeroAddress) {
      token = {
        evmToken: event.token as string,
        amount: event.tokenAmount as bigint,
        receiver: new PublicKey(getBytes(event.extraArgs.tokenReceiver)),
      };
    }
    // A token with a zero receiver is token-only: no program is invoked, so the deliver API takes no message fields.
    const tokenOnly = token !== undefined && receiverBytes.every((byte) => byte === 0);
    // `computeUnits` is the receiver's budget (0 for token-only); deliver() adds the token overhead on top.
    const result = await svm.deliver(
      tokenOnly ? { ...common, token } : { ...common, ...message, ...(token && { token }) },
    );
    results.push({ ...result, evmMessageId: event.messageId as string });
  }
  return results;
}

/** Throws when the router's `getSvmLaneVersion()` differs from the version `svm` runs: the send followed other rules than the programs. */
async function checkLaneVersion(provider: NonNullable<EvmReceiptLike["provider"]>, router: string, svmVersion: CcipVersion) {
  const raw = await provider.call({ to: router, data: LANE_VERSION.encodeFunctionData("getSvmLaneVersion") });
  const routerVersion = LANE_VERSIONS[Number(LANE_VERSION.decodeFunctionResult("getSvmLaneVersion", raw)[0])];
  if (routerVersion !== svmVersion) {
    throw new Error(
      `routeToSvm: the router ${router} sent this message with CCIP ${routerVersion} rules, but the local Solana side runs ` +
        `CCIP ${svmVersion}. Call router.setSvmLaneVersion(${svmVersion === "1.6" ? 1 : 0}) ` +
        `(${svmVersion === "1.6" ? "V1_6" : "V2_0"}) before sending, or startSvmLocal({ ccipVersion: "${routerVersion}" }).`,
    );
  }
}
