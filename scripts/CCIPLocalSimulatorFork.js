/**
 * Hardhat 3 helpers for routing CCIP messages between forked networks (the JavaScript counterpart of the Solidity
 * `CCIPLocalSimulatorFork`). Supports pre-1.6 (`EVM2EVMOnRamp`), 1.6 and CCIP 2.0 (CCV-based) lanes.
 *
 * Every function takes the `NetworkConnection` returned by `network.connect()` and requires the
 * `@nomicfoundation/hardhat-ethers` plugin (it uses `connection.ethers`). Messages are sent on the source connection,
 * then routed on the destination connection:
 *
 *   const source = await network.connect({ network: "sepoliaFork" });
 *   const destination = await network.connect({ network: "arbitrumSepoliaFork" });
 *   const receipt = await (await router.ccipSend(destChainSelector, message, { value: fee })).wait();
 *   const [sent] = getCCIPMessages(source, receipt);
 *   await routeMessage(destination, destinationRouterAddress, sent);
 */

const LINK_FAUCET_ADDRESS = "0x4281eCF07378Ee595C564a59048801330f3084eE";

/** Dedicated CCIP 2.0 routers deployed next to the default router, keyed by chain id (verified on-chain, Sep 2026). */
export const CCIP_V2_ROUTERS = Object.freeze({
    11155111: "0x784d49a71BB4C48eB7dA4cD7e6Ecb424f9b5EAB1", // Ethereum Sepolia
    43113: "0x7C9B8B4e8024e5Ee8A630F6FCe9015e470dA5763", // Avalanche Fuji
});

// `Internal.MessageExecutionState.SUCCESS`
const EXECUTION_STATE_SUCCESS = BigInt(2);
// Verifier-result version the synthetic fork verifier is registered under on CCV resolvers ("FORK").
const SYNTHETIC_VERIFIER_VERSION = "0x464f524b";
// `Client.NO_EXECUTION_ADDRESS` = address(bytes20(keccak256("NO_EXECUTION_TAG")[:4])): marks manual execution.
const NO_EXECUTION_ADDRESS = "0xeba517d200000000000000000000000000000000";
const DEFAULT_GAS_LIMIT = BigInt(200_000);
// Gas for the CCIP 2.0 `execute` transaction. It must be explicit: `execute` does not revert when the inner execution
// runs out of gas (it records FAILURE with `NotEnoughGasForCall`), so a gas estimate converges on a limit that is too low.
const V2_EXECUTE_GAS_LIMIT = BigInt(15_000_000);
const GENERIC_EXTRA_ARGS_V2_TAG = "0x181dcf10";
const EVM_EXTRA_ARGS_V1_TAG = "0x97a657c9";

const PRE_V1_6_MESSAGE =
    "tuple(uint64 sourceChainSelector, address sender, address receiver, uint64 sequenceNumber, uint256 gasLimit, bool strict, uint64 nonce, address feeToken, uint256 feeTokenAmount, bytes data, tuple(address token, uint256 amount)[] tokenAmounts, bytes[] sourceTokenData, bytes32 messageId)";
const V1_6_HEADER = "tuple(bytes32 messageId, uint64 sourceChainSelector, uint64 destChainSelector, uint64 sequenceNumber, uint64 nonce)";
const V1_6_EVM2ANY_MESSAGE = `tuple(${V1_6_HEADER} header, address sender, bytes data, bytes receiver, bytes extraArgs, address feeToken, uint256 feeTokenAmount, uint256 feeValueJuels, tuple(address sourcePoolAddress, bytes destTokenAddress, bytes extraData, uint256 amount, bytes destExecData)[] tokenAmounts)`;
const V1_6_ANY2EVM_MESSAGE = `tuple(${V1_6_HEADER} header, bytes sender, bytes data, address receiver, uint256 gasLimit, tuple(bytes sourcePoolAddress, address destTokenAddress, uint32 destGasAmount, bytes extraData, uint256 amount)[] tokenAmounts)`;

const ABI = {
    link: ["function transfer(address to, uint256 amount) returns (bool)"],
    router: [
        "function getOffRamps() view returns (tuple(uint64 sourceChainSelector, address offRamp)[])",
        "function getOnRamp(uint64 destChainSelector) view returns (address)",
    ],
    typeAndVersion: ["function typeAndVersion() view returns (string)"],
    preV1_6OnRamp: [`event CCIPSendRequested(${PRE_V1_6_MESSAGE} message)`],
    v1_6OnRamp: [`event CCIPMessageSent(uint64 indexed destChainSelector, uint64 indexed sequenceNumber, ${V1_6_EVM2ANY_MESSAGE} message)`],
    v2OnRamp: [
        "event CCIPMessageSent(uint64 indexed destChainSelector, address indexed sender, bytes32 indexed messageId, address feeToken, uint256 tokenAmountBeforeTokenPoolFees, bytes encodedMessage, tuple(address issuer, uint32 destGasLimit, uint32 destBytesOverhead, uint256 feeTokenAmount, bytes extraArgs)[] receipts, bytes[] verifierBlobs)",
    ],
    preV1_6OffRamp: [
        "function getStaticConfig() view returns (tuple(address commitStore, uint64 chainSelector, uint64 sourceChainSelector, address onRamp, address prevOffRamp, address rmnProxy, address tokenAdminRegistry))",
        `function executeSingleMessage(${PRE_V1_6_MESSAGE} message, bytes[] offchainTokenData)`,
        `function executeSingleMessage(${PRE_V1_6_MESSAGE} message, bytes[] offchainTokenData, uint32[] tokenGasOverrides)`,
    ],
    v1_6OffRamp: [
        "function getSourceChainConfig(uint64 sourceChainSelector) view returns (tuple(address router, bool isEnabled, uint64 minSeqNr, bool isRMNVerificationDisabled, bytes onRamp))",
        `function executeSingleMessage(${V1_6_ANY2EVM_MESSAGE} message, bytes[] offchainTokenData, uint32[] tokenGasOverrides)`,
    ],
    v2OffRamp: [
        "function getSourceChainConfig(uint64 sourceChainSelector) view returns (tuple(address router, bool isEnabled, bytes[] onRamps, address[] defaultCCVs, address[] laneMandatedCCVs))",
        "function getCCVsForMessage(bytes encodedMessage) view returns (address[] requiredCCVs, address[] optionalCCVs, uint8 threshold)",
        "function execute(bytes encodedMessage, address[] ccvs, bytes[] verifierResults, uint32 gasLimitOverride)",
        "function getExecutionState(bytes32 messageId) view returns (uint8)",
        "event ExecutionStateChanged(uint64 indexed sourceChainSelector, uint64 indexed messageNumber, bytes32 indexed messageId, uint8 state, bytes returnData)",
    ],
    // Errors decoded in failure messages.
    knownErrors: [
        "error NotEnoughGasForCall()",
        "error InvalidRequestedFinality(bytes4 requestedFinality, bytes4 allowedFinality)",
        "error RequestedFinalityCanOnlyHaveOneMode(bytes4 encodedFinality)",
        "error ReceiverError(bytes err)",
        "error RequiredCCVMissing(address requiredCCV)",
        "error InboundImplementationNotFound(address ccv, bytes verifierResults)",
        "error SourceChainNotEnabled(uint64 sourceChainSelector)",
        "error SkippedAlreadyExecutedMessage(bytes32 messageId, uint64 sourceChainSelector, uint64 messageNumber)",
    ],
    ccvResolver: [
        "function owner() view returns (address)",
        "function applyInboundImplementationUpdates(tuple(bytes4 version, address verifier)[] implementations)",
    ],
};

/**
 * Requests LINK tokens from the testnet faucet by impersonating it, and returns the transaction hash.
 *
 * @param {object} connection Network connection from `network.connect()`
 * @param {string} linkAddress The address of the LINK contract on the connected network
 * @param {string} to The address to send LINK to
 * @param {bigint} amount The amount of LINK to request
 * @returns {Promise<string>} The transaction hash of the transfer
 */
export async function requestLinkFromTheFaucet(connection, linkAddress, to, amount) {
    const { ethers } = connection;
    const faucet = await _impersonate(connection, LINK_FAUCET_ADDRESS);
    const tx = await new ethers.Contract(linkAddress, ABI.link, faucet).transfer(to, amount);
    return tx.hash;
}

/**
 * @typedef {Object} CCIPSentMessage
 * @property {"PRE_V1_6" | "V1_6" | "V2"} era CCIP protocol version of the lane the message was sent on
 * @property {string} onRamp Source OnRamp that emitted the message
 * @property {string} messageId
 * @property {bigint} sourceChainSelector
 * @property {bigint} destChainSelector
 * @property {object} message Era-specific payload: the pre-1.6 `EVM2EVMMessage`, the 1.6 `EVM2AnyRampMessage`, or for
 *                            CCIP 2.0 `{ encodedMessage, receipts }`
 */

/**
 * Extracts every CCIP message sent in a transaction, for all supported protocol versions.
 *
 * @param {object} connection Network connection of the source chain
 * @param {object} receipt Transaction receipt of the `ccipSend` call
 * @returns {CCIPSentMessage[]} The sent messages, in log order (empty if none)
 */
export function getCCIPMessages(connection, receipt) {
    const { ethers } = connection;
    const preV1_6 = new ethers.Interface(ABI.preV1_6OnRamp);
    const v1_6 = new ethers.Interface(ABI.v1_6OnRamp);
    const v2 = new ethers.Interface(ABI.v2OnRamp);
    const topics = {
        preV1_6: preV1_6.getEvent("CCIPSendRequested").topicHash,
        v1_6: v1_6.getEvent("CCIPMessageSent").topicHash,
        v2: v2.getEvent("CCIPMessageSent").topicHash,
    };

    const messages = [];
    for (const log of receipt.logs) {
        const topic0 = log.topics[0];
        if (topic0 === topics.preV1_6) {
            const m = preV1_6.parseLog(log).args.message;
            messages.push({
                era: "PRE_V1_6",
                onRamp: log.address,
                messageId: m.messageId,
                sourceChainSelector: m.sourceChainSelector,
                destChainSelector: undefined,
                message: {
                    sourceChainSelector: m.sourceChainSelector,
                    sender: m.sender,
                    receiver: m.receiver,
                    sequenceNumber: m.sequenceNumber,
                    gasLimit: m.gasLimit,
                    strict: m.strict,
                    nonce: m.nonce,
                    feeToken: m.feeToken,
                    feeTokenAmount: m.feeTokenAmount,
                    data: m.data,
                    tokenAmounts: m.tokenAmounts.map(([token, amount]) => ({ token, amount })),
                    sourceTokenData: [...m.sourceTokenData],
                    messageId: m.messageId,
                },
            });
        } else if (topic0 === topics.v1_6) {
            const m = v1_6.parseLog(log).args.message;
            messages.push({
                era: "V1_6",
                onRamp: log.address,
                messageId: m.header.messageId,
                sourceChainSelector: m.header.sourceChainSelector,
                destChainSelector: m.header.destChainSelector,
                message: {
                    header: {
                        messageId: m.header.messageId,
                        sourceChainSelector: m.header.sourceChainSelector,
                        destChainSelector: m.header.destChainSelector,
                        sequenceNumber: m.header.sequenceNumber,
                        nonce: m.header.nonce,
                    },
                    sender: m.sender,
                    data: m.data,
                    receiver: m.receiver,
                    extraArgs: m.extraArgs,
                    feeToken: m.feeToken,
                    feeTokenAmount: m.feeTokenAmount,
                    feeValueJuels: m.feeValueJuels,
                    tokenAmounts: m.tokenAmounts.map(([sourcePoolAddress, destTokenAddress, extraData, amount, destExecData]) => ({
                        sourcePoolAddress,
                        destTokenAddress,
                        extraData,
                        amount,
                        destExecData,
                    })),
                },
            });
        } else if (topic0 === topics.v2) {
            const args = v2.parseLog(log).args;
            // MessageV1 wire format starts with version (1 byte), sourceChainSelector and destChainSelector (8 bytes each,
            // big endian). These fields precede everything that changed across codec versions, so no full decode is needed.
            const encoded = ethers.getBytes(args.encodedMessage);
            messages.push({
                era: "V2",
                onRamp: log.address,
                messageId: args.messageId,
                sourceChainSelector: ethers.toBigInt(encoded.slice(1, 9)),
                destChainSelector: ethers.toBigInt(encoded.slice(9, 17)),
                message: {
                    encodedMessage: args.encodedMessage,
                    receipts: args.receipts.map(([issuer, destGasLimit, destBytesOverhead, feeTokenAmount, extraArgs]) => ({
                        issuer,
                        destGasLimit,
                        destBytesOverhead,
                        feeTokenAmount,
                        extraArgs,
                    })),
                },
            });
        }
    }
    return messages;
}

/**
 * Routes a sent message on the destination (connected) network, as the destination OffRamp would execute it.
 *
 * - pre-1.6 and 1.6: impersonates the lane's OffRamp and calls `executeSingleMessage`.
 * - CCIP 2.0: the OffRamp selects the CCVs (`getCCVsForMessage`), CCVs that are owner-configurable verifier resolvers
 *   are pointed at a synthetic no-op verifier, and the raw encoded message is executed through the permissionless
 *   `execute`. A message is only delivered if the OffRamp reports SUCCESS.
 *
 * @param {object} connection Network connection of the destination chain
 * @param {string | string[]} routerAddresses Destination router address(es) whose OffRamps are searched, e.g. the default
 *                                            router and `CCIP_V2_ROUTERS[chainId]`
 * @param {CCIPSentMessage} sent A message returned by `getCCIPMessages`
 * @param {Object} [options]
 * @param {boolean} [options.forceExecution=false] Execute CCIP 2.0 messages whose executor is `NO_EXECUTION_ADDRESS`
 *                                                 (manual execution)
 * @returns {Promise<Object>} `{ offRamp, executed, reason }`: `executed` is false only for a CCIP 2.0 NO_EXECUTION
 *          message routed without `forceExecution` (`reason` is then `"NO_EXECUTION_ADDRESS"`)
 * @throws {Error} If no OffRamp serves the lane, or if execution fails (receiver revert, finality or CCV rejection)
 */
export async function routeMessage(connection, routerAddresses, sent, options = {}) {
    const routers = (Array.isArray(routerAddresses) ? routerAddresses : [routerAddresses]).filter(Boolean);
    const lane = await _findOffRamp(connection, routers, sent.sourceChainSelector, sent.onRamp);
    if (!lane) {
        throw new Error(
            `No OffRamp found for source chain ${sent.sourceChainSelector} and OnRamp ${sent.onRamp} on routers ${routers.join(", ")}`
        );
    }

    if (sent.era === "PRE_V1_6") {
        await _executePreV1_6(connection, lane, sent.message);
    } else if (sent.era === "V1_6") {
        await _executeV1_6(connection, lane.offRamp, sent.message);
    } else if (sent.era === "V2") {
        const receipts = sent.message.receipts;
        const isNoExecution = receipts.length >= 2 && receipts[receipts.length - 2].issuer.toLowerCase() === NO_EXECUTION_ADDRESS;
        if (isNoExecution && !options.forceExecution) {
            return { offRamp: lane.offRamp, executed: false, reason: "NO_EXECUTION_ADDRESS" };
        }
        await _executeV2(connection, lane.offRamp, sent.message.encodedMessage);
    } else {
        throw new Error(`Unsupported CCIP era: ${sent.era}`);
    }

    return { offRamp: lane.offRamp, executed: true };
}

// ================================================================
// │                        OffRamp lookup                        │
// ================================================================

/**
 * Finds the OffRamp whose lane is bound to `sourceOnRamp`. Routers list OffRamps of several versions for the same
 * source chain (1.2 / 1.5 / 1.6 / 2.0 during migrations), so candidates are matched by `typeAndVersion` and a candidate
 * of unknown shape is skipped.
 * @private
 */
async function _findOffRamp(connection, routerAddresses, sourceChainSelector, sourceOnRamp) {
    const { ethers } = connection;
    for (const routerAddress of routerAddresses) {
        let offRamps;
        try {
            offRamps = await new ethers.Contract(routerAddress, ABI.router, ethers.provider).getOffRamps();
        } catch {
            continue;
        }
        for (let i = offRamps.length - 1; i >= 0; --i) {
            const [candidateSelector, candidate] = offRamps[i];
            if (candidateSelector !== BigInt(sourceChainSelector)) continue;
            const typeAndVersion = await _matchOffRamp(connection, candidate, sourceChainSelector, sourceOnRamp);
            if (typeAndVersion !== null) return { offRamp: candidate, typeAndVersion };
        }
    }
    return null;
}

/**
 * @private
 * @returns {Promise<?string>} The candidate's typeAndVersion ("" if unreadable) when it serves the lane, else null
 */
async function _matchOffRamp(connection, offRamp, sourceChainSelector, sourceOnRamp) {
    const { ethers } = connection;
    let typeAndVersion = "";
    try {
        typeAndVersion = await new ethers.Contract(offRamp, ABI.typeAndVersion, ethers.provider).typeAndVersion();
    } catch {
        // No readable typeAndVersion: probe every known shape below.
    }

    const is = (prefix) => typeAndVersion.startsWith(prefix);
    const known = is("OffRamp 2.") || is("OffRamp 1.6") || is("EVM2EVMOffRamp 1.");
    if (typeAndVersion !== "" && !known) return null;

    const onRamp = sourceOnRamp.toLowerCase();
    const matchesEncoded = (encoded) => {
        try {
            return ethers.getBytes(encoded).length === 32 && ethers.AbiCoder.defaultAbiCoder().decode(["address"], encoded)[0].toLowerCase() === onRamp;
        } catch {
            return false;
        }
    };

    if (typeAndVersion === "" || is("OffRamp 2.")) {
        try {
            const cfg = await new ethers.Contract(offRamp, ABI.v2OffRamp, ethers.provider).getSourceChainConfig(sourceChainSelector);
            if (cfg.isEnabled && cfg.onRamps.some(matchesEncoded)) return typeAndVersion;
        } catch {}
        if (is("OffRamp 2.")) return null;
    }
    if (typeAndVersion === "" || is("OffRamp 1.6")) {
        try {
            const cfg = await new ethers.Contract(offRamp, ABI.v1_6OffRamp, ethers.provider).getSourceChainConfig(sourceChainSelector);
            if (cfg.isEnabled && matchesEncoded(cfg.onRamp)) return typeAndVersion;
        } catch {}
    }
    try {
        const cfg = await new ethers.Contract(offRamp, ABI.preV1_6OffRamp, ethers.provider).getStaticConfig();
        if (cfg.onRamp.toLowerCase() === onRamp && cfg.sourceChainSelector === BigInt(sourceChainSelector)) return typeAndVersion;
    } catch {}
    return null;
}

// ================================================================
// │                          Execution                           │
// ================================================================

async function _executePreV1_6(connection, lane, message) {
    const { ethers } = connection;
    const offRamp = new ethers.Contract(lane.offRamp, ABI.preV1_6OffRamp, await _impersonate(connection, lane.offRamp));
    const offchainTokenData = message.tokenAmounts.map(() => "0x");
    // EVM2EVMOffRamp 1.5 takes per-token gas overrides; older versions do not.
    if (lane.typeAndVersion.startsWith("EVM2EVMOffRamp 1.5")) {
        const tokenGasOverrides = message.tokenAmounts.map(() => message.gasLimit);
        await _send(offRamp["executeSingleMessage((uint64,address,address,uint64,uint256,bool,uint64,address,uint256,bytes,(address,uint256)[],bytes[],bytes32),bytes[],uint32[])"](message, offchainTokenData, tokenGasOverrides));
    } else {
        await _send(offRamp["executeSingleMessage((uint64,address,address,uint64,uint256,bool,uint64,address,uint256,bytes,(address,uint256)[],bytes[],bytes32),bytes[])"](message, offchainTokenData));
    }
}

async function _executeV1_6(connection, offRampAddress, message) {
    const { ethers } = connection;
    const coder = ethers.AbiCoder.defaultAbiCoder();
    const gasLimit = _gasLimitFromExtraArgs(connection, message.extraArgs);

    const any2EVMMessage = {
        header: message.header,
        // Production 1.6 lanes deliver an EVM sender as a 32-byte ABI word.
        sender: coder.encode(["address"], [message.sender]),
        data: message.data,
        receiver: _decodeEVMAddress(connection, message.receiver),
        gasLimit,
        tokenAmounts: message.tokenAmounts.map((t) => ({
            sourcePoolAddress: coder.encode(["address"], [t.sourcePoolAddress]),
            destTokenAddress: _decodeEVMAddress(connection, t.destTokenAddress),
            destGasAmount: coder.decode(["uint32"], t.destExecData)[0],
            extraData: t.extraData,
            amount: t.amount,
        })),
    };

    const offRamp = new ethers.Contract(offRampAddress, ABI.v1_6OffRamp, await _impersonate(connection, offRampAddress));
    await _send(
        offRamp.executeSingleMessage(
            any2EVMMessage,
            message.tokenAmounts.map(() => "0x"),
            message.tokenAmounts.map(() => gasLimit)
        )
    );
}

async function _executeV2(connection, offRampAddress, encodedMessage) {
    const { ethers } = connection;
    const offRampView = new ethers.Contract(offRampAddress, ABI.v2OffRamp, ethers.provider);

    const messageId = ethers.keccak256(encodedMessage);
    let required, optional, threshold;
    try {
        [required, optional, threshold] = await offRampView.getCCVsForMessage(encodedMessage);
    } catch (error) {
        // The OffRamp validates the message while selecting CCVs (e.g. receiver finality), so it cannot be executed.
        const revertData = error?.data ?? error?.info?.error?.data ?? "n/a";
        throw new Error(
            `CCIP 2.0 message ${messageId} cannot be executed: OffRamp.getCCVsForMessage reverted with ${_describeError(connection, revertData)}`
        );
    }
    // Same selection as the OffRamp quorum: all required CCVs, plus `threshold` optional ones.
    const ccvs = [...required, ...optional].slice(0, Math.max(required.length, Math.min(required.length + optional.length, Number(threshold))));
    const verifierResults = [];
    for (const ccv of ccvs) {
        verifierResults.push((await _pointResolverAtSyntheticVerifier(connection, ccv)) ? SYNTHETIC_VERIFIER_VERSION : "0x");
    }

    const [executor] = await ethers.getSigners();
    const latestBlock = await ethers.provider.getBlock("latest");
    const gasLimit = latestBlock.gasLimit < V2_EXECUTE_GAS_LIMIT ? latestBlock.gasLimit : V2_EXECUTE_GAS_LIMIT;
    const receipt = await _send(offRampView.connect(executor).execute(encodedMessage, ccvs, verifierResults, 0, { gasLimit }));

    // `execute` does not revert when the inner execution fails on a first attempt: it records FAILURE.
    const state = await offRampView.getExecutionState(messageId);
    if (state !== EXECUTION_STATE_SUCCESS) {
        const offRampInterface = new ethers.Interface(ABI.v2OffRamp);
        const stateChanged = receipt.logs
            .map((log) => {
                try {
                    return offRampInterface.parseLog(log);
                } catch {
                    return null;
                }
            })
            .find((parsed) => parsed?.name === "ExecutionStateChanged" && parsed.args.messageId === messageId);
        throw new Error(
            `CCIP 2.0 message ${messageId} did not execute successfully (state ${state}): ${_describeError(connection, stateChanged?.args.returnData ?? "n/a")}`
        );
    }
}

/**
 * Points an owner-configurable CCV resolver at a synthetic no-op verifier for the "FORK" verifier-result version.
 * @returns {Promise<boolean>} Whether the CCV could be configured (otherwise it gets an empty verifier result)
 * @private
 */
async function _pointResolverAtSyntheticVerifier(connection, ccv) {
    const { ethers } = connection;
    let owner;
    try {
        owner = await new ethers.Contract(ccv, ABI.ccvResolver, ethers.provider).owner();
    } catch {
        return false;
    }
    if (owner === ethers.ZeroAddress) return false;

    const verifier = ethers.getAddress(ethers.dataSlice(ethers.id("chainlink-local.synthetic-ccv-verifier"), 12));
    // STOP: every call succeeds with empty return data, which is all `verifyMessage` needs.
    await connection.provider.request({ method: "hardhat_setCode", params: [verifier, "0x00"] });

    try {
        const resolver = new ethers.Contract(ccv, ABI.ccvResolver, await _impersonate(connection, owner));
        await _send(resolver.applyInboundImplementationUpdates([{ version: SYNTHETIC_VERIFIER_VERSION, verifier }]));
        return true;
    } catch {
        return false;
    }
}

// ================================================================
// │                           Utilities                          │
// ================================================================

async function _impersonate(connection, address) {
    await connection.provider.request({ method: "hardhat_impersonateAccount", params: [address] });
    await connection.provider.request({ method: "hardhat_setBalance", params: [address, "0x56BC75E2D63100000"] }); // 100 ETH
    return connection.ethers.getSigner(address);
}

async function _send(txPromise) {
    const tx = await txPromise;
    return tx.wait();
}

/**
 * Decodes revert data of the errors in `ABI.knownErrors`, falling back to the raw hex.
 * @private
 */
function _describeError(connection, data) {
    try {
        const parsed = new connection.ethers.Interface(ABI.knownErrors).parseError(data);
        if (parsed) return `${parsed.name}(${parsed.args.map(String).join(", ")})`;
    } catch {}
    return String(data);
}

function _decodeEVMAddress(connection, encoded) {
    const { ethers } = connection;
    const bytes = ethers.getBytes(encoded);
    if (bytes.length === 32) return ethers.AbiCoder.defaultAbiCoder().decode(["address"], encoded)[0];
    if (bytes.length === 20) return ethers.getAddress(ethers.hexlify(bytes));
    throw new Error(`Invalid EVM address encoding: ${encoded}`);
}

function _gasLimitFromExtraArgs(connection, extraArgs) {
    const { ethers } = connection;
    if (ethers.getBytes(extraArgs).length === 0) return DEFAULT_GAS_LIMIT;
    const tag = ethers.dataSlice(extraArgs, 0, 4);
    const body = ethers.dataSlice(extraArgs, 4);
    const coder = ethers.AbiCoder.defaultAbiCoder();
    if (tag === GENERIC_EXTRA_ARGS_V2_TAG) return coder.decode(["tuple(uint256 gasLimit, bool allowOutOfOrderExecution)"], body)[0].gasLimit;
    if (tag === EVM_EXTRA_ARGS_V1_TAG) return coder.decode(["uint256"], body)[0];
    throw new Error(`Unsupported 1.6 extraArgs tag: ${tag}`);
}
