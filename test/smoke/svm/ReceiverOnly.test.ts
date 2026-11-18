import assert from "node:assert/strict";
import path from "node:path";
import { after, before, describe, it } from "node:test";
import anchor from "@anchor-lang/core";
import { PublicKey, SystemProgram, Transaction } from "@solana/web3.js";
import { readIdl, resolveArtifacts } from "../../../scripts/svm/artifacts.ts";
import { CCIP_PROGRAMS } from "../../../scripts/svm/programs.ts";
import { startSvmLocal, type SvmLocal } from "../../../scripts/svm/index.ts";

const { AnchorProvider, Program, Wallet } = anchor;

async function timed<T>(step: string, work: () => Promise<T>): Promise<T> {
  const start = performance.now();
  const value = await work();
  console.log(`[svm-timing] ${step} ${Math.round(performance.now() - start)}ms`);
  return value;
}

describe("deliver a message to a receiver program through the real OffRamp", () => {
  const receiverId = new PublicKey(CCIP_PROGRAMS.test_ccip_receiver);
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
    svm = await timed("startSvmLocal", () => startSvmLocal());

    const bundleDir = await resolveArtifacts();
    const soPath = path.join(bundleDir, "target", "deploy", "test_ccip_receiver.so");
    await timed("deployProgram", () => svm.deployProgram(soPath, receiverId));

    const provider = new AnchorProvider(svm.connection, new Wallet(svm.payer), { commitment: "confirmed" });
    const receiver = new Program(readIdl(bundleDir, "test_ccip_receiver") as never, provider);
    const initialize = await receiver.methods
      .initialize(svm.ccip.router)
      .accounts({ counter, externalExecutionConfig, authority: svm.payer.publicKey, systemProgram: SystemProgram.programId })
      .instruction();
    await timed("initialize-receiver", () => svm.sendAndConfirm(new Transaction().add(initialize)));
  });

  after(() => svm?.stop());

  it("exposes the CCIP addresses and chain selector", () => {
    assert.equal(svm.ccip.router.toBase58(), CCIP_PROGRAMS.ccip_router);
    assert.equal(svm.ccip.offRamp.toBase58(), CCIP_PROGRAMS.ccip_offramp);
    assert.equal(svm.ccip.chainSelector, 16423721717087811551n);
  });

  it("delivers a message and the receiver's state changes", async () => {
    const before = await readCounter();
    const result = await timed("deliver-hello", () =>
      svm.deliver({ receiverProgram: receiverId, receiverAccounts, receiverWritableBitmap, data: "hello" }),
    );
    assert.equal(result.state, "Success", result.error);
    console.log(`[svm-result] hello: ${result.state}, ${result.computeUnitsUsed} compute units`);
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
    console.log(`[svm-result] 1000 CU: ${result.error}`);
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
    console.log(`[svm-timing] misordered-account error: ${result.error}`);
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

  it("throws on misuse", async () => {
    await assert.rejects(
      svm.deliver({ receiverProgram: PublicKey.unique(), receiverAccounts, receiverWritableBitmap, data: "x" }),
      /not a deployed program/,
    );
    await assert.rejects(
      svm.deliver({ receiverProgram: receiverId, receiverAccounts, receiverWritableBitmap, data: "x", computeUnits: 0 }),
      /computeUnits/,
    );
    await assert.rejects(
      svm.deliver({ receiverProgram: receiverId, receiverAccounts, receiverWritableBitmap: 0b1000n, data: "x" }),
      /receiverWritableBitmap/,
    );
    await assert.rejects(
      svm.deliver({ receiverProgram: receiverId, receiverAccounts, receiverWritableBitmap, data: "x", sourceChainSelector: 1n }),
      /not configured/,
    );
  });
});
