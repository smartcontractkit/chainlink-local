// Fully offline (no RPC, no Hardhat network) tests for `getCCIPMessages`'s log decoding, covering all three CCIP
// eras. Fixture logs are built from ABIs fetched INDEPENDENTLY of the helper's own ABI strings, so a bug that
// mirrors a wrong assumption in both places would still be caught:
//   - pre-1.6 `CCIPSendRequested` and 1.6 `CCIPMessageSent`: `git show v0.2.9:abi/EVM2EVMOnRamp.json` and
//     `v0.2.9:abi/OnRamp.json` (the 0.2.x npm package shipped these ABIs), saved as
//     `test/unit/ccip/fixtures/EVM2EVMOnRampPreV1dot6.abi.json` / `OnRampV1dot6.abi.json`.
//   - 2.0 `CCIPMessageSent`: `forge inspect lib/chainlink-ccip/.../OnRamp.sol:OnRamp abi` (tag contracts-ccip-v2.0.0),
//     saved as `OnRampV2.abi.json`. Its `encodedMessage` bytes are hand-encoded here per the documented MessageV1
//     wire format layout in `lib/chainlink-ccip/chains/evm/contracts/libraries/MessageV1Codec.sol`
//     (`_encodeMessageV1`), independently cross-checked in `CCIPLocalSimulatorForkRoutingHelper.unit.test.js` against
//     the codec's own `_encodeMessageV1` running on-chain (`MessageV1CodecTestHelper`).
// Run with `npm run js-unit-test` (part of `npm test`).
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { ethers } from "ethers";

import { getCCIPMessages } from "../../../scripts/CCIPLocalSimulatorFork.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const loadAbi = (name) => JSON.parse(readFileSync(path.join(__dirname, "fixtures", name), "utf8"));

const preV1dot6Abi = loadAbi("EVM2EVMOnRampPreV1dot6.abi.json");
const v1dot6Abi = loadAbi("OnRampV1dot6.abi.json");
const v2Abi = loadAbi("OnRampV2.abi.json");

const connection = { ethers };

/** Builds a fake `receipt.log` entry from an ABI's event and args, as `ethers.Interface.encodeEventLog` would emit it. */
function buildLog(abi, eventName, args, emitterAddress) {
    const iface = new ethers.Interface(abi);
    const fragment = iface.getEvent(eventName);
    const { data, topics } = iface.encodeEventLog(fragment, args);
    return { address: emitterAddress, topics, data };
}

/** A log from an unrelated contract/event, which `getCCIPMessages` must ignore. */
function foreignLog() {
    const iface = new ethers.Interface(["event Transfer(address indexed from, address indexed to, uint256 value)"]);
    const { data, topics } = iface.encodeEventLog(iface.getEvent("Transfer"), [
        "0x1000000000000000000000000000000000000001",
        "0x2000000000000000000000000000000000000002",
        123n,
    ]);
    return { address: "0x9000000000000000000000000000000000000009", topics, data };
}

/**
 * Hand-encodes a MessageV1 wire-format message, per `MessageV1Codec._encodeMessageV1`'s documented layout
 * (`lib/chainlink-ccip/chains/evm/contracts/libraries/MessageV1Codec.sol`). No token transfer, for brevity.
 */
function encodeMessageV1({
    sourceChainSelector,
    destChainSelector,
    messageNumber,
    executionGasLimit,
    ccipReceiveGasLimit,
    finality,
    ccvAndExecutorHash,
    onRampAddress,
    offRampAddress,
    sender,
    receiver,
    destBlob,
    data,
}) {
    return ethers.solidityPacked(
        [
            "uint8",
            "uint64",
            "uint64",
            "uint64",
            "uint32",
            "uint32",
            "bytes4",
            "bytes32",
            "uint8",
            "bytes",
            "uint8",
            "bytes",
            "uint8",
            "bytes",
            "uint8",
            "bytes",
            "uint16",
            "bytes",
            "uint16",
            "bytes",
            "uint16",
            "bytes",
        ],
        [
            1,
            sourceChainSelector,
            destChainSelector,
            messageNumber,
            executionGasLimit,
            ccipReceiveGasLimit,
            finality,
            ccvAndExecutorHash,
            ethers.getBytes(onRampAddress).length,
            onRampAddress,
            ethers.getBytes(offRampAddress).length,
            offRampAddress,
            ethers.getBytes(sender).length,
            sender,
            ethers.getBytes(receiver).length,
            receiver,
            ethers.getBytes(destBlob).length,
            destBlob,
            0,
            "0x",
            ethers.getBytes(data).length,
            data,
        ]
    );
}

describe("getCCIPMessages: pre-1.6 (CCIPSendRequested)", () => {
    it("decodes era, onRamp, messageId, sourceChainSelector and the full EVM2EVMMessage payload", () => {
        const onRamp = "0x1111111111111111111111111111111111111111";
        const message = {
            sourceChainSelector: 16015286601757825753n,
            sender: "0x2222222222222222222222222222222222222222",
            receiver: "0x3333333333333333333333333333333333333333",
            sequenceNumber: 5n,
            gasLimit: 200000n,
            strict: false,
            nonce: 1n,
            feeToken: "0x4444444444444444444444444444444444444444",
            feeTokenAmount: 1000n,
            data: "0xdeadbeef",
            tokenAmounts: [["0x5555555555555555555555555555555555555555", 42n]],
            sourceTokenData: ["0x01", "0x02"],
            messageId: ethers.id("pre-1.6-message"),
        };
        const log = buildLog(preV1dot6Abi, "CCIPSendRequested", [message], onRamp);

        const [sent] = getCCIPMessages(connection, { logs: [foreignLog(), log] });

        assert.equal(sent.era, "PRE_V1_6");
        assert.equal(sent.onRamp, onRamp);
        assert.equal(sent.messageId, message.messageId);
        assert.equal(sent.sourceChainSelector, message.sourceChainSelector);
        assert.equal(sent.destChainSelector, undefined);
        assert.equal(sent.message.sender, message.sender);
        assert.equal(sent.message.receiver, message.receiver);
        assert.equal(sent.message.data, message.data);
        assert.deepEqual(sent.message.tokenAmounts, [{ token: message.tokenAmounts[0][0], amount: 42n }]);
        assert.deepEqual(sent.message.sourceTokenData, ["0x01", "0x02"]);
    });
});

describe("getCCIPMessages: 1.6 (CCIPMessageSent)", () => {
    it("decodes era, onRamp, messageId, source/destChainSelector and the full EVM2AnyRampMessage payload", () => {
        const onRamp = "0x6666666666666666666666666666666666666666";
        const header = {
            messageId: ethers.id("v1.6-message"),
            sourceChainSelector: 16015286601757825753n,
            destChainSelector: 3478487238524512106n,
            sequenceNumber: 9n,
            nonce: 2n,
        };
        const message = {
            header,
            sender: "0x7777777777777777777777777777777777777777",
            data: "0xcafe",
            receiver: "0x88888888888888888888888888888888888888888888888888888888888888",
            extraArgs: "0x97a657c9",
            feeToken: "0x9999999999999999999999999999999999999999",
            feeTokenAmount: 500n,
            feeValueJuels: 600n,
            tokenAmounts: [
                ["0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "0xbbbb", "0x", 1n, "0x0000007b"],
            ],
        };
        const log = buildLog(v1dot6Abi, "CCIPMessageSent", [header.destChainSelector, header.sequenceNumber, message], onRamp);

        const [sent] = getCCIPMessages(connection, { logs: [log] });

        assert.equal(sent.era, "V1_6");
        assert.equal(sent.onRamp, onRamp);
        assert.equal(sent.messageId, header.messageId);
        assert.equal(sent.sourceChainSelector, header.sourceChainSelector);
        assert.equal(sent.destChainSelector, header.destChainSelector);
        assert.deepEqual(sent.message.header, {
            messageId: header.messageId,
            sourceChainSelector: header.sourceChainSelector,
            destChainSelector: header.destChainSelector,
            sequenceNumber: header.sequenceNumber,
            nonce: header.nonce,
        });
        assert.equal(sent.message.sender, message.sender);
        assert.equal(sent.message.extraArgs, message.extraArgs);
        assert.deepEqual(sent.message.tokenAmounts, [
            {
                sourcePoolAddress: ethers.getAddress(message.tokenAmounts[0][0]),
                destTokenAddress: message.tokenAmounts[0][1],
                extraData: message.tokenAmounts[0][2],
                amount: message.tokenAmounts[0][3],
                destExecData: message.tokenAmounts[0][4],
            },
        ]);
    });
});

describe("getCCIPMessages: CCIP 2.0 (CCIPMessageSent, MessageV1)", () => {
    it("decodes era, onRamp, messageId and source/destChainSelector from the encodedMessage wire format", () => {
        const onRamp = "0xcccccccccccccccccccccccccccccccccccccccc";
        const sourceChainSelector = 16015286601757825753n;
        const destChainSelector = 3478487238524512106n;
        const encodedMessage = encodeMessageV1({
            sourceChainSelector,
            destChainSelector,
            messageNumber: 3n,
            executionGasLimit: 200000,
            ccipReceiveGasLimit: 100000,
            finality: "0x00000000",
            ccvAndExecutorHash: ethers.ZeroHash,
            onRampAddress: ethers.AbiCoder.defaultAbiCoder().encode(["address"], [onRamp]),
            offRampAddress: "0xdddddddddddddddddddddddddddddddddddddddd",
            sender: ethers.AbiCoder.defaultAbiCoder().encode(["address"], ["0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"]),
            receiver: "0xffffffffffffffffffffffffffffffffffffffff",
            destBlob: "0x",
            data: "0xf00d",
        });
        const messageId = ethers.keccak256(encodedMessage);
        const receipts = [
            {
                issuer: "0x1234567890123456789012345678901234567890",
                destGasLimit: 200000,
                destBytesOverhead: 0,
                feeTokenAmount: 10n,
                extraArgs: "0x",
            },
        ];
        const log = buildLog(
            v2Abi,
            "CCIPMessageSent",
            [
                destChainSelector,
                "0x1111111111111111111111111111111111111111",
                messageId,
                "0x2222222222222222222222222222222222222222",
                777n,
                encodedMessage,
                receipts,
                [],
            ],
            onRamp
        );

        const [sent] = getCCIPMessages(connection, { logs: [log] });

        assert.equal(sent.era, "V2");
        assert.equal(sent.onRamp, onRamp);
        assert.equal(sent.messageId, messageId);
        assert.equal(sent.sourceChainSelector, sourceChainSelector);
        assert.equal(sent.destChainSelector, destChainSelector);
        assert.equal(sent.message.encodedMessage, encodedMessage);
        assert.deepEqual(sent.message.receipts, [
            {
                issuer: receipts[0].issuer,
                destGasLimit: BigInt(receipts[0].destGasLimit),
                destBytesOverhead: BigInt(receipts[0].destBytesOverhead),
                feeTokenAmount: receipts[0].feeTokenAmount,
                extraArgs: receipts[0].extraArgs,
            },
        ]);
    });
});

describe("getCCIPMessages: multi-message / mixed-era receipts", () => {
    it("returns every recognised message, in log order, ignoring logs from other contracts and unrelated events", () => {
        const preOnRamp = "0x1010101010101010101010101010101010101010";
        const v6OnRamp = "0x2020202020202020202020202020202020202020";

        const preMessage = {
            sourceChainSelector: 1n,
            sender: "0x000000000000000000000000000000000000000a",
            receiver: "0x000000000000000000000000000000000000000b",
            sequenceNumber: 1n,
            gasLimit: 1n,
            strict: false,
            nonce: 1n,
            feeToken: "0x000000000000000000000000000000000000000c",
            feeTokenAmount: 1n,
            data: "0x",
            tokenAmounts: [],
            sourceTokenData: [],
            messageId: ethers.id("multi-pre"),
        };
        const header = {
            messageId: ethers.id("multi-v1.6"),
            sourceChainSelector: 2n,
            destChainSelector: 3n,
            sequenceNumber: 1n,
            nonce: 1n,
        };
        const v6Message = {
            header,
            sender: "0x000000000000000000000000000000000000000d",
            data: "0x",
            receiver: "0x000000000000000000000000000000000000000e",
            extraArgs: "0x",
            feeToken: "0x000000000000000000000000000000000000000f",
            feeTokenAmount: 0n,
            feeValueJuels: 0n,
            tokenAmounts: [],
        };

        const logs = [
            foreignLog(),
            buildLog(preV1dot6Abi, "CCIPSendRequested", [preMessage], preOnRamp),
            foreignLog(),
            buildLog(v1dot6Abi, "CCIPMessageSent", [header.destChainSelector, header.sequenceNumber, v6Message], v6OnRamp),
        ];

        const sent = getCCIPMessages(connection, { logs });

        assert.equal(sent.length, 2);
        assert.equal(sent[0].era, "PRE_V1_6");
        assert.equal(sent[0].messageId, preMessage.messageId);
        assert.equal(sent[1].era, "V1_6");
        assert.equal(sent[1].messageId, header.messageId);
    });

    it("returns an empty array when a receipt has no CCIP logs", () => {
        assert.deepEqual(getCCIPMessages(connection, { logs: [foreignLog()] }), []);
        assert.deepEqual(getCCIPMessages(connection, { logs: [] }), []);
    });
});
