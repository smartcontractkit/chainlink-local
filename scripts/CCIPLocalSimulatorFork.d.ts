/**
 * TypeScript declarations for the Hardhat 3 JavaScript helper `CCIPLocalSimulatorFork.js`.
 *
 * `EthersConnection` is a minimal structural type — not the real `NetworkConnection` type from `hardhat` / the
 * `@nomicfoundation/hardhat-ethers` chain type extension — so that any object shaped like one (in particular, what
 * `network.connect()` actually returns once the `@nomicfoundation/hardhat-ethers` plugin is registered) is accepted
 * without this package depending on either of those packages' types directly.
 */

/** A minimal, structurally-typed stand-in for ethers.js's `Contract` instances used by this module's return values. */
export interface EthersContractLike {
    getAddress(): Promise<string>;
    [name: string]: any;
}

/** The subset of `ethers.js`'s runtime API (as exposed by `@nomicfoundation/hardhat-ethers`) this module relies on. */
export interface EthersLike {
    readonly provider: EthersProviderLike;
    Contract: new (target: string, abi: ReadonlyArray<string>, runner?: unknown) => EthersContractLike;
    Interface: new (abi: ReadonlyArray<string>) => unknown;
    AbiCoder: { defaultAbiCoder(): unknown };
    ZeroAddress: string;
    getSigners(): Promise<unknown[]>;
    getSigner(address: string): Promise<unknown>;
    getBytes(value: string): Uint8Array;
    dataSlice(value: string, start?: number, end?: number): string;
    hexlify(value: Uint8Array | string): string;
    getAddress(value: string): string;
    keccak256(value: string): string;
    toBigInt(value: string | Uint8Array | number | bigint): bigint;
    id(text: string): string;
}

/** The subset of an `ethers` `Provider` this module relies on, reached either via `connection.provider` directly or
 * via `connection.ethers.provider`. */
export interface EthersProviderLike {
    request(args: { method: string; params?: unknown[] }): Promise<unknown>;
    getBlock(blockTag: string): Promise<{ gasLimit: bigint } | null>;
}

/**
 * Minimal structural shape of the Hardhat 3 `NetworkConnection` returned by `network.connect()` once the
 * `@nomicfoundation/hardhat-ethers` plugin is registered in `hardhat.config`. Every exported function in this
 * module throws a clear error (naming the plugin) if `connection.ethers` is missing.
 */
export interface EthersConnection {
    readonly ethers: EthersLike;
    readonly provider: EthersProviderLike;
}

/** Dedicated CCIP 2.0 routers deployed next to the default router, keyed by chain id (verified on-chain, Sep 2026). */
export declare const CCIP_V2_ROUTERS: Readonly<Record<number, string>>;

/**
 * Requests LINK tokens from the testnet faucet by impersonating it, and returns the transaction hash.
 */
export declare function requestLinkFromTheFaucet(
    connection: EthersConnection,
    linkAddress: string,
    to: string,
    amount: bigint
): Promise<string>;

export interface EVMTokenAmount {
    token: string;
    amount: bigint;
}

/** Pre-1.6 `Internal.EVM2EVMMessage`. */
export interface PreV1dot6Message {
    sourceChainSelector: bigint;
    sender: string;
    receiver: string;
    sequenceNumber: bigint;
    gasLimit: bigint;
    strict: boolean;
    nonce: bigint;
    feeToken: string;
    feeTokenAmount: bigint;
    data: string;
    tokenAmounts: EVMTokenAmount[];
    sourceTokenData: string[];
    messageId: string;
}

export interface V1dot6RampMessageHeader {
    messageId: string;
    sourceChainSelector: bigint;
    destChainSelector: bigint;
    sequenceNumber: bigint;
    nonce: bigint;
}

export interface V1dot6TokenAmount {
    sourcePoolAddress: string;
    destTokenAddress: string;
    extraData: string;
    amount: bigint;
    destExecData: string;
}

/** 1.6 `Internal.EVM2AnyRampMessage`, as emitted by the source `OnRamp`'s `CCIPMessageSent` event. */
export interface V1dot6Message {
    header: V1dot6RampMessageHeader;
    sender: string;
    data: string;
    receiver: string;
    extraArgs: string;
    feeToken: string;
    feeTokenAmount: bigint;
    feeValueJuels: bigint;
    tokenAmounts: V1dot6TokenAmount[];
}

export interface V2Receipt {
    issuer: string;
    destGasLimit: bigint;
    destBytesOverhead: bigint;
    feeTokenAmount: bigint;
    extraArgs: string;
}

/** CCIP 2.0 payload: the raw `MessageV1`-encoded wire format plus the OnRamp's fee receipts. */
export interface V2Message {
    encodedMessage: string;
    receipts: V2Receipt[];
}

interface CCIPSentMessageBase {
    onRamp: string;
    messageId: string;
    sourceChainSelector: bigint;
}

export interface PreV1dot6SentMessage extends CCIPSentMessageBase {
    era: "PRE_V1_6";
    destChainSelector: undefined;
    message: PreV1dot6Message;
}

export interface V1dot6SentMessage extends CCIPSentMessageBase {
    era: "V1_6";
    destChainSelector: bigint;
    message: V1dot6Message;
}

export interface V2SentMessage extends CCIPSentMessageBase {
    era: "V2";
    destChainSelector: bigint;
    message: V2Message;
}

/** A CCIP message extracted by `getCCIPMessages`, tagged by protocol era. */
export type CCIPSentMessage = PreV1dot6SentMessage | V1dot6SentMessage | V2SentMessage;

/** The subset of an `ethers` `TransactionReceipt` this module reads. */
export interface TransactionReceiptLike {
    logs: ReadonlyArray<{ address: string; topics: ReadonlyArray<string>; data: string }>;
}

/**
 * Extracts every CCIP message sent in a transaction, for all supported protocol versions.
 */
export declare function getCCIPMessages(
    connection: EthersConnection,
    receipt: TransactionReceiptLike
): CCIPSentMessage[];

export interface RouteMessageOptions {
    /** Execute CCIP 2.0 messages whose executor is `NO_EXECUTION_ADDRESS` (manual execution). Default `false`. */
    forceExecution?: boolean;
}

export interface RouteMessageResult {
    offRamp: string;
    executed: boolean;
    /** Set only when `executed` is `false` (a CCIP 2.0 `NO_EXECUTION_ADDRESS` message routed without `forceExecution`). */
    reason?: "NO_EXECUTION_ADDRESS";
}

/**
 * Routes a sent message on the destination (connected) network, as the destination OffRamp would execute it.
 */
export declare function routeMessage(
    connection: EthersConnection,
    routerAddresses: string | string[],
    sent: CCIPSentMessage,
    options?: RouteMessageOptions
): Promise<RouteMessageResult>;
