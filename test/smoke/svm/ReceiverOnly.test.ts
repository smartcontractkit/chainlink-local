import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import anchor from "@anchor-lang/core";
import { ComputeBudgetProgram, PublicKey, SystemProgram, Transaction } from "@solana/web3.js";
import { programIds } from "../../../scripts/svm/programs.ts";
import { exampleReceiver, startSvmLocal, type CcipVersion, type SvmLocal } from "../../../scripts/svm/index.ts";

const { AnchorProvider, Program, Wallet } = anchor;

const VERSIONS: CcipVersion[] = ["2.0", "1.6"];

for (const ccipVersion of VERSIONS) {
  const receiver = await exampleReceiver({ ccipVersion });
  // Timing lines carry the lane version as a suffix: `[svm-timing] deliver-hello@1.6 41ms`.
  async function timed<T>(step: string, work: () => Promise<T>): Promise<T> {
    const start = performance.now();
    const value = await work();
    console.log(`[svm-timing] ${step}@${ccipVersion} ${Math.round(performance.now() - start)}ms`);
    return value;
  }

  describe(`CCIP ${ccipVersion}: deliver a message to a receiver program through the real OffRamp`, () => {
    const receiverId = receiver.programId;
    const counter = PublicKey.findProgramAddressSync([Buffer.from("counter")], receiverId)[0];
    const externalExecutionConfig = PublicKey.findProgramAddressSync(
      [Buffer.from("external_execution_config")],
      receiverId,
    )[0];
    const receiverAccounts = [externalExecutionConfig, counter, SystemProgram.programId];
    const receiverWritableBitmap = 0b11n;

    let svm: SvmLocal;
    const readCounter = async () => {
      const account = await svm.connection.getAccountInfo(counter);
      assert.ok(account, "receiver counter is not initialised");
      return account.data.readBigUInt64LE(8);
    };

    before(async () => {
      // Warm cache: the bundle is already downloaded, so this is boot + deploy + trust-layer setup.
      svm = await timed("startSvmLocal", () => startSvmLocal({ ccipVersion }));

      await timed("deployProgram", () => svm.deployProgram(receiver.programPath, receiverId));

      const provider = new AnchorProvider(svm.connection, new Wallet(svm.payer), { commitment: "confirmed" });
      const receiverProgram = new Program(receiver.idl as never, provider);
      const initialize = await receiverProgram.methods
        .initialize(svm.ccip.router)
        .accounts({ counter, externalExecutionConfig, authority: svm.payer.publicKey, systemProgram: SystemProgram.programId })
        .instruction();
      await timed("initialize-receiver", () => svm.sendAndConfirm(new Transaction().add(initialize)));
    });

    after(() => svm?.stop());

    it("exposes the CCIP version, addresses and chain selector", () => {
      assert.equal(svm.ccipVersion, ccipVersion);
      assert.equal(svm.ccip.router.toBase58(), programIds(ccipVersion).ccip_router);
      assert.equal(svm.ccip.offRamp.toBase58(), programIds(ccipVersion).ccip_offramp);
      assert.equal(svm.ccip.chainSelector, 16423721717087811551n);
    });

    it("delivers a message and the receiver's state changes", async () => {
      const before = await readCounter();
      const result = await timed("deliver-hello", () =>
        svm.deliver({ receiverProgram: receiverId, receiverAccounts, receiverWritableBitmap, data: "hello" }),
      );
      assert.equal(result.state, "Success", result.error);
      console.log(`[svm-result] hello@${ccipVersion}: ${result.state}, ${result.computeUnitsUsed} compute units`);
      assert.equal(result.error, undefined);
      assert.match(result.messageId, /^0x[0-9a-f]{64}$/);
      assert.ok(result.computeUnitsUsed > 0 && result.computeUnitsUsed <= 200_000, `used ${result.computeUnitsUsed}`);
      assert.ok(result.logs.length > 0);
      assert.equal(await readCounter(), before + 1n);
    });

    it("returns Failure with a readable reason when the compute-unit limit is too low", async () => {
      const before = await readCounter();
      const result = await timed("deliver-1000-cu", () =>
        svm.deliver({ receiverProgram: receiverId, receiverAccounts, receiverWritableBitmap, data: "hello", computeUnits: 1_000 }),
      );
      assert.equal(result.state, "Failure");
      console.log(`[svm-result] 1000 CU@${ccipVersion}: ${result.error}`);
      assert.match(result.error ?? "", /compute budget exceeded: used \d+ of 1000 compute units/);
      assert.equal(await readCounter(), before, "a failed delivery must not change state");
    });

    it("returns Failure naming the Anchor error when an account is misordered", async () => {
      const result = await timed("deliver-misordered", () =>
        svm.deliver({
          receiverProgram: receiverId,
          receiverAccounts: [counter, externalExecutionConfig, SystemProgram.programId],
          receiverWritableBitmap,
          data: "hello",
        }),
      );
      assert.equal(result.state, "Failure");
      assert.match(result.error ?? "", /AnchorError.*Error Code: \w+/);
      console.log(`[svm-timing] misordered-account error@${ccipVersion}: ${result.error}`);
    });

    it("gives two identical calls different message ids", async () => {
      const options = { receiverProgram: receiverId, receiverAccounts, receiverWritableBitmap, data: "same" };
      const first = await timed("deliver-same-1", () => svm.deliver(options));
      const second = await timed("deliver-same-2", () => svm.deliver(options));
      assert.equal(first.state, "Success", first.error);
      assert.equal(second.state, "Success", second.error);
      assert.notEqual(first.messageId, second.messageId);
    });

    it("keeps delivering after many slots have passed", async () => {
      const before = await readCounter();
      for (let i = 0; i < 10; i++) {
        const result = await svm.deliver({ receiverProgram: receiverId, receiverAccounts, receiverWritableBitmap, data: `n${i}` });
        assert.equal(result.state, "Success", result.error);
      }
      assert.equal(await readCounter(), before + 10n);
    });

    const base = { receiverProgram: receiverId, receiverAccounts, receiverWritableBitmap, data: "x" };

    it("executes a message whose writable bitmap has bits beyond the accounts", async () => {
      // A CCIP 2.0 lane accepts this at send time; the real OffRamp ignores the extra bits.
      const before = await readCounter();
      const result = await svm.deliver({ ...base, receiverWritableBitmap: 0b11n | (1n << 10n) });
      assert.equal(result.state, "Success", result.error);
      assert.equal(await readCounter(), before + 1n);
    });

    it("returns Failure when the receiver is not a deployed program", async () => {
      const result = await svm.deliver({ ...base, receiverProgram: PublicKey.unique() });
      assert.equal(result.state, "Failure");
      assert.match(result.error ?? "", /UnsupportedProgramId/);
    });

    it("executes with more than 1,400,000 compute units: Surfnet clamps the limit to 1,400,000", async () => {
      // The EVM lane accepts up to 3,000,000. Like a validator, Surfnet caps the transaction budget at 1.4M.
      const result = await svm.deliver({ ...base, computeUnits: 3_000_000 });
      assert.equal(result.state, "Success", result.error);
      assert.ok(result.logs.some((line) => /consumed \d+ of 1399850 compute units/.test(line)), "budget should be 1.4M minus the limit instruction");
    });

    it("runs a message with 0 compute units instead of throwing: a CCIP 2.0 EVM send accepts it", async () => {
      const before = await readCounter();
      const result = await svm.deliver({ ...base, computeUnits: 0 });
      console.log(`[svm-result] 0 compute units@${ccipVersion}: ${result.state}${result.error ? `, ${result.error}` : ""}`);
      assert.equal(result.state, "Failure");
      assert.ok(result.error, "a failure must explain itself");
      assert.equal(await readCounter(), before, "the receiver must not run");
    });

    if (ccipVersion === "1.6") {
      it("runs the 1.6 OffRamp out of heap above 14 receiver accounts, as on the live lane", async () => {
        // test_ccip_receiver CPIs into its first extra account with the rest; ComputeBudget is a no-op target.
        const extra = [ComputeBudgetProgram.programId, ...Array.from({ length: 11 }, () => PublicKey.unique())];
        const fourteen = await svm.deliver({ receiverProgram: receiverId, receiverAccounts: [...receiverAccounts, ...extra.slice(0, 11)], receiverWritableBitmap });
        assert.equal(fourteen.state, "Success", fourteen.error);

        const before = await readCounter();
        const fifteen = await svm.deliver({ receiverProgram: receiverId, receiverAccounts: [...receiverAccounts, ...extra], receiverWritableBitmap });
        console.log(`[svm-result] 15 receiver accounts@${ccipVersion}: ${fifteen.error}`);
        assert.equal(fifteen.state, "Failure");
        assert.match(fifteen.error ?? "", new RegExp(`^${svm.ccip.offRamp.toBase58()} ran out of heap`));
        assert.equal(await readCounter(), before, "the receiver must not run");
      });
    }

    it("throws on misuse", async () => {
      await assert.rejects(svm.deliver({ ...base, computeUnits: -1 }), /computeUnits/);
      await assert.rejects(svm.deliver({ ...base, computeUnits: 1.5 }), /computeUnits/);
      await assert.rejects(svm.deliver({ ...base, receiverWritableBitmap: 1n << 64n }), /receiverWritableBitmap/);
      await assert.rejects(svm.deliver({ ...base, receiverProgram: "x" as never }), /PublicKey/);
      await assert.rejects(svm.deliver({ ...base, onRampAddress: new Uint8Array(19) }), /onRampAddress/);
      await assert.rejects(svm.deliver({ ...base, sourceChainSelector: 1n }), /not configured/);
    });
  });
}
