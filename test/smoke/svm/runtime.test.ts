import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { LAMPORTS_PER_SOL, SystemProgram, Transaction, PublicKey } from "@solana/web3.js";
import { readProgram, resolveArtifacts } from "../../../scripts/svm/artifacts.ts";
import { CCIP_PROGRAMS, deployCcipPrograms } from "../../../scripts/svm/programs.ts";
import { SvmRuntime } from "../../../scripts/svm/runtime.ts";

async function timed<T>(step: string, work: () => Promise<T> | T): Promise<T> {
  const start = performance.now();
  const value = await work();
  console.log(`[svm-timing] ${step} ${Math.round(performance.now() - start)}ms`);
  return value;
}

describe("embedded Surfnet runtime", () => {
  let runtime: SvmRuntime;
  let bundleDir: string;

  before(async () => {
    // "download" on a cold cache, a cache hit (a few ms) otherwise.
    bundleDir = await timed("artifacts-resolve", () => resolveArtifacts());
    runtime = await timed("boot", () => SvmRuntime.start());
  });

  after(() => runtime?.stop());

  it("deploys every CCIP 2.0 program as executable, with the payer as upgrade authority", async () => {
    await timed("deploy-all-programs", () => deployCcipPrograms(runtime, bundleDir));

    for (const [name, id] of Object.entries(CCIP_PROGRAMS)) {
      const account = await runtime.connection.getAccountInfo(new PublicKey(id));
      assert.ok(account?.executable, `${name} (${id}) is not executable`);
    }
  });

  it("stores the exact program bytes (including a program larger than one write chunk) and the payer as authority", async () => {
    for (const name of ["ccip_router", "rmn_remote"] as const) {
      const program = await runtime.connection.getAccountInfo(new PublicKey(CCIP_PROGRAMS[name]));
      const programData = await runtime.connection.getAccountInfo(new PublicKey(program!.data.subarray(4, 36)));
      const header = programData!.data.subarray(0, 45); // tag u32, slot u64, Option<authority>
      assert.equal(header[12], 1, `${name} has no upgrade authority`);
      assert.deepEqual(new PublicKey(header.subarray(13, 45)), runtime.payer.publicKey);
      const bytes = readProgram(bundleDir, name);
      assert.ok(programData!.data.subarray(45, 45 + bytes.length).equals(bytes), `${name} bytes differ`);
    }
  });

  it("confirms a transaction by polling", async () => {
    const recipient = PublicKey.unique();
    const transfer = new Transaction().add(
      SystemProgram.transfer({ fromPubkey: runtime.payer.publicKey, toPubkey: recipient, lamports: LAMPORTS_PER_SOL }),
    );
    await timed("transfer", () => runtime.sendAndConfirm(transfer));
    assert.equal(await runtime.connection.getBalance(recipient), LAMPORTS_PER_SOL);
  });

  // web3.js guesses the WebSocket at the HTTP port + 1, which is wrong whenever the free ports are not consecutive
  // (the usual case on Linux): subscriptions then never connect and the client retries forever, hanging the process.
  it("connects subscriptions to the Surfnet's real WebSocket endpoint", async () => {
    const endpoint = (runtime.connection as unknown as { _rpcWsEndpoint: string })._rpcWsEndpoint;
    assert.equal(endpoint, runtime.wsUrl);
    const recipient = PublicKey.unique();
    // confirmTransaction with a bare signature waits on a WebSocket subscription.
    const signature = await runtime.connection.requestAirdrop(recipient, LAMPORTS_PER_SOL);
    await timed("confirm-over-websocket", () => runtime.connection.confirmTransaction(signature, "confirmed"));
    assert.equal(await runtime.connection.getBalance(recipient), LAMPORTS_PER_SOL);
  });

  it("wraps the account and time cheatcodes", async () => {
    const address = PublicKey.unique();
    await runtime.setAccount(address, { lamports: 777 });
    assert.equal(await runtime.connection.getBalance(address), 777);

    const travelled = await runtime.timeTravel({ absoluteSlot: 500_000 });
    assert.equal(travelled.absoluteSlot, 500_000);
    assert.equal((await runtime.connection.getEpochInfo("processed")).absoluteSlot >= 500_000, true);
  });
});
