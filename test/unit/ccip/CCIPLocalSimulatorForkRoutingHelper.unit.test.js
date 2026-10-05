// Local-EDR-network tests (no forking, no RPC) for the OffRamp lookup and execution paths of the JavaScript helper
// `scripts/CCIPLocalSimulatorFork.js`. Uses the mocks in `src/test/ccip/JsHelperOffRampMocks.sol` and the real
// pinned `MessageV1Codec` (via `src/test/ccip/MessageV1CodecTestHelper.sol`) to build a genuine CCIP 2.0 wire-format
// `encodedMessage`. Run with `npm run js-unit-test` (part of `npm test`).
import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import { network } from "hardhat";

import { routeMessage, _stampedOffRamp } from "../../../scripts/CCIPLocalSimulatorFork.js";

const SOURCE_SELECTOR = 16015286601757825753n;
const DEST_SELECTOR = 3478487238524512106n;
const NO_EXECUTION_ADDRESS = "0xeba517d200000000000000000000000000000000";

describe("routeMessage (local EDR network, mocked OffRamps)", () => {
    let connection, ethers, codecHelper;

    before(async () => {
        connection = await network.connect();
        ethers = connection.ethers;
        const factory = await ethers.getContractFactory(
            "src/test/ccip/MessageV1CodecTestHelper.sol:MessageV1CodecTestHelper"
        );
        codecHelper = await factory.deploy();
        await codecHelper.waitForDeployment();
    });

    async function deployRouter() {
        const factory = await ethers.getContractFactory("src/test/ccip/JsHelperOffRampMocks.sol:JsMockRouter");
        const router = await factory.deploy();
        await router.waitForDeployment();
        return router;
    }

    async function deployPreV1dot6(typeAndVersion, chainSelector, sourceChainSelector, onRamp) {
        const factory = await ethers.getContractFactory(
            "src/test/ccip/JsHelperOffRampMocks.sol:JsMockPreV1dot6OffRamp"
        );
        const c = await factory.deploy(typeAndVersion, chainSelector, sourceChainSelector, onRamp);
        await c.waitForDeployment();
        return c;
    }

    async function deployV1dot6(sourceChainSelector, onRamp, localChainSelector) {
        const factory = await ethers.getContractFactory("src/test/ccip/JsHelperOffRampMocks.sol:JsMockV1dot6OffRamp");
        const c = await factory.deploy(sourceChainSelector, onRamp, localChainSelector);
        await c.waitForDeployment();
        return c;
    }

    async function deployV2(sourceChainSelector, onRamps) {
        const factory = await ethers.getContractFactory("src/test/ccip/JsHelperOffRampMocks.sol:JsMockV2OffRamp");
        const c = await factory.deploy(sourceChainSelector, onRamps);
        await c.waitForDeployment();
        return c;
    }

    async function deployUnknown() {
        const factory = await ethers.getContractFactory("src/test/ccip/JsHelperOffRampMocks.sol:JsMockUnknownOffRamp");
        const c = await factory.deploy();
        await c.waitForDeployment();
        return c;
    }

    function abiEncodeAddress(addr) {
        return ethers.AbiCoder.defaultAbiCoder().encode(["address"], [addr]);
    }

    async function encodeV2Message({
        sourceChainSelector = SOURCE_SELECTOR,
        destChainSelector = DEST_SELECTOR,
        messageNumber = 1n,
        onRampAddress,
        offRampAddress,
        sender = "0x3333333333333333333333333333333333333333",
        receiver = "0x4444444444444444444444444444444444444444",
        data = "0x",
    }) {
        const message = {
            sourceChainSelector,
            destChainSelector,
            messageNumber,
            executionGasLimit: 200_000,
            ccipReceiveGasLimit: 100_000,
            finality: "0x00000000",
            ccvAndExecutorHash: ethers.ZeroHash,
            onRampAddress: abiEncodeAddress(onRampAddress),
            offRampAddress,
            sender: abiEncodeAddress(sender),
            receiver,
            destBlob: "0x",
            tokenTransfer: [],
            data,
        };
        return codecHelper.encodeMessageV1(message);
    }

    describe("pre-1.6 lanes", () => {
        it("1.5.x OffRamp: uses the 3-argument executeSingleMessage overload and passes a zero gas override per token", async () => {
            const router = await deployRouter();
            const onRamp = "0x1111111111111111111111111111111111111111";
            const offRamp = await deployPreV1dot6("EVM2EVMOffRamp 1.5.0", DEST_SELECTOR, SOURCE_SELECTOR, onRamp);
            await router.addOffRamp(SOURCE_SELECTOR, await offRamp.getAddress());

            const sent = {
                era: "PRE_V1_6",
                onRamp,
                sourceChainSelector: SOURCE_SELECTOR,
                message: {
                    sourceChainSelector: SOURCE_SELECTOR,
                    sender: onRamp,
                    receiver: "0x5555555555555555555555555555555555555555",
                    sequenceNumber: 1,
                    gasLimit: 200_000n,
                    strict: false,
                    nonce: 1,
                    feeToken: ethers.ZeroAddress,
                    feeTokenAmount: 0,
                    data: "0x",
                    tokenAmounts: [{ token: "0x6666666666666666666666666666666666666666", amount: 1n }],
                    sourceTokenData: ["0x"],
                    messageId: ethers.id("message-1"),
                },
            };

            const result = await routeMessage(connection, await router.getAddress(), sent);
            assert.equal(result.executed, true);
            assert.equal(await offRamp.callsWithOverridesCount(), 1n);
            assert.equal(await offRamp.callsWithoutOverridesCount(), 0n);
            const overrides = await offRamp.lastTokenGasOverrides();
            assert.deepEqual(overrides.map(Number), [0]);
        });

        it("1.2.x OffRamp: uses the 2-argument executeSingleMessage overload (no per-token gas override param)", async () => {
            const router = await deployRouter();
            const onRamp = "0x1111111111111111111111111111111111111111";
            const offRamp = await deployPreV1dot6("EVM2EVMOffRamp 1.2.0", DEST_SELECTOR, SOURCE_SELECTOR, onRamp);
            await router.addOffRamp(SOURCE_SELECTOR, await offRamp.getAddress());

            const sent = {
                era: "PRE_V1_6",
                onRamp,
                sourceChainSelector: SOURCE_SELECTOR,
                message: {
                    sourceChainSelector: SOURCE_SELECTOR,
                    sender: onRamp,
                    receiver: "0x5555555555555555555555555555555555555555",
                    sequenceNumber: 1,
                    gasLimit: 200_000n,
                    strict: false,
                    nonce: 1,
                    feeToken: ethers.ZeroAddress,
                    feeTokenAmount: 0,
                    data: "0x",
                    tokenAmounts: [],
                    sourceTokenData: [],
                    messageId: ethers.id("message-2"),
                },
            };

            await routeMessage(connection, await router.getAddress(), sent);
            assert.equal(await offRamp.callsWithoutOverridesCount(), 1n);
            assert.equal(await offRamp.callsWithOverridesCount(), 0n);
        });

        it("decodes a known revert reason from executeSingleMessage and keeps the original error as `cause`", async () => {
            const router = await deployRouter();
            const onRamp = "0x1111111111111111111111111111111111111111";
            const offRamp = await deployPreV1dot6("EVM2EVMOffRamp 1.5.0", DEST_SELECTOR, SOURCE_SELECTOR, onRamp);
            // `TokenHandlingError(bytes)` — pre-1.6 `EVM2EVMOffRamp` signature (`git show v0.2.9:abi/EVM2EVMOffRamp.json`).
            const errIface = new ethers.Interface(["error TokenHandlingError(bytes err)"]);
            const revertData = errIface.encodeErrorResult("TokenHandlingError", ["0xdead"]);
            await offRamp.setRevertData(revertData);
            await router.addOffRamp(SOURCE_SELECTOR, await offRamp.getAddress());

            const sent = {
                era: "PRE_V1_6",
                onRamp,
                sourceChainSelector: SOURCE_SELECTOR,
                message: {
                    sourceChainSelector: SOURCE_SELECTOR,
                    sender: onRamp,
                    receiver: "0x5555555555555555555555555555555555555555",
                    sequenceNumber: 1,
                    gasLimit: 200_000n,
                    strict: false,
                    nonce: 1,
                    feeToken: ethers.ZeroAddress,
                    feeTokenAmount: 0,
                    data: "0x",
                    tokenAmounts: [],
                    sourceTokenData: [],
                    messageId: ethers.id("message-3"),
                },
            };

            await assert.rejects(routeMessage(connection, await router.getAddress(), sent), (err) => {
                assert.match(err.message, /TokenHandlingError\(0xdead\)/);
                assert.ok(err.cause, "original error should be preserved as `cause`");
                return true;
            });
        });
    });

    describe("1.6 lanes", () => {
        it("executes when the connected OffRamp's static chain selector matches the message's destChainSelector, with zero token gas overrides", async () => {
            const router = await deployRouter();
            const onRamp = "0x2222222222222222222222222222222222222222";
            const offRamp = await deployV1dot6(SOURCE_SELECTOR, onRamp, DEST_SELECTOR);
            await router.addOffRamp(SOURCE_SELECTOR, await offRamp.getAddress());

            const sent = {
                era: "V1_6",
                onRamp,
                sourceChainSelector: SOURCE_SELECTOR,
                destChainSelector: DEST_SELECTOR,
                message: {
                    header: {
                        messageId: ethers.id("message-4"),
                        sourceChainSelector: SOURCE_SELECTOR,
                        destChainSelector: DEST_SELECTOR,
                        sequenceNumber: 1,
                        nonce: 1,
                    },
                    sender: "0x7777777777777777777777777777777777777777",
                    data: "0x",
                    receiver: "0x5555555555555555555555555555555555555555",
                    extraArgs: "0x",
                    feeToken: ethers.ZeroAddress,
                    feeTokenAmount: 0,
                    feeValueJuels: 0,
                    tokenAmounts: [
                        {
                            sourcePoolAddress: "0x8888888888888888888888888888888888888888",
                            destTokenAddress: "0x9999999999999999999999999999999999999999",
                            extraData: "0x",
                            amount: 1n,
                            destExecData: ethers.AbiCoder.defaultAbiCoder().encode(["uint32"], [123]),
                        },
                    ],
                },
            };

            const result = await routeMessage(connection, await router.getAddress(), sent);
            assert.equal(result.executed, true);
            assert.equal(await offRamp.callCount(), 1n);
            const overrides = await offRamp.lastTokenGasOverrides();
            assert.deepEqual(overrides.map(Number), [0]);
            // Sender must be delivered as a 32-byte ABI word (see the existing Solidity-side assertion in
            // `CCIPLocalSimulatorForkRouting.t.sol`'s `test_executeV1dot6_encodesSenderAsAbiWord`).
            assert.equal(ethers.getBytes(await offRamp.lastSender()).length, 32);
        });

        it("throws a clear error when the connected OffRamp's chain selector does not match destChainSelector", async () => {
            const router = await deployRouter();
            const onRamp = "0x2222222222222222222222222222222222222222";
            // OffRamp reports it is on chain selector DEST_SELECTOR + 1n, but the message targets DEST_SELECTOR.
            const offRamp = await deployV1dot6(SOURCE_SELECTOR, onRamp, DEST_SELECTOR + 1n);
            await router.addOffRamp(SOURCE_SELECTOR, await offRamp.getAddress());

            const sent = {
                era: "V1_6",
                onRamp,
                sourceChainSelector: SOURCE_SELECTOR,
                destChainSelector: DEST_SELECTOR,
                message: {
                    header: {
                        messageId: ethers.id("message-5"),
                        sourceChainSelector: SOURCE_SELECTOR,
                        destChainSelector: DEST_SELECTOR,
                        sequenceNumber: 1,
                        nonce: 1,
                    },
                    sender: "0x7777777777777777777777777777777777777777",
                    data: "0x",
                    receiver: "0x5555555555555555555555555555555555555555",
                    extraArgs: "0x",
                    feeToken: ethers.ZeroAddress,
                    feeTokenAmount: 0,
                    feeValueJuels: 0,
                    tokenAmounts: [],
                },
            };

            await assert.rejects(routeMessage(connection, await router.getAddress(), sent), (err) => {
                assert.match(err.message, /destination chain selector/i);
                return true;
            });
            assert.equal(await offRamp.callCount(), 0n);
        });
    });

    describe("CCIP 2.0 lanes", () => {
        it("executes successfully and reports `executed: true` on SUCCESS", async () => {
            const router = await deployRouter();
            const onRamp = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
            const offRamp = await deployV2(SOURCE_SELECTOR, [onRamp]);
            const offRampAddress = await offRamp.getAddress();
            await router.addOffRamp(SOURCE_SELECTOR, offRampAddress);

            const encodedMessage = await encodeV2Message({ onRampAddress: onRamp, offRampAddress });
            const sent = {
                era: "V2",
                onRamp,
                sourceChainSelector: SOURCE_SELECTOR,
                message: { encodedMessage, receipts: [] },
            };

            const result = await routeMessage(connection, await router.getAddress(), sent);
            assert.equal(result.executed, true);
            assert.equal(result.offRamp, offRampAddress);
            assert.equal(await offRamp.executeCalled(), true);
        });

        it("points a resolver CCV at the synthetic verifier and passes the \"FORK\" verifier result", async () => {
            const router = await deployRouter();
            const onRamp = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
            const offRamp = await deployV2(SOURCE_SELECTOR, [onRamp]);
            const offRampAddress = await offRamp.getAddress();
            await router.addOffRamp(SOURCE_SELECTOR, offRampAddress);

            const resolverOwner = "0x0000000000000000000000000000000000000a11";
            const resolverFactory = await ethers.getContractFactory(
                "src/test/ccip/JsHelperOffRampMocks.sol:JsMockVersionedResolver"
            );
            const resolver = await resolverFactory.deploy(resolverOwner);
            await resolver.waitForDeployment();
            const plainCCV = "0x0000000000000000000000000000000000000cc5";
            await offRamp.setCCVsForMessage([await resolver.getAddress(), plainCCV], [], 0);

            const encodedMessage = await encodeV2Message({ onRampAddress: onRamp, offRampAddress });
            const sent = { era: "V2", onRamp, sourceChainSelector: SOURCE_SELECTOR, message: { encodedMessage, receipts: [] } };

            await routeMessage(connection, await router.getAddress(), sent);
            assert.deepEqual([...(await offRamp.lastVerifierResults())], ["0x464f524b", "0x"]);
            assert.notEqual(await resolver.inboundImplementation("0x464f524b"), ethers.ZeroAddress);
        });

        it("throws a decoded error when the OffRamp records FAILURE", async () => {
            const router = await deployRouter();
            const onRamp = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
            const offRamp = await deployV2(SOURCE_SELECTOR, [onRamp]);
            const offRampAddress = await offRamp.getAddress();
            await router.addOffRamp(SOURCE_SELECTOR, offRampAddress);
            // `NotEnoughGasForCall()` — CCIP 2.0 OffRamp (`lib/chainlink-ccip` OffRamp.sol, tag contracts-ccip-v2.0.0).
            const errIface = new ethers.Interface(["error NotEnoughGasForCall()"]);
            const returnData = errIface.encodeErrorResult("NotEnoughGasForCall", []);
            await offRamp.setExecutionResult(1, returnData); // 1 = FAILURE

            const encodedMessage = await encodeV2Message({ onRampAddress: onRamp, offRampAddress });
            const sent = {
                era: "V2",
                onRamp,
                sourceChainSelector: SOURCE_SELECTOR,
                message: { encodedMessage, receipts: [] },
            };

            await assert.rejects(routeMessage(connection, await router.getAddress(), sent), (err) => {
                assert.match(err.message, /NotEnoughGasForCall\(\)/);
                return true;
            });
        });

        it("decodes a revert of the outer `execute` call itself (not just a recorded FAILURE state)", async () => {
            const router = await deployRouter();
            const onRamp = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
            const offRamp = await deployV2(SOURCE_SELECTOR, [onRamp]);
            const offRampAddress = await offRamp.getAddress();
            await router.addOffRamp(SOURCE_SELECTOR, offRampAddress);
            // `InvalidMessageDestChainSelector(uint64)` — CCIP 2.0 OffRamp (`lib/chainlink-ccip` OffRamp.sol, tag
            // contracts-ccip-v2.0.0); the same signature the 1.6.0 OffRamp uses (verified via the gobindings-embedded
            // source, see the ABI comment in `scripts/CCIPLocalSimulatorFork.js`).
            const errIface = new ethers.Interface(["error InvalidMessageDestChainSelector(uint64 messageDestChainSelector)"]);
            const revertData = errIface.encodeErrorResult("InvalidMessageDestChainSelector", [DEST_SELECTOR]);
            await offRamp.setExecuteReverts(revertData);

            const encodedMessage = await encodeV2Message({ onRampAddress: onRamp, offRampAddress });
            const sent = { era: "V2", onRamp, sourceChainSelector: SOURCE_SELECTOR, message: { encodedMessage, receipts: [] } };

            await assert.rejects(routeMessage(connection, await router.getAddress(), sent), (err) => {
                assert.match(err.message, /InvalidMessageDestChainSelector/);
                assert.ok(err.cause);
                return true;
            });
        });

        it("decodes a getCCVsForMessage revert (e.g. finality rejection) with a clear error", async () => {
            const router = await deployRouter();
            const onRamp = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
            const offRamp = await deployV2(SOURCE_SELECTOR, [onRamp]);
            const offRampAddress = await offRamp.getAddress();
            await router.addOffRamp(SOURCE_SELECTOR, offRampAddress);
            const errIface = new ethers.Interface([
                "error InvalidRequestedFinality(bytes4 requestedFinality, bytes4 allowedFinality)",
            ]);
            const returnData = errIface.encodeErrorResult("InvalidRequestedFinality", ["0x00000001", "0x00000000"]);
            await offRamp.setGetCCVsReverts(returnData);

            const encodedMessage = await encodeV2Message({ onRampAddress: onRamp, offRampAddress });
            const sent = {
                era: "V2",
                onRamp,
                sourceChainSelector: SOURCE_SELECTOR,
                message: { encodedMessage, receipts: [] },
            };

            await assert.rejects(routeMessage(connection, await router.getAddress(), sent), (err) => {
                assert.match(err.message, /InvalidRequestedFinality/);
                return true;
            });
        });

        it("queues a NO_EXECUTION_ADDRESS message instead of executing, unless forceExecution is set", async () => {
            const router = await deployRouter();
            const onRamp = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
            const offRamp = await deployV2(SOURCE_SELECTOR, [onRamp]);
            const offRampAddress = await offRamp.getAddress();
            await router.addOffRamp(SOURCE_SELECTOR, offRampAddress);

            const encodedMessage = await encodeV2Message({ onRampAddress: onRamp, offRampAddress });
            // `routeMessage` treats `receipts[receipts.length - 2].issuer` as the executor slot: put the
            // NO_EXECUTION marker there (second-to-last), with a distinct final entry after it.
            const receipts = [
                { issuer: NO_EXECUTION_ADDRESS, destGasLimit: 0, destBytesOverhead: 0, feeTokenAmount: 0, extraArgs: "0x" },
                { issuer: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", destGasLimit: 0, destBytesOverhead: 0, feeTokenAmount: 0, extraArgs: "0x" },
            ];
            const sent = { era: "V2", onRamp, sourceChainSelector: SOURCE_SELECTOR, message: { encodedMessage, receipts } };

            const queued = await routeMessage(connection, await router.getAddress(), sent);
            assert.equal(queued.executed, false);
            assert.equal(queued.reason, "NO_EXECUTION_ADDRESS");
            assert.equal(await offRamp.executeCalled(), false);

            const forced = await routeMessage(connection, await router.getAddress(), sent, { forceExecution: true });
            assert.equal(forced.executed, true);
            assert.equal(await offRamp.executeCalled(), true);
        });

        it("prefers the OffRamp stamped in encodedMessage over the generic reverse-order lookup", async () => {
            const router = await deployRouter();
            const onRamp = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
            // Two 2.0 OffRamps both serve `onRamp` for the same source selector (a migration in progress). The
            // generic lookup walks the router's list newest-first, so it would pick `newerOffRamp`. The message is
            // stamped for `olderOffRamp`, and that is the one that must execute.
            const olderOffRamp = await deployV2(SOURCE_SELECTOR, [onRamp]);
            const newerOffRamp = await deployV2(SOURCE_SELECTOR, [onRamp]);
            const olderAddress = await olderOffRamp.getAddress();
            const newerAddress = await newerOffRamp.getAddress();
            await router.addOffRamp(SOURCE_SELECTOR, olderAddress);
            await router.addOffRamp(SOURCE_SELECTOR, newerAddress);

            const encodedMessage = await encodeV2Message({ onRampAddress: onRamp, offRampAddress: olderAddress });
            assert.equal(_stampedOffRamp(connection, encodedMessage), ethers.getAddress(olderAddress));

            const sent = { era: "V2", onRamp, sourceChainSelector: SOURCE_SELECTOR, message: { encodedMessage, receipts: [] } };
            const result = await routeMessage(connection, await router.getAddress(), sent);

            assert.equal(result.offRamp, olderAddress);
            assert.equal(await olderOffRamp.executeCalled(), true);
            assert.equal(await newerOffRamp.executeCalled(), false);
        });
    });

    describe("OffRamp lookup", () => {
        it("skips an OffRamp of unknown typeAndVersion and still resolves the correct mixed-era lane", async () => {
            const router = await deployRouter();
            const preOnRamp = "0x1111111111111111111111111111111111111111";
            const preOffRamp = await deployPreV1dot6("EVM2EVMOffRamp 1.5.0", DEST_SELECTOR, SOURCE_SELECTOR, preOnRamp);
            const v6OnRamp = "0x2222222222222222222222222222222222222222";
            const v6OffRamp = await deployV1dot6(SOURCE_SELECTOR, v6OnRamp, DEST_SELECTOR);
            const v2OnRamp = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
            const v2OffRamp = await deployV2(SOURCE_SELECTOR, [v2OnRamp]);
            const unknown = await deployUnknown();

            await router.addOffRamp(SOURCE_SELECTOR, await preOffRamp.getAddress());
            await router.addOffRamp(SOURCE_SELECTOR, await unknown.getAddress());
            await router.addOffRamp(SOURCE_SELECTOR, await v6OffRamp.getAddress());
            await router.addOffRamp(SOURCE_SELECTOR, await v2OffRamp.getAddress());
            const routerAddress = await router.getAddress();

            // pre-1.6 lane still resolves.
            await routeMessage(connection, routerAddress, {
                era: "PRE_V1_6",
                onRamp: preOnRamp,
                sourceChainSelector: SOURCE_SELECTOR,
                message: {
                    sourceChainSelector: SOURCE_SELECTOR,
                    sender: preOnRamp,
                    receiver: "0x5555555555555555555555555555555555555555",
                    sequenceNumber: 1,
                    gasLimit: 200_000n,
                    strict: false,
                    nonce: 1,
                    feeToken: ethers.ZeroAddress,
                    feeTokenAmount: 0,
                    data: "0x",
                    tokenAmounts: [],
                    sourceTokenData: [],
                    messageId: ethers.id("message-6"),
                },
            });
            assert.equal(await preOffRamp.callsWithOverridesCount(), 1n);

            // 1.6 lane still resolves.
            await routeMessage(connection, routerAddress, {
                era: "V1_6",
                onRamp: v6OnRamp,
                sourceChainSelector: SOURCE_SELECTOR,
                destChainSelector: DEST_SELECTOR,
                message: {
                    header: {
                        messageId: ethers.id("message-7"),
                        sourceChainSelector: SOURCE_SELECTOR,
                        destChainSelector: DEST_SELECTOR,
                        sequenceNumber: 1,
                        nonce: 1,
                    },
                    sender: "0x7777777777777777777777777777777777777777",
                    data: "0x",
                    receiver: "0x5555555555555555555555555555555555555555",
                    extraArgs: "0x",
                    feeToken: ethers.ZeroAddress,
                    feeTokenAmount: 0,
                    feeValueJuels: 0,
                    tokenAmounts: [],
                },
            });
            assert.equal(await v6OffRamp.callCount(), 1n);
        });
    });
});
