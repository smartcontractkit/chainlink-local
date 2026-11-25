import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import anchor from "@anchor-lang/core";
import { Keypair, PublicKey, SystemProgram, Transaction } from "@solana/web3.js";
import { associatedTokenAddress } from "../../../scripts/svm/tokens.ts";
import { exampleReceiver, startSvmLocal, type BurnMintToken, type CcipVersion, type SvmLocal } from "../../../scripts/svm/index.ts";

const { AnchorProvider, Program, Wallet } = anchor;

const VERSIONS: CcipVersion[] = ["2.0", "1.6"];
const EVM_TOKEN = "0x00000000000000000000000000000000000000Aa";
const ONE_TOKEN = 10n ** 18n; // 18 EVM decimals; the Solana mint has 9, so this mints 1e9

for (const ccipVersion of VERSIONS) {
  const receiver = await exampleReceiver({ ccipVersion });
  async function timed<T>(step: string, work: () => Promise<T>): Promise<T> {
    const start = performance.now();
    const value = await work();
    console.log(`[svm-timing] ${step}@${ccipVersion} ${Math.round(performance.now() - start)}ms`);
    return value;
  }

  describe(`CCIP ${ccipVersion}: deliver tokens to Solana through the BurnMint pool`, () => {
    const counter = PublicKey.findProgramAddressSync([Buffer.from("counter")], receiver.programId)[0];
    const externalExecutionConfig = PublicKey.findProgramAddressSync([Buffer.from("external_execution_config")], receiver.programId)[0];

    let svm: SvmLocal;
    let token: BurnMintToken;
    const wallet = () => Keypair.generate().publicKey;
    const readCounter = async () => (await svm.connection.getAccountInfo(counter))!.data.readBigUInt64LE(8);

    before(async () => {
      svm = await startSvmLocal({ ccipVersion });
      token = await timed("createBurnMintToken", () => svm.createBurnMintToken());
      await timed("linkToken", () => svm.linkToken(token, { evmToken: EVM_TOKEN }));

      await svm.deployProgram(receiver.programPath, receiver.programId);
      const provider = new AnchorProvider(svm.connection, new Wallet(svm.payer), { commitment: "confirmed" });
      const initialize = await new Program(receiver.idl as never, provider).methods
        .initialize(svm.ccip.router)
        .accounts({ counter, externalExecutionConfig, authority: svm.payer.publicKey, systemProgram: SystemProgram.programId })
        .instruction();
      await svm.sendAndConfirm(new Transaction().add(initialize));
    });

    after(() => svm?.stop());

    it("creates a token and links it to an EVM token", async () => {
      assert.equal(token.decimals, 9);
      assert.equal(svm.linkedMint(EVM_TOKEN)?.toBase58(), token.mint.toBase58());
      assert.equal(svm.linkedMint(EVM_TOKEN.toLowerCase())?.toBase58(), token.mint.toBase58(), "lookup ignores case");
      assert.equal(svm.linkedMint("0x" + "11".repeat(20)), undefined);
      const mint = await svm.connection.getParsedAccountInfo(token.mint);
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const parsed = (mint.value!.data as any).parsed.info;
      assert.equal(parsed.decimals, 9);
      assert.equal(parsed.mintAuthority, PublicKey.findProgramAddressSync([Buffer.from("ccip_tokenpool_signer"), token.mint.toBuffer()], token.pool)[0].toBase58());
    });

    it("delivers a token-only message to a wallet and mints the converted amount", async () => {
      const owner = wallet();
      await svm.createTokenAccount(token.mint, owner); // required on 1.6, harmless on 2.0
      const result = await timed("deliver-token-only", () => svm.deliver({ token: { evmToken: EVM_TOKEN, amount: 3n * ONE_TOKEN / 2n, receiver: owner } }));
      assert.equal(result.state, "Success", result.error);
      console.log(`[svm-result] token-only@${ccipVersion}: ${result.computeUnitsUsed} compute units`);
      assert.ok(result.computeUnitsUsed > 100_000 && result.computeUnitsUsed < 500_000, `used ${result.computeUnitsUsed}`);
      assert.equal(await svm.tokenBalance(token.mint, owner), 1_500_000_000n);
    });

    it("delivers tokens together with data to the example receiver", async () => {
      const owner = wallet();
      await svm.createTokenAccount(token.mint, owner);
      const before = await readCounter();
      const result = await timed("deliver-token-and-data", () =>
        svm.deliver({
          receiverProgram: receiver.programId,
          receiverAccounts: [externalExecutionConfig, counter, SystemProgram.programId],
          receiverWritableBitmap: 0b11n,
          data: "hello",
          token: { evmToken: EVM_TOKEN, amount: 2n * ONE_TOKEN, receiver: owner },
        }),
      );
      assert.equal(result.state, "Success", result.error);
      console.log(`[svm-result] token+data@${ccipVersion}: ${result.computeUnitsUsed} compute units`);
      assert.equal(await readCounter(), before + 1n);
      assert.equal(await svm.tokenBalance(token.mint, owner), 2_000_000_000n);
    });

    it("throws a clear error for an EVM token that is not linked", async () => {
      await assert.rejects(
        svm.deliver({ token: { evmToken: "0x" + "22".repeat(20), amount: 1n, receiver: wallet() } }),
        /not linked to a Solana token.*linkToken/,
      );
    });

    if (ccipVersion === "1.6") {
      it("fails with AccountNotInitialized when the receiver has no token account, and succeeds after createTokenAccount", async () => {
        const owner = wallet();
        const failed = await svm.deliver({ token: { evmToken: EVM_TOKEN, amount: ONE_TOKEN, receiver: owner } });
        assert.equal(failed.state, "Failure");
        assert.match(failed.error ?? "", /AccountNotInitialized/);
        assert.equal(await svm.tokenBalance(token.mint, owner), 0n);

        const account = await svm.createTokenAccount(token.mint, owner);
        assert.ok(await svm.connection.getAccountInfo(account));
        const result = await svm.deliver({ token: { evmToken: EVM_TOKEN, amount: ONE_TOKEN, receiver: owner } });
        assert.equal(result.state, "Success", result.error);
        assert.equal(await svm.tokenBalance(token.mint, owner), 1_000_000_000n);
      });
    } else {
      it("creates the receiver's token account when it does not exist", async () => {
        const owner = wallet();
        assert.equal(await svm.connection.getAccountInfo(associatedTokenAddress(token.mint, owner)), null);
        const result = await svm.deliver({ token: { evmToken: EVM_TOKEN, amount: ONE_TOKEN, receiver: owner } });
        assert.equal(result.state, "Success", result.error);
        assert.equal(await svm.tokenBalance(token.mint, owner), 1_000_000_000n);
      });
    }

    it("truncates an amount below one Solana unit to 0", async () => {
      const owner = wallet();
      await svm.createTokenAccount(token.mint, owner);
      const dust = 10n ** 9n - 1n; // 999,999,999 wei: less than one unit of a 9-decimal mint
      const result = await svm.deliver({ token: { evmToken: EVM_TOKEN, amount: dust, receiver: owner } });
      console.log(`[svm-result] dust@${ccipVersion}: ${result.state}${result.error ? `, ${result.error}` : ""}, balance ${await svm.tokenBalance(token.mint, owner)}`);
      assert.equal(result.state, "Success", result.error);
      assert.equal(await svm.tokenBalance(token.mint, owner), 0n);

      const exact = wallet();
      await svm.createTokenAccount(token.mint, exact);
      await svm.deliver({ token: { evmToken: EVM_TOKEN, amount: 10n ** 9n + 999_999_999n, receiver: exact } });
      assert.equal(await svm.tokenBalance(token.mint, exact), 1n, "the remainder below one unit is dropped, not rounded");
    });

    it("honours the decimals of the mint and of the linked EVM token", async () => {
      const six = await svm.createBurnMintToken({ decimals: 6 });
      const evmToken = "0x" + "33".repeat(20);
      await svm.linkToken(six, { evmToken, evmPool: "0x" + "44".repeat(20), evmDecimals: 8 });
      const owner = wallet();
      await svm.createTokenAccount(six.mint, owner);
      const result = await svm.deliver({ token: { evmToken, amount: 250_000_000n, receiver: owner } }); // 2.5 at 8 decimals
      assert.equal(result.state, "Success", result.error);
      assert.equal(await svm.tokenBalance(six.mint, owner), 2_500_000n);
    });

    it("reports 0n for an account that does not exist, and keeps an existing one on createTokenAccount", async () => {
      const owner = wallet();
      assert.equal(await svm.tokenBalance(token.mint, owner), 0n);
      const first = await svm.createTokenAccount(token.mint, owner);
      await svm.deliver({ token: { evmToken: EVM_TOKEN, amount: ONE_TOKEN, receiver: owner } });
      assert.equal((await svm.createTokenAccount(token.mint, owner)).toBase58(), first.toBase58());
      assert.equal(await svm.tokenBalance(token.mint, owner), 1_000_000_000n);
    });

    it("throws on misuse", async () => {
      const receiverOwner = wallet();
      const linked = { evmToken: EVM_TOKEN, amount: 1n, receiver: receiverOwner };
      await assert.rejects(svm.deliver({}), /receiverProgram is required unless a token/);
      await assert.rejects(svm.deliver({ token: linked, data: "x" }), /token-only/);
      await assert.rejects(svm.deliver({ token: linked, receiverAccounts: [counter] }), /token-only/);
      await assert.rejects(svm.deliver({ token: { ...linked, amount: -1n } }), /token\.amount/);
      await assert.rejects(svm.deliver({ token: { ...linked, receiver: "x" as never } }), /token\.receiver/);
      await assert.rejects(svm.linkToken(token, { evmToken: "0x" + "55".repeat(20) }), /already linked/);
      const other = await svm.createBurnMintToken();
      await assert.rejects(svm.linkToken(other, { evmToken: EVM_TOKEN.toLowerCase() }), /already linked/);
      await assert.rejects(svm.linkToken(other, { evmToken: "0x1234" }), /20-byte/);
      await assert.rejects(svm.linkToken({ mint: PublicKey.unique() }, { evmToken: "0x" + "66".repeat(20) }), /createBurnMintToken/);
      await assert.rejects(svm.createBurnMintToken({ decimals: 300 }), /decimals/);
    });
  });
}
