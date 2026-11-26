// `routeToSvm()`: delivers the Solana-bound messages of an EVM transaction through the real OffRamp of the local Solana side (CCIP 2.0 or 1.6).
// `routeFromSvm()`: executes messages sent from Solana on the EVM side, through `CCIPLocalSvmLane`.
// `routeAll()`: alternates both until nothing is pending.

import { Interface, ZeroAddress, getAddress, getBytes, hexlify, type Contract, type ContractTransactionReceipt } from "ethers";
import { PublicKey } from "@solana/web3.js";
import { EVM_CHAIN_SELECTOR, SVM_CHAIN_SELECTOR } from "./constants.ts";
import type { CcipVersion } from "./artifacts.ts";
import type { DeliverResult, SvmLocal } from "./local.ts";
import type { SvmSentMessage } from "./send.ts";
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
 * EVM message ids each local Solana chain has received, shared by `routeToSvm` and `routeAll` so `routeAll` never
 * delivers a message a second time. A repeat would really execute twice on 1.6, where every `deliver()` commits the
 * next sequence number.
 */
const deliveredToSolanaBySvm = new WeakMap<SvmLocal, Set<string>>();
function deliveredToSolana(svm: SvmLocal): Set<string> {
  let delivered = deliveredToSolanaBySvm.get(svm);
  if (!delivered) deliveredToSolanaBySvm.set(svm, (delivered = new Set()));
  return delivered;
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
    deliveredToSolana(svm).add((event.messageId as string).toLowerCase());
    results.push({ ...result, evmMessageId: event.messageId as string });
  }
  return results;
}

/** Throws when the router's `getSvmLaneVersion()` differs from the version `svm` runs: the send followed other rules than the programs. */
async function checkLaneVersion(
  provider: NonNullable<EvmReceiptLike["provider"]>,
  router: string,
  svmVersion: CcipVersion,
  caller = "routeToSvm",
  verb = "sent this message with",
) {
  const raw = await provider.call({ to: router, data: LANE_VERSION.encodeFunctionData("getSvmLaneVersion") });
  const routerVersion = LANE_VERSIONS[Number(LANE_VERSION.decodeFunctionResult("getSvmLaneVersion", raw)[0])];
  if (routerVersion !== svmVersion) {
    throw new Error(
      `${caller}: the router ${router} ${verb} CCIP ${routerVersion} rules, but the local Solana side runs ` +
        `CCIP ${svmVersion}. Call router.setSvmLaneVersion(${svmVersion === "1.6" ? 1 : 0}) ` +
        `(${svmVersion === "1.6" ? "V1_6" : "V2_0"}) before routing, or startSvmLocal({ ccipVersion: "${routerVersion}" }).`,
    );
  }
}

// ================================================================
//                    Solana -> EVM: routeFromSvm
// ================================================================

const LANE_EXECUTE = new Interface([
  "function execute((bytes32 messageId, uint64 sourceChainSelector, uint64 sequenceNumber, bytes sender, address receiver, bytes data, uint256 gasLimit, bytes4 finality, bytes sourcePoolAddress, address destToken, uint256 amount, bytes extraData) message) returns (bool success, bytes retData)",
  "event SvmMessageExecuted(bytes32 indexed messageId, uint64 indexed sourceChainSelector, address indexed receiver, bool success, bytes retData)",
  "error ReceiverError(bytes err)",
  "error InsufficientEscrow(address token, uint256 held, uint256 needed)",
  "error InvalidRemoteChainDecimals(bytes sourcePoolData)",
  "error OverflowDetected(uint8 remoteDecimals, uint8 localDecimals, uint256 remoteAmount)",
  "error InvalidOptionalThreshold(uint8 wanted, uint256 got)",
  "error CanOnlySelfCall()",
  "error InvalidSourceChainSelector(uint64 sourceChainSelector)",
]);
const ROUTER_OF_LANE = new Interface(["function ROUTER() view returns (address)"]);
const CCIP_RECEIVE = new Interface([
  "function ccipReceive((bytes32 messageId, uint64 sourceChainSelector, bytes sender, bytes data, (address token, uint256 amount)[] destTokenAmounts) message)",
]);
const ERROR_STRING = new Interface(["error Error(string reason)", "error Panic(uint256 code)"]);
/** Gas on top of the message's `gasLimit` for the lane's own work: state, token release, the router call. */
const EXECUTE_GAS_OVERHEAD = 2_000_000n;

export interface RouteFromSvmResult {
  /** The Solana message id. */
  messageId: string;
  state: "Success" | "Failure";
  /** For a Failure: the decoded revert data, e.g. the receiver's revert reason. */
  error?: string;
  evmTransactionHash: string;
  receipt: ContractTransactionReceipt;
}

/** `lane.runner.provider`, or a clear error: `lane` must be connected to a signer, which sends the transactions. */
function laneProvider(lane: Contract, caller: string) {
  const provider = lane.runner?.provider;
  if (!provider) throw new Error(`${caller}: lane must be a CCIPLocalSvmLane contract connected to a signer`);
  return provider;
}

/** Reads `ROUTER()` of the lane and checks the router's lane version against `svm`. Returns the router address. */
async function checkLane(svm: SvmLocal, lane: Contract, caller: string): Promise<string> {
  const provider = laneProvider(lane, caller);
  const raw = await provider.call({ to: await lane.getAddress(), data: ROUTER_OF_LANE.encodeFunctionData("ROUTER") });
  const router = getAddress(ROUTER_OF_LANE.decodeFunctionResult("ROUTER", raw)[0] as string);
  await checkLaneVersion(provider, router, svm.ccipVersion, caller, "executes this message with");
  return router;
}

/** Revert data as text: `Error(string)`, `Panic`, the lane's own errors, else the raw hex (also when truncated). */
function decodeRevert(data: string): string {
  if (data === "0x" || data === "") return "reverted with no data";
  try {
    const known = ERROR_STRING.parseError(data) ?? LANE_EXECUTE.parseError(data);
    if (known?.name === "Error") return `reverted: ${known.args[0]}`;
    if (known?.name === "Panic") return `panic code ${known.args[0]}`;
    if (known && known.name !== "ReceiverError") return `${known.name}(${known.args.map(String).join(", ")})`;
  } catch {
    // Undecodable, usually cut at `Internal.MAX_RET_BYTES` (132 bytes), like the OffRamp does.
  }
  return `reverted with ${data}`;
}

/**
 * Why a failed execution failed. For a receiver failure the lane's `retData` is `ReceiverError(receiver's revert data)`
 * cut to `Internal.MAX_RET_BYTES` (132 bytes), which loses the reason. The attempt was rolled back, so the receiver's call
 * is run again as the router makes it (without tokens: their release was rolled back too) to read its revert data.
 */
async function failureReason(
  provider: NonNullable<ReturnType<typeof laneProvider>>,
  router: string,
  message: { messageId: string; sourceChainSelector: bigint; sender: string; data: string; receiver: string; gasLimit: bigint },
  laneRetData: string,
): Promise<string> {
  if (!laneRetData.startsWith(LANE_EXECUTE.getError("ReceiverError")!.selector)) return decodeRevert(laneRetData);
  const call = CCIP_RECEIVE.encodeFunctionData("ccipReceive", [
    { messageId: message.messageId, sourceChainSelector: message.sourceChainSelector, sender: message.sender, data: message.data, destTokenAmounts: [] },
  ]);
  try {
    await provider.call({ from: router, to: message.receiver, data: call, gasLimit: message.gasLimit });
  } catch (error) {
    const data = (error as { data?: string }).data;
    if (data) return `receiver ${decodeRevert(data)}`;
  }
  return "receiver reverted; the lane's revert data is cut at 132 bytes and the reason could not be recovered";
}

/**
 * Executes messages sent from Solana on the EVM side: `lane.execute(...)` for each, in order, like the OffRamp.
 *
 * - `lane`: an ethers v6 Contract for `CCIPLocalSvmLane`, connected to the signer that sends the transactions.
 * - `messages`: one `SvmSentMessage`, an array, or the signature of a Solana transaction (decoded with
 *   `svm.sentMessages({ signature })`).
 *
 * All messages are checked before any is executed. Misuse throws: another destination chain, a router whose lane
 * version differs from `svm`'s, no message. A message the lane already executed successfully reverts
 * (`SkippedAlreadyExecutedMessage`), and so does a retry of a failed message that fails again. A receiver or token
 * failure does not throw: it returns `state: "Failure"` and the message can be routed again.
 */
export async function routeFromSvm(
  svm: SvmLocal,
  lane: Contract,
  messages: SvmSentMessage | SvmSentMessage[] | string,
): Promise<RouteFromSvmResult[]> {
  const list = typeof messages === "string" ? await svm.sentMessages({ signature: messages }) : Array.isArray(messages) ? messages : [messages];
  if (list.length === 0) {
    throw new Error("routeFromSvm: no message to route; the transaction sent none through the Solana Router");
  }
  for (const message of list) {
    if (message.destChainSelector !== EVM_CHAIN_SELECTOR) {
      throw new Error(
        `routeFromSvm: message ${message.messageId} is for chain selector ${message.destChainSelector}, but the local EVM chain is ${EVM_CHAIN_SELECTOR}`,
      );
    }
    if (message.sourceChainSelector !== SVM_CHAIN_SELECTOR) {
      throw new Error(`routeFromSvm: message ${message.messageId} has source chain selector ${message.sourceChainSelector}, not Solana`);
    }
  }
  const router = await checkLane(svm, lane, "routeFromSvm");

  const laneAddress = await lane.getAddress();
  const results: RouteFromSvmResult[] = [];
  for (const message of list) {
    const { token } = message;
    const struct = {
      messageId: message.messageId,
      sourceChainSelector: message.sourceChainSelector,
      sequenceNumber: message.sequenceNumber,
      sender: hexlify(message.sender),
      receiver: message.receiver,
      data: hexlify(message.data),
      gasLimit: message.gasLimit,
      finality: message.finality,
      sourcePoolAddress: token ? hexlify(token.sourcePool) : "0x",
      destToken: token ? token.destToken : ZeroAddress,
      amount: token ? token.amount : 0n,
      extraData: token ? hexlify(token.extraData) : "0x",
    };
    // An explicit gas limit: estimating would stop at the least gas that does not revert, and the lane does not revert
    // when the receiver runs out of gas, so the estimate could leave the receiver too little.
    const transaction = await lane.getFunction("execute")(struct, { gasLimit: message.gasLimit + EXECUTE_GAS_OVERHEAD });
    const receipt = (await transaction.wait()) as ContractTransactionReceipt;
    const executed = receipt.logs.flatMap((log) => {
      const parsed = log.address === laneAddress ? LANE_EXECUTE.parseLog({ topics: [...log.topics], data: log.data }) : null;
      return parsed?.name === "SvmMessageExecuted" ? [parsed.args] : [];
    })[0];
    if (!executed) throw new Error(`routeFromSvm: transaction ${receipt.hash} emitted no SvmMessageExecuted event`);
    const success = executed.success as boolean;
    results.push({
      messageId: message.messageId,
      state: success ? "Success" : "Failure",
      ...(!success && { error: await failureReason(laneProvider(lane, "routeFromSvm"), router, struct, executed.retData as string) }),
      evmTransactionHash: receipt.hash,
      receipt,
    });
  }
  return results;
}

// ================================================================
//                       Both ways: routeAll
// ================================================================

export interface RouteAllOptions {
  /** `CCIPLocalSvmLane` connected to a signer. Its `ROUTER()` is the router whose `SvmMessageSent` logs are routed. */
  lane: Contract;
  /**
   * First EVM block to look for `SvmMessageSent` logs in. Required: there is no safe default, because the message
   * that starts the exchange has usually been sent already. Use `receipt.blockNumber` of the first send, or the block
   * before it. Messages already delivered by `routeToSvm` (or an earlier `routeAll`) to this `svm`, or already executed
   * by the lane, are skipped, so an earlier block is safe.
   */
  fromBlock: number | bigint;
  /**
   * Route only the Solana messages sent in Router transactions after this one (`svm.sentMessages({ afterSignature })`).
   * Default: every message since the Solana side started, so pass it when other messages were sent before.
   */
  afterSignature?: string;
  /** Deliveries after which `routeAll` stops. Default 20. */
  maxMessages?: number;
  /**
   * Awaited after every delivery to Solana, before the next scan: this is where a test replies from a Solana wallet
   * with `svm.send`. No Solana program can reply today: on 1.6 a receiver needing more than 14 accounts runs the
   * OffRamp out of heap (the 1.6 `ping_pong_demo` needs 20), and 2.0 ships none.
   */
  onSolanaDelivery?: (result: RouteResult) => void | Promise<void>;
}

export type RouteAllDelivery =
  | { direction: "evm-to-solana"; result: RouteResult }
  | { direction: "solana-to-evm"; message: SvmSentMessage; result: RouteFromSvmResult };

export interface RouteAllResult {
  /** Every delivery, in the order it happened. A Failure is a delivery; it is not retried. */
  deliveries: RouteAllDelivery[];
  /**
   * False when `routeAll` stopped at `maxMessages` with messages still pending (a never-ending exchange). It does not
   * throw then, so the deliveries made so far are not lost; check this flag.
   */
  complete: boolean;
}

/**
 * Routes both directions until nothing is pending: the router's `SvmMessageSent` logs from `fromBlock` go to Solana
 * (`routeToSvm`), the Solana Router's messages after `afterSignature` go to the EVM lane (`routeFromSvm`), and the
 * two are scanned again after each round, so a message sent while routing (a receiver that replies) is routed too.
 * A message is delivered once, even though the scans overlap. Misuse throws what `routeToSvm` and `routeFromSvm` throw.
 */
export async function routeAll(svm: SvmLocal, options: RouteAllOptions): Promise<RouteAllResult> {
  const { lane, fromBlock, onSolanaDelivery } = options;
  const maxMessages = options.maxMessages ?? 20;
  if (!Number.isInteger(maxMessages) || maxMessages < 1) throw new Error(`routeAll: maxMessages must be a positive integer, got ${maxMessages}`);
  const router = await checkLane(svm, lane, "routeAll");
  const provider = laneProvider(lane, "routeAll");

  const deliveries: RouteAllDelivery[] = [];
  const toSolana = deliveredToSolana(svm);
  const deliveredToEvm = new Set<string>();
  let cursor = options.afterSignature;

  for (;;) {
    const logs = (await provider.getLogs({ address: router, topics: [SVM_MESSAGE_SENT_TOPIC], fromBlock })).filter(
      (log) => !toSolana.has(log.topics[1].toLowerCase()),
    );
    const sent: SvmSentMessage[] = [];
    for (const message of await svm.sentMessages(cursor === undefined ? {} : { afterSignature: cursor })) {
      if (deliveredToEvm.has(message.messageId)) continue;
      // Executed by an earlier routeFromSvm or routeAll (any state but UNTOUCHED): the lane is the source of truth.
      if (Number(await lane.getExecutionState(message.messageId)) !== 0) {
        deliveredToEvm.add(message.messageId);
        continue;
      }
      sent.push(message);
    }
    if (logs.length === 0 && sent.length === 0) return { deliveries, complete: true };

    for (const log of logs) {
      if (deliveries.length >= maxMessages) return { deliveries, complete: false };
      const [result] = await routeToSvm(svm, { logs: [log], provider });
      deliveries.push({ direction: "evm-to-solana", result });
      await onSolanaDelivery?.(result);
    }
    for (const message of sent) {
      if (deliveries.length >= maxMessages) return { deliveries, complete: false };
      deliveredToEvm.add(message.messageId);
      const [result] = await routeFromSvm(svm, lane, message);
      deliveries.push({ direction: "solana-to-evm", message, result });
    }
    // Later scans start after the newest message seen; the ids above stay as the guard against a repeat.
    if (sent.length > 0) cursor = sent[sent.length - 1].signature;
  }
}
