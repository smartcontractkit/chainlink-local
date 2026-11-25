// Journey 2: a Solidity contract sends a CCIP message to a Solana program, delivered through the real
// CCIP 2.0 and 1.6 Solana programs running in a local Surfnet.
import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import anchor from "@anchor-lang/core";
import { PublicKey, SystemProgram, Transaction } from "@solana/web3.js";
import { network } from "hardhat";
import { exampleReceiver, routeToSvm, startSvmLocal, svmExtraArgs, type CcipVersion, type SvmLocal } from "../../../scripts/svm/index.ts";

const { AnchorProvider, Program, Wallet } = anchor;
const SOLANA_SELECTOR = 16423721717087811551n;
const LOCAL_EVM_SELECTOR = 16015286601757825753n;
const FEE = 10n ** 16n;
const VERSIONS: CcipVersion[] = ["2.0", "1.6"];
// `CCIPLocalRouter.SvmLaneVersion` by CCIP version.
const LANE_VERSION = { "2.0": 0, "1.6": 1 } as const;
const fileStart = performance.now();

for (const ccipVersion of VERSIONS) {
  const receiver = await exampleReceiver({ ccipVersion });
  // Timing lines carry the lane version as a suffix: `[svm-timing] journey-2 send-to-result@1.6 41ms`.
  async function timed<T>(step: string, work: () => Promise<T>): Promise<T> {
    const start = performance.now();
    const value = await work();
    console.log(`[svm-timing] ${step}@${ccipVersion} ${Math.round(performance.now() - start)}ms`);
    return value;
  }

  describe(`CCIP ${ccipVersion}: a Solidity contract sends a CCIP message to a Solana program`, () => {
    const receiverId = receiver.programId;
    const counter = PublicKey.findProgramAddressSync([Buffer.from("counter")], receiverId)[0];
    const externalExecutionConfig = PublicKey.findProgramAddressSync([Buffer.from("external_execution_config")], receiverId)[0];
    const accounts = [externalExecutionConfig, counter, SystemProgram.programId];

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let ethers: any, router: any, link: any, sender: any, svm: SvmLocal;

    const readCounter = async () => (await svm.connection.getAccountInfo(counter))!.data.readBigUInt64LE(8);

    /** Sends `"hello"` to the receiver program from the Solidity sender, and returns the receipt and the id `send` returned. */
    async function send(extraArgs: string, feeToken = ethers.ZeroAddress) {
      const tx = await sender.send(SOLANA_SELECTOR, receiverId.toBytes(), ethers.toUtf8Bytes("hello"), extraArgs, feeToken);
      const receipt = await tx.wait();
      const [sent] = receipt.logs.flatMap((log: unknown) => {
        const parsed = sender.interface.parseLog(log);
        return parsed?.name === "MessageSent" ? [parsed] : [];
      });
      return { receipt, messageId: sent.args.messageId as string };
    }

    before(async () => {
      const connection = await network.connect();
      ({ ethers } = connection);
      const simulator = await ethers.deployContract("CCIPLocalSimulator");
      const [, sourceRouter, , , linkToken] = await simulator.configuration();
      router = await ethers.getContractAt("CCIPLocalRouter", sourceRouter);
      // Solana sends need the lane contract, which is not built into the simulator.
      await router.setSvmLane(await ethers.deployContract("CCIPLocalSvmLane", [router]));
      link = await ethers.getContractAt("LinkToken", linkToken);
      sender = await ethers.deployContract("SvmMessageSender", [sourceRouter, linkToken]);

      // Fees are zero until set; give the sender native and LINK balances to pay them with.
      await router.setFee(FEE);
      const [funder] = await ethers.getSigners();
      await funder.sendTransaction({ to: sender, value: ethers.parseEther("1") });
      await simulator.requestLinkFromFaucet(sender, ethers.parseEther("1"));

      // The router applies the send rules of the lane version it is set to; the default is 2.0.
      await router.setSvmLaneVersion(LANE_VERSION[ccipVersion]);

      svm = await timed("startSvmLocal", () => startSvmLocal({ ccipVersion }));
      await svm.deployProgram(receiver.programPath, receiverId);
      const receiverProgram = new Program(
        receiver.idl as never,
        new AnchorProvider(svm.connection, new Wallet(svm.payer), { commitment: "confirmed" }),
      );
      const initialize = await receiverProgram.methods
        .initialize(svm.ccip.router)
        .accounts({ counter, externalExecutionConfig, authority: svm.payer.publicKey, systemProgram: SystemProgram.programId })
        .instruction();
      await svm.sendAndConfirm(new Transaction().add(initialize));
    });

    after(() => {
      svm?.stop();
      console.log(`[svm-timing] MessageToSolana file@${ccipVersion} ${Math.round(performance.now() - fileStart)}ms`);
    });

    it("delivers a message to the receiver program", async () => {
      const start = performance.now();
      const extraArgs = svmExtraArgs({ computeUnits: 200_000, accounts, writableBitmap: 0b11n });
      const { receipt, messageId } = await send(extraArgs);
      const [result] = await routeToSvm(svm, receipt);
      console.log(`[svm-timing] journey-2 send-to-result@${ccipVersion} ${Math.round(performance.now() - start)}ms`);

      assert.equal(result.state, "Success", result.error);
      assert.equal(result.evmMessageId, messageId);
      assert.notEqual(result.messageId, messageId, "the Solana message id is computed differently");
      assert.equal(await readCounter(), 1n);

      // The router that emitted the event is now the one onRamp the OffRamp accepts for the EVM source chain.
      // The account layout read here is the 2.0 OffRamp's; on 1.6 the next test shows the lane's onRamp check.
      if (ccipVersion !== "2.0") return;
      const sourceChain = PublicKey.findProgramAddressSync(
        [Buffer.from("source_chain_state"), Buffer.from(LOCAL_EVM_SELECTOR.toString(16).padStart(16, "0"), "hex").reverse()],
        svm.ccip.offRamp,
      )[0];
      const config = (await svm.connection.getAccountInfo(sourceChain))!.data;
      assert.ok(config.includes(Buffer.from(ethers.getBytes(await router.getAddress()))), "router is not the OffRamp's onRamp");
      assert.ok(!config.includes(Buffer.alloc(20, 1)), "the startup placeholder onRamp is still accepted");
    });

    it("accepts only the router as onRamp, as a live lane does", async () => {
      const direct = { receiverProgram: receiverId, receiverAccounts: accounts, receiverWritableBitmap: 0b11n, data: "direct" };
      const before = await readCounter();
      // deliver() without an onRamp carries the lane's onRamp, so it mixes with routed messages.
      const fromLane = await svm.deliver(direct);
      assert.equal(fromLane.state, "Success", fromLane.error);
      assert.equal(await readCounter(), before + 1n);

      // A message from any other onRamp runs, and the real OffRamp rejects it.
      const fromElsewhere = await svm.deliver({ ...direct, onRampAddress: new Uint8Array(20).fill(7) });
      console.log(`[svm-result] foreign onRamp: ${fromElsewhere.state}${fromElsewhere.error ? `, ${fromElsewhere.error}` : ""}`);
      assert.equal(fromElsewhere.state, "Failure");
      // 2.0 rejects it at execute; the 1.6 OffRamp already rejects it at commit.
      assert.match(fromElsewhere.error ?? "", ccipVersion === "2.0" ? /InvalidOnrampAddress/ : /commit failed:.*OnrampNotConfigured/);
      assert.equal(await readCounter(), before + 1n);
    });

    it("returns the error a user sees when the compute-unit limit is too low", async () => {
      const before = await readCounter();
      const { receipt } = await send(svmExtraArgs({ computeUnits: 1_000, accounts, writableBitmap: 0b11n }));
      const [result] = await routeToSvm(svm, receipt);
      console.log(`[svm-result] 1000 CU: ${result.error}`);
      assert.equal(result.state, "Failure");
      assert.match(result.error ?? "", /compute budget exceeded: used \d+ of 1000 compute units/);
      assert.equal(await readCounter(), before);
    });

    it("handles a writable bitmap with a stray bit as the lane version does", async () => {
      // Bit 10 points past the 3 accounts.
      const before = await readCounter();
      const strayBit = svmExtraArgs({ computeUnits: 200_000, accounts, writableBitmap: 0b11n | (1n << 10n) });
      if (ccipVersion === "1.6") {
        // A CCIP 1.6 FeeQuoter rejects it at send time, so nothing reaches Solana.
        await assert.rejects(send(strayBit), (error: { data?: string; message?: string }) => {
          const selector = router.interface.getError("InvalidSVMExtraArgsWritableBitmap").selector;
          return error.data?.startsWith(selector) || /InvalidSVMExtraArgsWritableBitmap/.test(error.message ?? "");
        });
        assert.equal(await readCounter(), before);
        return;
      }
      // A CCIP 2.0 lane accepts this at send time (so does the local router).
      const { receipt } = await send(strayBit);
      const [result] = await routeToSvm(svm, receipt);
      console.log(`[svm-result] stray bitmap bit: ${result.state}${result.error ? `, ${result.error}` : ""}`);
      // The real OffRamp ignores bits beyond the account list, so the message executes.
      assert.equal(result.state, "Success", result.error);
      assert.equal(await readCounter(), before + 1n);
    });

    it("charges the fee in native and in LINK", async () => {
      const extraArgs = svmExtraArgs({ computeUnits: 200_000, accounts, writableBitmap: 0b11n });

      const nativeBefore = await ethers.provider.getBalance(router);
      const native = await send(extraArgs);
      assert.equal((await ethers.provider.getBalance(router)) - nativeBefore, FEE);

      const linkBefore = await link.balanceOf(router);
      const paidInLink = await send(extraArgs, await link.getAddress());
      assert.equal((await link.balanceOf(router)) - linkBefore, FEE);

      for (const { receipt } of [native, paidInLink]) {
        const [result] = await routeToSvm(svm, receipt);
        assert.equal(result.state, "Success", result.error);
      }
    });

    it("throws when the router's lane version differs from the Solana side", async () => {
      const other: CcipVersion = ccipVersion === "2.0" ? "1.6" : "2.0";
      const before = await readCounter();
      await router.setSvmLaneVersion(LANE_VERSION[other]);
      try {
        const { receipt } = await send(svmExtraArgs({ computeUnits: 200_000, accounts, writableBitmap: 0b11n }));
        await assert.rejects(routeToSvm(svm, receipt), (error: Error) => {
          assert.match(error.message, new RegExp(`CCIP ${other} rules`));
          assert.match(error.message, new RegExp(`runs CCIP ${ccipVersion}`));
          assert.match(error.message, /setSvmLaneVersion/);
          assert.match(error.message, /startSvmLocal\(\{ ccipVersion/);
          return true;
        });
        assert.equal(await readCounter(), before, "nothing was delivered");
        // Without a provider the check is skipped and the message goes through.
        const [result] = await routeToSvm(svm, { logs: receipt.logs });
        assert.equal(result.state, "Success", result.error);
      } finally {
        await router.setSvmLaneVersion(LANE_VERSION[ccipVersion]);
      }
    });

    it("throws when the receipt holds no message to Solana", async () => {
      await assert.rejects(routeToSvm(svm, { logs: [] }), /no SvmMessageSent log/);
    });
  });
}
