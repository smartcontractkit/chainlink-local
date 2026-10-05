// Fork tests for the Hardhat 3 JavaScript helper `scripts/CCIPLocalSimulatorFork.js`.
// Run with `npm run hardhat-test-js` (needs ETHEREUM_SEPOLIA_RPC_URL, ARBITRUM_SEPOLIA_RPC_URL, AVALANCHE_FUJI_RPC_URL;
// the 1.6 regression needs archive RPCs).
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { network } from "hardhat";

import {
    CCIP_V2_ROUTERS,
    getCCIPMessages,
    requestLinkFromTheFaucet,
    routeMessage,
} from "../../../scripts/CCIPLocalSimulatorFork.js";

const ROUTER_CLIENT_ABI = [
    "function getFee(uint64 destinationChainSelector, tuple(bytes receiver, bytes data, tuple(address token, uint256 amount)[] tokenAmounts, address feeToken, bytes extraArgs) message) view returns (uint256)",
    "function ccipSend(uint64 destinationChainSelector, tuple(bytes receiver, bytes data, tuple(address token, uint256 amount)[] tokenAmounts, address feeToken, bytes extraArgs) message) payable returns (bytes32)",
];
const ERC20_ABI = [
    "function approve(address spender, uint256 amount) returns (bool)",
    "function balanceOf(address account) view returns (uint256)",
    "function drip(address to)",
];
// Network details from `src/ccip/Register.sol` (deploying `Register` itself exceeds the per-transaction gas cap).
const NETWORK_DETAILS = {
    11155111: {
        chainSelector: 16015286601757825753n,
        routerAddress: "0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59",
        linkAddress: "0x779877A7B0D9E8603169DdbD7836e478b4624789",
        ccipBnMAddress: "0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05",
    },
    421614: {
        chainSelector: 3478487238524512106n,
        routerAddress: "0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165",
        linkAddress: "0xb1D4538B4571d411F07960EF2838Ce337FE1E80E",
        ccipBnMAddress: "0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D",
    },
    43113: {
        chainSelector: 14767482510784806043n,
        routerAddress: "0xF694E193200268f9a4868e4Aa017A0118C9a8177",
        linkAddress: "0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846",
        ccipBnMAddress: "0xD21341536c5cF5EB1bcb58f6723cE26e8D8E90e4",
    },
};
const WAIT_FOR_FINALITY = "0x00000000";
const EXTRA_ARGS_V2_TAG = "0x181dcf10";

async function connectFork(networkName, blockNumber) {
    const connection = await network.connect(
        blockNumber === undefined ? networkName : { network: networkName, override: { forking: { blockNumber } } }
    );
    const { chainId } = await connection.ethers.provider.getNetwork();
    const details = NETWORK_DETAILS[Number(chainId)];
    const [signer] = await connection.ethers.getSigners();
    const encoder = await (await connection.ethers.getContractFactory("src/test/ccip/utils/EncodeExtraArgsOffchain.sol:EncodeExtraArgsOffchain")).deploy();
    return { connection, details, chainId: Number(chainId), signer, encoder };
}

async function send(source, router, destChainSelector, { receiver, data = "0x", tokenAmounts = [], extraArgs }) {
    const { ethers } = source.connection;
    const routerClient = new ethers.Contract(router, ROUTER_CLIENT_ABI, source.signer);
    for (const { token, amount } of tokenAmounts) {
        await (await new ethers.Contract(token, ERC20_ABI, source.signer).approve(router, amount)).wait();
    }
    const message = {
        receiver: ethers.AbiCoder.defaultAbiCoder().encode(["address"], [receiver]),
        data,
        tokenAmounts,
        feeToken: ethers.ZeroAddress,
        extraArgs,
    };
    const fee = await routerClient.getFee(destChainSelector, message);
    const receipt = await (await routerClient.ccipSend(destChainSelector, message, { value: fee })).wait();
    const sent = getCCIPMessages(source.connection, receipt);
    assert.equal(sent.length, 1, "expected exactly one CCIP message in the receipt");
    return sent[0];
}

async function deployReceiver(destination, contractName, router) {
    return (await destination.connection.ethers.getContractFactory(contractName)).deploy(router);
}

describe("CCIPLocalSimulatorFork.js - CCIP 2.0 (Sepolia -> Arbitrum Sepolia, Register routers)", () => {
    it("routes a message and a token transfer", async () => {
        const source = await connectFork("sepoliaFork");
        const destination = await connectFork("arbitrumSepoliaFork");
        const { ethers } = source.connection;

        // Message
        const receiver = await deployReceiver(destination, "src/test/ccip/BasicMessageReceiver.sol:BasicMessageReceiver", destination.details.routerAddress);
        const payload = ethers.hexlify(ethers.toUtf8Bytes("Hello from Hardhat 3"));
        const sent = await send(source, source.details.routerAddress, destination.details.chainSelector, {
            receiver: await receiver.getAddress(),
            data: payload,
            extraArgs: await source.encoder.encodeV3Basic(200_000, WAIT_FOR_FINALITY),
        });
        assert.equal(sent.era, "V2");
        assert.equal(sent.sourceChainSelector, source.details.chainSelector);
        assert.equal(sent.destChainSelector, destination.details.chainSelector);

        const result = await routeMessage(destination.connection, destination.details.routerAddress, sent);
        assert.equal(result.executed, true);
        assert.equal(await receiver.latestMessageId(), sent.messageId);
        assert.equal(await receiver.latestMessage(), payload);
        assert.equal(await receiver.latestSender(), source.signer.address);

        // Token transfer (CCIP-BnM)
        const bob = ethers.Wallet.createRandom().address;
        const amount = ethers.parseEther("1");
        await (await new ethers.Contract(source.details.ccipBnMAddress, ERC20_ABI, source.signer).drip(source.signer.address)).wait();
        const tokenSent = await send(source, source.details.routerAddress, destination.details.chainSelector, {
            receiver: bob,
            tokenAmounts: [{ token: source.details.ccipBnMAddress, amount }],
            extraArgs: await source.encoder.encodeV3Basic(0, WAIT_FOR_FINALITY),
        });
        await routeMessage(destination.connection, destination.details.routerAddress, tokenSent);
        const destinationBnM = new destination.connection.ethers.Contract(destination.details.ccipBnMAddress, ERC20_ABI, destination.connection.ethers.provider);
        assert.equal(await destinationBnM.balanceOf(bob), amount);
    });

    it("rejects a Faster-Than-Finality message to a receiver that requires finality", async () => {
        const source = await connectFork("sepoliaFork");
        const destination = await connectFork("arbitrumSepoliaFork");
        const receiver = await deployReceiver(destination, "src/test/ccip/BasicMessageReceiver.sol:BasicMessageReceiver", destination.details.routerAddress);

        const sent = await send(source, source.details.routerAddress, destination.details.chainSelector, {
            receiver: await receiver.getAddress(),
            data: "0x1234",
            extraArgs: await source.encoder.encodeV3BasicBlockDepth(200_000, 1),
        });

        await assert.rejects(
            routeMessage(destination.connection, destination.details.routerAddress, sent),
            /cannot be executed: .*InvalidRequestedFinality\(0x00000001, 0x00000000\)/
        );
        assert.equal(await receiver.latestMessageId(), destination.connection.ethers.ZeroHash);
    });

    it("leaves NO_EXECUTION messages for manual execution", async () => {
        const source = await connectFork("sepoliaFork");
        const destination = await connectFork("arbitrumSepoliaFork");
        const receiver = await deployReceiver(destination, "src/test/ccip/BasicMessageReceiver.sol:BasicMessageReceiver", destination.details.routerAddress);

        const extraArgs = await source.encoder.encodeV3(
            200_000,
            WAIT_FOR_FINALITY,
            [],
            [],
            await source.encoder.getNoExecutionAddress(),
            "0x",
            "0x",
            "0x"
        );
        const sent = await send(source, source.details.routerAddress, destination.details.chainSelector, {
            receiver: await receiver.getAddress(),
            data: "0xabcd",
            extraArgs,
        });

        const queued = await routeMessage(destination.connection, destination.details.routerAddress, sent);
        assert.deepEqual([queued.executed, queued.reason], [false, "NO_EXECUTION_ADDRESS"]);
        assert.equal(await receiver.latestMessageId(), destination.connection.ethers.ZeroHash);

        const forced = await routeMessage(destination.connection, destination.details.routerAddress, sent, { forceExecution: true });
        assert.equal(forced.executed, true);
        assert.equal(await receiver.latestMessageId(), sent.messageId);
    });

    it("requests LINK from the faucet", async () => {
        const source = await connectFork("sepoliaFork");
        const { ethers } = source.connection;
        const to = ethers.Wallet.createRandom().address;
        await requestLinkFromTheFaucet(source.connection, source.details.linkAddress, to, ethers.parseEther("1"));
        const link = new ethers.Contract(source.details.linkAddress, ERC20_ABI, ethers.provider);
        assert.equal(await link.balanceOf(to), ethers.parseEther("1"));
    });
});

describe("CCIPLocalSimulatorFork.js - CCIP 2.0 (Sepolia -> Fuji, dedicated CCIP 2.0 routers)", () => {
    it("routes a message sent through the CCIP 2.0 router", async () => {
        const source = await connectFork("sepoliaFork");
        const destination = await connectFork("fujiFork");
        const receiver = await deployReceiver(destination, "src/test/ccip/BasicMessageReceiver.sol:BasicMessageReceiver", CCIP_V2_ROUTERS[destination.chainId]);

        const sent = await send(source, CCIP_V2_ROUTERS[source.chainId], destination.details.chainSelector, {
            receiver: await receiver.getAddress(),
            data: "0xc0ffee",
            extraArgs: await source.encoder.encodeV3Basic(200_000, WAIT_FOR_FINALITY),
        });

        // Search both routers, as a test that does not know which router the message was sent through would.
        await routeMessage(destination.connection, [destination.details.routerAddress, CCIP_V2_ROUTERS[destination.chainId]], sent);
        assert.equal(await receiver.latestMessageId(), sent.messageId);
        assert.equal(await receiver.latestMessage(), "0xc0ffee");
    });
});

describe("CCIPLocalSimulatorFork.js - CCIP 1.6 (pinned blocks, archive RPCs)", () => {
    // Sepolia -> Arbitrum Sepolia was a 1.6 lane at these blocks (OnRamp 1.6.0 0x23a5084F...); the destination router
    // lists EVM2EVMOffRamp 1.2.0 / 1.5.0 and OffRamp 1.6.0, so the mixed-era lookup is exercised too.
    it("routes a message (sender as 32-byte ABI word) and a token transfer", async () => {
        const source = await connectFork("sepoliaFork", 11_500_000);
        const destination = await connectFork("arbitrumSepoliaFork", 298_680_335);
        const { ethers } = source.connection;
        const coder = ethers.AbiCoder.defaultAbiCoder();
        const extraArgsV2 = (gasLimit) =>
            ethers.concat([EXTRA_ARGS_V2_TAG, coder.encode(["tuple(uint256 gasLimit, bool allowOutOfOrderExecution)"], [[gasLimit, true]])]);

        const receiver = await deployReceiver(destination, "src/test/ccip/BasicMessageReceiver.sol:BasicMessageReceiver", destination.details.routerAddress);
        const sent = await send(source, source.details.routerAddress, destination.details.chainSelector, {
            receiver: await receiver.getAddress(),
            data: "0x16",
            extraArgs: extraArgsV2(200_000),
        });
        assert.equal(sent.era, "V1_6");
        await routeMessage(destination.connection, destination.details.routerAddress, sent);
        assert.equal(await receiver.latestMessageId(), sent.messageId);
        // BasicMessageReceiver does `abi.decode(message.sender, (address))`, which only succeeds for the 32-byte encoding.
        assert.equal(await receiver.latestSender(), source.signer.address);

        const bob = ethers.Wallet.createRandom().address;
        const amount = ethers.parseEther("1");
        await (await new ethers.Contract(source.details.ccipBnMAddress, ERC20_ABI, source.signer).drip(source.signer.address)).wait();
        const tokenSent = await send(source, source.details.routerAddress, destination.details.chainSelector, {
            receiver: bob,
            tokenAmounts: [{ token: source.details.ccipBnMAddress, amount }],
            extraArgs: extraArgsV2(0),
        });
        await routeMessage(destination.connection, destination.details.routerAddress, tokenSent);
        const destinationBnM = new destination.connection.ethers.Contract(destination.details.ccipBnMAddress, ERC20_ABI, destination.connection.ethers.provider);
        assert.equal(await destinationBnM.balanceOf(bob), amount);
    });
});
