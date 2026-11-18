// `routeToSvm()`: delivers the Solana-bound messages of an EVM transaction through the real CCIP 2.0 OffRamp.

import { Interface, getAddress, getBytes } from "ethers";
import { PublicKey } from "@solana/web3.js";
import { EVM_CHAIN_SELECTOR } from "./constants.ts";
import type { DeliverResult, SvmLocal } from "./local.ts";

const SVM_MESSAGE_SENT = new Interface([
  "event SvmMessageSent(bytes32 indexed messageId, uint64 indexed destinationChainSelector, address indexed sender, " +
    "bytes32 receiver, bytes data, (uint32 computeUnits, uint64 accountIsWritableBitmap, bool allowOutOfOrderExecution, " +
    "bytes32 tokenReceiver, bytes32[] accounts) extraArgs, address feeToken, uint256 feeTokenAmount, uint256 nonce)",
]);
const SVM_MESSAGE_SENT_TOPIC = SVM_MESSAGE_SENT.getEvent("SvmMessageSent")!.topicHash;

/** What `routeToSvm` reads from an ethers transaction receipt. */
export interface EvmReceiptLike {
  logs: readonly { address: string; topics: readonly string[]; data: string }[];
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
  const results: RouteResult[] = [];
  for (const log of logs) {
    const event = SVM_MESSAGE_SENT.parseLog({ topics: [...log.topics], data: log.data })!.args;
    const result = await svm.deliver({
      receiverProgram: new PublicKey(getBytes(event.receiver)),
      receiverAccounts: (event.extraArgs.accounts as string[]).map((account) => new PublicKey(getBytes(account))),
      receiverWritableBitmap: event.extraArgs.accountIsWritableBitmap as bigint,
      data: getBytes(event.data),
      sender: getBytes(event.sender),
      onRampAddress: getBytes(getAddress(log.address)),
      sourceChainSelector: EVM_CHAIN_SELECTOR,
      messageNumber: event.nonce as bigint,
      computeUnits: Number(event.extraArgs.computeUnits),
    });
    results.push({ ...result, evmMessageId: event.messageId as string });
  }
  return results;
}
