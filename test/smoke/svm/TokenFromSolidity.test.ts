// Journey 3: a Solidity contract sends CCIP-BnM to Solana, alone or with data, and routeToSvm delivers it through the
// real BurnMint pool of the local Solana side (CCIP 2.0 and 1.6).
import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import anchor from "@anchor-lang/core";
import { Keypair, PublicKey, SystemProgram, Transaction } from "@solana/web3.js";
import { network } from "hardhat";
import {
  exampleReceiver,
  routeToSvm,
  startSvmLocal,
  svmExtraArgs,
  type BurnMintToken,
  type CcipVersion,
  type SvmLocal,
} from "../../../scripts/svm/index.ts";

const { AnchorProvider, Program, Wallet } = anchor;
const SOLANA_SELECTOR = 16423721717087811551n;
const FEE = 10n ** 16n;
const VERSIONS: CcipVersion[] = ["2.0", "1.6"];
// `CCIPLocalRouter.SvmLaneVersion` by CCIP version.
const LANE_VERSION = { "2.0": 0, "1.6": 1 } as const;
const ONE_TOKEN = 10n ** 18n; // CCIP-BnM has 18 decimals; the Solana mint has 9, so one token is 1e9 on Solana
const NO_RECEIVER = new Uint8Array(32);
// A token-only send carries no compute units (a CCIP 1.6 lane requires 0 for a zero receiver). With a program they are
// the receiver's budget, as for data-only messages; the delivery adds the token overhead on top, like a live executor.
const PROGRAM_COMPUTE_UNITS = 200_000;
const fileStart = performance.now();

for (const ccipVersion of VERSIONS) {
  const receiver = await exampleReceiver({ ccipVersion });
  // Timing lines carry the lane version as a suffix: `[svm-timing] journey-3 token-only@1.6 41ms`.
  async function timed<T>(step: string, work: () => Promise<T>): Promise<T> {
    const start = performance.now();
    const value = await work();
    console.log(`[svm-timing] ${step}@${ccipVersion} ${Math.round(performance.now() - start)}ms`);
    return value;
  }

  describe(`CCIP ${ccipVersion}: a Solidity contract sends tokens to Solana`, () => {
    const receiverId = receiver.programId;
    const counter = PublicKey.findProgramAddressSync([Buffer.from("counter")], receiverId)[0];
    const externalExecutionConfig = PublicKey.findProgramAddressSync([Buffer.from("external_execution_config")], receiverId)[0];
    const accounts = [externalExecutionConfig, counter, SystemProgram.programId];

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let ethers: any, router: any, bnm: any, lnm: any, sender: any, svm: SvmLocal, mint: BurnMintToken;
    const wallet = () => Keypair.generate().publicKey;
    const readCounter = async () => (await svm.connection.getAccountInfo(counter))!.data.readBigUInt64LE(8);

    /** Sends `amount` of `token` from the Solidity sender; `receiverProgram` and `data` make it a token-plus-data message. */
    async function sendToken(
      tokenReceiver: PublicKey | undefined,
      amount: bigint,
      options: { token?: unknown; receiverProgram?: PublicKey; data?: string } = {},
    ) {
      const withProgram = options.receiverProgram !== undefined;
      const extraArgs = svmExtraArgs({
        computeUnits: withProgram ? PROGRAM_COMPUTE_UNITS : 0,
        accounts: withProgram ? accounts : [],
        writableBitmap: withProgram ? 0b11n : 0n,
        tokenReceiver,
      });
      const tx = await sender.sendToken(
        SOLANA_SELECTOR,
        options.receiverProgram?.toBytes() ?? NO_RECEIVER,
        ethers.toUtf8Bytes(options.data ?? ""),
        extraArgs,
        ethers.ZeroAddress,
        options.token ?? bnm,
        amount,
      );
      return tx.wait();
    }

    before(async () => {
      ({ ethers } = await network.connect());
      const simulator = await ethers.deployContract("CCIPLocalSimulator");
      const [, sourceRouter, , , linkToken, ccipBnM, ccipLnM] = await simulator.configuration();
      router = await ethers.getContractAt("CCIPLocalRouter", sourceRouter);
      await router.setSvmLane(await ethers.deployContract("CCIPLocalSvmLane"));
      await router.setSvmLaneVersion(LANE_VERSION[ccipVersion]);
      await router.setFee(FEE);
      bnm = await ethers.getContractAt("BurnMintERC677Helper", ccipBnM);
      lnm = await ethers.getContractAt("BurnMintERC677Helper", ccipLnM);
      sender = await ethers.deployContract("SvmMessageSender", [sourceRouter, linkToken]);

      // The sender pays the fee in native and holds the tokens (the faucet drips one token per call).
      const [funder] = await ethers.getSigners();
      await funder.sendTransaction({ to: sender, value: ethers.parseEther("1") });
      for (let i = 0; i < 10; i++) {
        await bnm.drip(sender);
        await lnm.drip(sender);
      }

      svm = await timed("startSvmLocal", () => startSvmLocal({ ccipVersion }));
      mint = await svm.createBurnMintToken();
      // CCIP-BnM is linked; CCIP-LnM stays unlinked for the misuse test.
      await svm.linkToken(mint, { evmToken: await bnm.getAddress() });
      await svm.deployProgram(receiver.programPath, receiverId);
      const provider = new AnchorProvider(svm.connection, new Wallet(svm.payer), { commitment: "confirmed" });
      const initialize = await new Program(receiver.idl as never, provider).methods
        .initialize(svm.ccip.router)
        .accounts({ counter, externalExecutionConfig, authority: svm.payer.publicKey, systemProgram: SystemProgram.programId })
        .instruction();
      await svm.sendAndConfirm(new Transaction().add(initialize));
    });

    after(() => {
      svm?.stop();
      console.log(`[svm-timing] TokenFromSolidity file@${ccipVersion} ${Math.round(performance.now() - fileStart)}ms`);
    });

    it("delivers CCIP-BnM to a wallet and mints the converted amount", async () => {
      const owner = wallet();
      await svm.createTokenAccount(mint.mint, owner); // required on 1.6, harmless on 2.0
      const amount = 3n * ONE_TOKEN / 2n;
      const senderBefore = await bnm.balanceOf(sender);
      const routerBefore = await bnm.balanceOf(router);

      const start = performance.now();
      const receipt = await sendToken(owner, amount);
      assert.equal(senderBefore - (await bnm.balanceOf(sender)), amount, "EVM balance of the sender is down");
      assert.equal((await bnm.balanceOf(router)) - routerBefore, amount, "the router holds the tokens");

      const [result] = await routeToSvm(svm, receipt);
      console.log(`[svm-timing] journey-3 token-only send-to-result@${ccipVersion} ${Math.round(performance.now() - start)}ms`);
      console.log(`[svm-result] BnM token-only@${ccipVersion}: ${result.computeUnitsUsed} compute units`);
      assert.equal(result.state, "Success", result.error);
      assert.equal(await svm.tokenBalance(mint.mint, owner), 1_500_000_000n);
      assert.equal(await readCounter(), 0n, "no program was called");
    });

    it("delivers CCIP-BnM and data to the example receiver", async () => {
      const owner = wallet();
      await svm.createTokenAccount(mint.mint, owner);
      const senderBefore = await bnm.balanceOf(sender);
      const counterBefore = await readCounter();

      const start = performance.now();
      const receipt = await sendToken(owner, 2n * ONE_TOKEN, { receiverProgram: receiverId, data: "hello" });
      const [result] = await routeToSvm(svm, receipt);
      console.log(`[svm-timing] journey-3 token-and-data send-to-result@${ccipVersion} ${Math.round(performance.now() - start)}ms`);
      console.log(`[svm-result] BnM token+data@${ccipVersion}: ${result.computeUnitsUsed} compute units`);
      assert.equal(result.state, "Success", result.error);
      assert.equal(await readCounter(), counterBefore + 1n);
      assert.equal(await svm.tokenBalance(mint.mint, owner), 2_000_000_000n);
      assert.equal(senderBefore - (await bnm.balanceOf(sender)), 2n * ONE_TOKEN);
    });

    it("throws for a token that is not linked, and delivers nothing", async () => {
      const owner = wallet();
      await svm.createTokenAccount(mint.mint, owner);
      const receipt = await sendToken(owner, ONE_TOKEN, { token: lnm });
      const lnmPattern = new RegExp((await lnm.getAddress()).slice(2), "i");
      await assert.rejects(routeToSvm(svm, receipt), (error: Error) => {
        assert.match(error.message, lnmPattern);
        assert.match(error.message, /not linked to a Solana token/);
        assert.match(error.message, /svm\.linkToken\(/);
        return true;
      });
      assert.equal(await svm.tokenBalance(mint.mint, owner), 0n);
    });

    if (ccipVersion === "1.6") {
      it("fails with AccountNotInitialized without the receiver's token account, and works after createTokenAccount", async () => {
        const owner = wallet();
        const [failed] = await routeToSvm(svm, await sendToken(owner, ONE_TOKEN));
        console.log(`[svm-result] BnM without ATA@1.6: ${failed.state}, ${failed.error}`);
        assert.equal(failed.state, "Failure");
        assert.match(failed.error ?? "", /AccountNotInitialized/);
        assert.equal(await svm.tokenBalance(mint.mint, owner), 0n);

        await svm.createTokenAccount(mint.mint, owner);
        const [result] = await routeToSvm(svm, await sendToken(owner, ONE_TOKEN));
        assert.equal(result.state, "Success", result.error);
        assert.equal(await svm.tokenBalance(mint.mint, owner), 1_000_000_000n);
      });

      it("rejects a zero tokenReceiver at send time", async () => {
        await assert.rejects(sendToken(undefined, ONE_TOKEN), (error: { data?: string; message?: string }) => {
          const selector = router.interface.getError("InvalidTokenReceiver").selector;
          return error.data?.startsWith(selector) || /InvalidTokenReceiver/.test(error.message ?? "");
        });
      });
    } else {
      it("creates the receiver's token account when it does not exist", async () => {
        const owner = wallet();
        const [result] = await routeToSvm(svm, await sendToken(owner, ONE_TOKEN));
        assert.equal(result.state, "Success", result.error);
        assert.equal(await svm.tokenBalance(mint.mint, owner), 1_000_000_000n);
      });

      it("returns the Solana-side result of a zero tokenReceiver", async () => {
        // OnRamp 2.0 accepts it at send time, so the message reaches Solana with an all-zero receiver.
        const senderBefore = await bnm.balanceOf(sender);
        const zeroBefore = await svm.tokenBalance(mint.mint, PublicKey.default);
        const [result] = await routeToSvm(svm, await sendToken(undefined, ONE_TOKEN));
        console.log(`[svm-result] zero tokenReceiver@2.0: ${result.state}${result.error ? `, ${result.error}` : ""}`);
        assert.equal(senderBefore - (await bnm.balanceOf(sender)), ONE_TOKEN);
        // The OffRamp does not reject it: it mints to the token account of the all-zero address (the System Program's
        // key), where nobody can spend them.
        assert.equal(result.state, "Success", result.error);
        assert.equal(await svm.tokenBalance(mint.mint, PublicKey.default), zeroBefore + 1_000_000_000n);
      });
    }
  });
}
