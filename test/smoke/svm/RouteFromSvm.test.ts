// Journey 5: messages sent from Solana are executed on the EVM side through CCIPLocalSvmLane (`routeFromSvm`), and
// `routeAll` runs both directions until nothing is pending (CCIP 2.0 and 1.6).
import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import anchor from "@anchor-lang/core";
import { Keypair, LAMPORTS_PER_SOL, PublicKey, SystemProgram, Transaction } from "@solana/web3.js";
import { network } from "hardhat";
import {
  exampleReceiver,
  routeAll,
  routeFromSvm,
  routeToSvm,
  startSvmLocal,
  svmExtraArgs,
  type BurnMintToken,
  type CcipVersion,
  type RouteResult,
  type SvmLocal,
} from "../../../scripts/svm/index.ts";

const { AnchorProvider, Program, Wallet } = anchor;
const SOLANA_SELECTOR = 16423721717087811551n;
const FEE = 10n ** 16n;
const VERSIONS: CcipVersion[] = ["2.0", "1.6"];
// `CCIPLocalRouter.SvmLaneVersion` by CCIP version.
const LANE_VERSION = { "2.0": 0, "1.6": 1 } as const;
const ONE_TOKEN = 10n ** 18n; // CCIP-BnM has 18 decimals; the Solana mint has 9
const NO_RECEIVER = new Uint8Array(32);
const SUCCESS = 2n; // Internal.MessageExecutionState.SUCCESS
const FAILURE = 3n;
const UNTOUCHED = 0n;
const fileStart = performance.now();

for (const ccipVersion of VERSIONS) {
  const receiver = await exampleReceiver({ ccipVersion });
  // Timing lines carry the lane version as a suffix: `[svm-timing] journey-5 ping-pong@1.6 41ms`.
  async function timed<T>(step: string, work: () => Promise<T>): Promise<T> {
    const start = performance.now();
    const value = await work();
    console.log(`[svm-timing] ${step}@${ccipVersion} ${Math.round(performance.now() - start)}ms`);
    return value;
  }

  describe(`CCIP ${ccipVersion}: messages from Solana reach EVM contracts`, () => {
    const receiverId = receiver.programId;
    const counter = PublicKey.findProgramAddressSync([Buffer.from("counter")], receiverId)[0];
    const externalExecutionConfig = PublicKey.findProgramAddressSync([Buffer.from("external_execution_config")], receiverId)[0];
    const accounts = [externalExecutionConfig, counter, SystemProgram.programId];
    const wallet = Keypair.generate();

    /* eslint-disable @typescript-eslint/no-explicit-any */
    let ethers: any, router: any, lane: any, bnm: any, tokenSender: any, evmReceiver: any, pingPong: any;
    /* eslint-enable @typescript-eslint/no-explicit-any */
    let svm: SvmLocal, mint: BurnMintToken;

    const readCounter = async () => (await svm.connection.getAccountInfo(counter))!.data.readBigUInt64LE(8);
    const fund = async (key: PublicKey) => {
      await svm.connection.confirmTransaction(await svm.connection.requestAirdrop(key, 10 * LAMPORTS_PER_SOL), "confirmed");
    };
    const newestRouterSignature = async () => (await svm.connection.getSignaturesForAddress(svm.ccip.router, { limit: 1 }, "confirmed"))[0].signature;
    const encodeCount = (count: bigint) => ethers.AbiCoder.defaultAbiCoder().encode(["uint256"], [count]);

    before(async () => {
      ({ ethers } = await network.connect());
      const simulator = await ethers.deployContract("CCIPLocalSimulator");
      const [, sourceRouter, , , linkToken, ccipBnM] = await simulator.configuration();
      router = await ethers.getContractAt("CCIPLocalRouter", sourceRouter);
      lane = await ethers.deployContract("CCIPLocalSvmLane", [router]);
      await router.setSvmLane(lane);
      await router.setSvmLaneVersion(LANE_VERSION[ccipVersion]);
      await router.setFee(FEE);
      bnm = await ethers.getContractAt("BurnMintERC677Helper", ccipBnM);
      tokenSender = await ethers.deployContract("SvmMessageSender", [sourceRouter, linkToken]);
      evmReceiver = await ethers.deployContract("SvmMessageReceiver", [sourceRouter]);
      pingPong = await ethers.deployContract("SvmPingPong", [sourceRouter, SOLANA_SELECTOR]);

      const [funder] = await ethers.getSigners();
      await funder.sendTransaction({ to: tokenSender, value: ethers.parseEther("1") });
      await funder.sendTransaction({ to: pingPong, value: ethers.parseEther("1") });
      for (let i = 0; i < 5; i++) await bnm.drip(tokenSender);

      svm = await timed("startSvmLocal", () => startSvmLocal({ ccipVersion }));
      mint = await svm.createBurnMintToken();
      await svm.linkToken(mint, { evmToken: await bnm.getAddress() });
      await svm.deployProgram(receiver.programPath, receiverId);
      const provider = new AnchorProvider(svm.connection, new Wallet(svm.payer), { commitment: "confirmed" });
      const initialize = await new Program(receiver.idl as never, provider).methods
        .initialize(svm.ccip.router)
        .accounts({ counter, externalExecutionConfig, authority: svm.payer.publicKey, systemProgram: SystemProgram.programId })
        .instruction();
      await svm.sendAndConfirm(new Transaction().add(initialize));
      await fund(wallet.publicKey);
    });

    after(() => {
      svm?.stop();
      console.log(`[svm-timing] RouteFromSvm file@${ccipVersion} ${Math.round(performance.now() - fileStart)}ms`);
    });

    it("delivers a wallet's data to a Solidity receiver, with the 32-byte Solana sender", async () => {
      const sent = await svm.send({ sender: wallet, receiver: await evmReceiver.getAddress(), data: Buffer.from("hello evm"), gasLimit: 500_000n });
      const [result] = await timed("journey-5 data-to-evm", () => routeFromSvm(svm, lane, sent));

      assert.equal(result.state, "Success", result.error);
      assert.equal(result.messageId, sent.messageId);
      assert.match(result.evmTransactionHash, /^0x[0-9a-f]{64}$/);
      assert.equal(await evmReceiver.messageCount(), 1n);
      assert.equal(await evmReceiver.latestSourceChainSelector(), SOLANA_SELECTOR);
      assert.equal(await evmReceiver.latestMessageId(), sent.messageId);
      assert.equal(await evmReceiver.latestSender(), ethers.hexlify(wallet.publicKey.toBytes()));
      assert.equal(ethers.toUtf8String(await evmReceiver.latestData()), "hello evm");
      assert.equal((await evmReceiver.latestTokenAmounts()).length, 0);
      assert.equal(await lane.getExecutionState(sent.messageId), SUCCESS);
    });

    it("routes a message by the signature of its Solana transaction, and several messages in order", async () => {
      const first = await svm.send({ sender: wallet, receiver: await evmReceiver.getAddress(), data: Buffer.from("one"), gasLimit: 500_000n });
      const [bySignature] = await routeFromSvm(svm, lane, first.signature);
      assert.equal(bySignature.state, "Success", bySignature.error);
      assert.equal(bySignature.messageId, first.messageId);

      const two = [
        await svm.send({ sender: wallet, receiver: await evmReceiver.getAddress(), data: Buffer.from("two"), gasLimit: 500_000n }),
        await svm.send({ sender: wallet, receiver: await evmReceiver.getAddress(), data: Buffer.from("three"), gasLimit: 500_000n }),
      ];
      const results = await routeFromSvm(svm, lane, two);
      assert.deepEqual(results.map((r) => r.state), ["Success", "Success"]);
      assert.deepEqual(results.map((r) => r.messageId), two.map((m) => m.messageId));
      assert.equal(ethers.toUtf8String(await evmReceiver.latestData()), "three");
    });

    it("sends a token to Solana and back: the lane escrows it, and 9 -> 18 decimals scaling releases it", async () => {
      await svm.createTokenAccount(mint.mint, wallet.publicKey); // required on 1.6, harmless on 2.0
      const extraArgs = svmExtraArgs({ computeUnits: 0, accounts: [], writableBitmap: 0n, tokenReceiver: wallet.publicKey });
      const evmReceiverAddress = await evmReceiver.getAddress();
      const escrowBefore = await bnm.balanceOf(lane);
      const receiverBefore = await bnm.balanceOf(evmReceiverAddress);
      const supplyBefore = BigInt((await svm.connection.getTokenSupply(mint.mint)).value.amount);

      // EVM -> Solana: 2 tokens go into the lane's escrow and 2e9 are minted to the wallet.
      const receipt = await (
        await tokenSender.sendToken(SOLANA_SELECTOR, NO_RECEIVER, "0x", extraArgs, ethers.ZeroAddress, bnm, 2n * ONE_TOKEN)
      ).wait();
      const [delivered] = await routeToSvm(svm, receipt);
      assert.equal(delivered.state, "Success", delivered.error);
      assert.equal((await bnm.balanceOf(lane)) - escrowBefore, 2n * ONE_TOKEN);
      assert.equal(await svm.tokenBalance(mint.mint, wallet.publicKey), 2_000_000_000n);

      // Solana -> EVM: 1.5e9 burned on Solana release 1.5e18 from the escrow, with the data.
      const sent = await svm.send({
        sender: wallet,
        receiver: evmReceiverAddress,
        data: Buffer.from("back"),
        gasLimit: 500_000n,
        token: { mint: mint.mint, amount: 1_500_000_000n },
      });
      const [result] = await timed("journey-5 token-to-evm", () => routeFromSvm(svm, lane, sent));
      assert.equal(result.state, "Success", result.error);
      assert.equal(await svm.tokenBalance(mint.mint, wallet.publicKey), 500_000_000n);
      assert.equal(BigInt((await svm.connection.getTokenSupply(mint.mint)).value.amount), supplyBefore + 500_000_000n);
      assert.equal((await bnm.balanceOf(evmReceiverAddress)) - receiverBefore, 1_500_000_000_000_000_000n);
      assert.equal((await bnm.balanceOf(lane)) - escrowBefore, ONE_TOKEN / 2n, "the lane keeps what is still on Solana");
      const [tokenAmount, ...rest] = await evmReceiver.latestTokenAmounts();
      assert.equal(rest.length, 0);
      assert.equal(tokenAmount.token, await bnm.getAddress());
      assert.equal(tokenAmount.amount, 1_500_000_000_000_000_000n);
      assert.equal(ethers.toUtf8String(await evmReceiver.latestData()), "back");
    });

    it("returns Failure when the receiver reverts, and Success when routed again after the receiver is fixed", async () => {
      const countBefore = await evmReceiver.messageCount();
      await evmReceiver.setShouldRevert(true);
      const sent = await svm.send({ sender: wallet, receiver: await evmReceiver.getAddress(), data: Buffer.from("retry me"), gasLimit: 500_000n });

      const [failed] = await routeFromSvm(svm, lane, sent);
      console.log(`[svm-result] receiver revert@${ccipVersion}: ${failed.state}, ${failed.error}`);
      assert.equal(failed.state, "Failure");
      assert.match(failed.error ?? "", /SvmMessageReceiver: told to revert/);
      assert.equal(await evmReceiver.messageCount(), countBefore);
      assert.equal(await lane.getExecutionState(sent.messageId), FAILURE);

      // A retry that fails again reverts, as the OffRamp does.
      await assert.rejects(routeFromSvm(svm, lane, sent), ccipVersion === "2.0" ? /NoStateProgressMade/ : /ExecutionError/);

      await evmReceiver.setShouldRevert(false);
      const [retried] = await routeFromSvm(svm, lane, sent);
      assert.equal(retried.state, "Success", retried.error);
      assert.equal(retried.error, undefined);
      assert.equal(await evmReceiver.messageCount(), countBefore + 1n);
      assert.equal(await lane.getExecutionState(sent.messageId), SUCCESS);
    });

    it("returns Failure for a token the escrow cannot cover, and rolls the attempt back", async () => {
      // Solana minted these without any EVM tokens going into the lane, so the lane holds less than the message releases.
      await svm.mintTokens(mint.mint, wallet.publicKey, 100_000_000_000n);
      const escrow = await bnm.balanceOf(lane);
      const sent = await svm.send({ sender: wallet, receiver: await evmReceiver.getAddress(), token: { mint: mint.mint, amount: 100_000_000_000n } });
      const [result] = await routeFromSvm(svm, lane, sent);
      console.log(`[svm-result] empty escrow@${ccipVersion}: ${result.error}`);
      assert.equal(result.state, "Failure");
      assert.match(result.error ?? "", /^InsufficientEscrow\(/);
      assert.equal(await bnm.balanceOf(lane), escrow);
    });

    it("throws when a message is routed again after it succeeded", async () => {
      const sent = await svm.send({ sender: wallet, receiver: await evmReceiver.getAddress(), data: Buffer.from("once"), gasLimit: 500_000n });
      const [first] = await routeFromSvm(svm, lane, sent);
      assert.equal(first.state, "Success", first.error);
      await assert.rejects(routeFromSvm(svm, lane, sent), /SkippedAlreadyExecutedMessage/);
    });

    it("throws for misuse, and executes nothing when any message is invalid", async () => {
      const good = await svm.send({ sender: wallet, receiver: await evmReceiver.getAddress(), data: Buffer.from("good"), gasLimit: 500_000n });
      const elsewhere = { ...good, messageId: "0x" + "ab".repeat(32), destChainSelector: 12345n };
      await assert.rejects(routeFromSvm(svm, lane, [good, elsewhere]), /chain selector 12345.*local EVM chain/);
      assert.equal(await lane.getExecutionState(good.messageId), UNTOUCHED, "the valid message was not executed");

      const noMessages = await svm.sendAndConfirm(new Transaction().add(SystemProgram.transfer({ fromPubkey: svm.payer.publicKey, toPubkey: wallet.publicKey, lamports: 1 })));
      await assert.rejects(routeFromSvm(svm, lane, noMessages), /no message to route/);
      await assert.rejects(routeFromSvm(svm, lane, []), /no message to route/);
      await assert.rejects(routeFromSvm(svm, lane.connect(null), good), /connected to a signer/);
      assert.equal(await lane.getExecutionState(good.messageId), UNTOUCHED);
    });

    it("throws when the router and the Solana side run different CCIP versions", async () => {
      const other = ccipVersion === "2.0" ? "1.6" : "2.0";
      const sent = await svm.send({ sender: wallet, receiver: await evmReceiver.getAddress(), data: Buffer.from("mismatch"), gasLimit: 500_000n });
      await router.setSvmLaneVersion(LANE_VERSION[other]);
      try {
        await assert.rejects(routeFromSvm(svm, lane, sent), new RegExp(`executes this message with CCIP ${other} rules, but the local Solana side runs CCIP ${ccipVersion}`));
        await assert.rejects(routeAll(svm, { lane, fromBlock: 0 }), /executes this message with CCIP/);
      } finally {
        await router.setSvmLaneVersion(LANE_VERSION[ccipVersion]);
      }
      assert.equal(await lane.getExecutionState(sent.messageId), UNTOUCHED);
    });

    /**
     * Configures the EVM ping-pong, and returns a hook that plays the Solana side: no Solana program can reply (the
     * 1.6 `ping_pong_demo` needs 20 receiver accounts and the OffRamp runs out of heap above 14), so the wallet
     * sends `count + 1` back for every count that reached Solana.
     */
    async function startPingPong(maxCount: bigint) {
      await pingPong.configure(receiverId.toBytes(), maxCount, 200_000, 0b11, accounts.map((key) => key.toBytes()));
      const hook = async (result: RouteResult) => {
        const [ping] = await pingPong.queryFilter(pingPong.filters.PingSent(result.evmMessageId));
        await svm.send({
          sender: wallet,
          receiver: await pingPong.getAddress(),
          data: Buffer.from(encodeCount(ping.args.count + 1n).slice(2), "hex"),
          gasLimit: 1_000_000n,
        });
      };
      const afterSignature = await newestRouterSignature();
      const receipt = await (await pingPong.start(0)).wait();
      return { hook, afterSignature, fromBlock: receipt.blockNumber as number };
    }

    it("routes a ping-pong both ways with routeAll until the count is reached", async () => {
      const countersBefore = await readCounter();
      const receivedBefore = await pingPong.receivedCount();
      const { hook, afterSignature, fromBlock } = await startPingPong(4n);

      const { deliveries, complete } = await timed("journey-5 ping-pong", () =>
        routeAll(svm, { lane, fromBlock, afterSignature, onSolanaDelivery: hook }),
      );

      // EVM sends 0, 2, 4 to Solana; Solana answers 1, 3, 5; 5 >= 4 ends it.
      assert.equal(complete, true);
      assert.deepEqual(
        deliveries.map((d) => d.direction),
        ["evm-to-solana", "solana-to-evm", "evm-to-solana", "solana-to-evm", "evm-to-solana", "solana-to-evm"],
      );
      for (const delivery of deliveries) assert.equal(delivery.result.state, "Success", delivery.result.error);
      assert.equal(await pingPong.lastCount(), 5n);
      assert.equal((await pingPong.receivedCount()) - receivedBefore, 3n);
      assert.equal((await readCounter()) - countersBefore, 3n, "the receiver program ran for every EVM -> Solana leg");
      // Routing again from the current positions finds nothing: every message was delivered.
      const idle = await routeAll(svm, { lane, fromBlock: (await ethers.provider.getBlockNumber()) + 1, afterSignature: await newestRouterSignature() });
      assert.deepEqual(idle, { deliveries: [], complete: true });
    });

    it("does not deliver again what routeToSvm, routeFromSvm or an earlier routeAll already delivered", async () => {
      // Everything since the start of this file: the token test's EVM -> Solana message went through routeToSvm, the
      // ping-pong's through routeAll, and most Solana messages through routeFromSvm. Only the ones never routed
      // (left UNTOUCHED on purpose by the misuse and version tests) may be delivered now.
      const untouched: string[] = [];
      for (const message of await svm.sentMessages()) {
        if ((await lane.getExecutionState(message.messageId)) === UNTOUCHED) untouched.push(message.messageId);
      }
      const countersBefore = await readCounter();

      const { deliveries, complete } = await routeAll(svm, { lane, fromBlock: 0 });

      assert.equal(complete, true);
      assert.equal(deliveries.filter((d) => d.direction === "evm-to-solana").length, 0, "no EVM -> Solana message twice");
      assert.equal(await readCounter(), countersBefore);
      const toEvm = deliveries.filter((d) => d.direction === "solana-to-evm");
      assert.deepEqual(toEvm.map((d) => d.message.messageId).sort(), untouched.sort());
      for (const delivery of toEvm) assert.equal(delivery.result.state, "Success", delivery.result.error);
    });

    it("stops a never-ending ping-pong at maxMessages and says so", async () => {
      const { hook, afterSignature, fromBlock } = await startPingPong(1_000_000n);

      const { deliveries, complete } = await routeAll(svm, { lane, fromBlock, afterSignature, maxMessages: 4, onSolanaDelivery: hook });

      assert.equal(complete, false);
      assert.equal(deliveries.length, 4);
      assert.deepEqual(
        deliveries.map((d) => d.direction),
        ["evm-to-solana", "solana-to-evm", "evm-to-solana", "solana-to-evm"],
      );
      assert.equal(await pingPong.lastCount(), 3n);
      await assert.rejects(routeAll(svm, { lane, fromBlock, maxMessages: 0 }), /maxMessages must be a positive integer/);
    });
  });
}
