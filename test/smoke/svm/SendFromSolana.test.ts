import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { Keypair, LAMPORTS_PER_SOL, type PublicKey } from "@solana/web3.js";
import { keccak256 } from "ethers";
import {
  NO_EXECUTION_EXECUTOR,
  PLACEHOLDER_OFFRAMP_2_0,
  startSvmLocal,
  type BurnMintToken,
  type CcipVersion,
  type SvmLocal,
} from "../../../scripts/svm/index.ts";

const VERSIONS: CcipVersion[] = ["2.0", "1.6"];
const SVM_SELECTOR = 16423721717087811551n;
const EVM_SELECTOR = 16015286601757825753n;
const EVM_RECEIVER = "0x2222222222222222222222222222222222222222";
const EVM_TOKEN = "0x1111111111111111111111111111111111111111";
const ONE_TOKEN = 10n ** 9n; // the mint has 9 decimals

for (const ccipVersion of VERSIONS) {
  // Timing lines carry the lane version as a suffix: `[svm-timing] send-data@1.6 41ms`.
  async function timed<T>(step: string, work: () => Promise<T>): Promise<T> {
    const start = performance.now();
    const value = await work();
    console.log(`[svm-timing] ${step}@${ccipVersion} ${Math.round(performance.now() - start)}ms`);
    return value;
  }

  describe(`CCIP ${ccipVersion}: send a message from Solana through the real Router`, () => {
    let svm: SvmLocal;
    let token: BurnMintToken;
    const wallet = Keypair.generate();
    const computeUnits = async (signature: string) =>
      (await svm.connection.getTransaction(signature, { commitment: "confirmed", maxSupportedTransactionVersion: 0 }))!.meta!.computeUnitsConsumed;
    // A sender pays the CCIP fee in SOL, so it is funded first, as in any localnet or devnet test.
    const fund = async (key: PublicKey) => {
      const signature = await svm.connection.requestAirdrop(key, 10 * LAMPORTS_PER_SOL);
      await svm.connection.confirmTransaction(signature, "confirmed");
    };

    before(async () => {
      svm = await timed("startSvmLocal", () => startSvmLocal({ ccipVersion }));
      token = await svm.createBurnMintToken();
      await svm.linkToken(token, { evmToken: EVM_TOKEN });
      await fund(wallet.publicKey);
    });

    after(() => svm?.stop());

    it("sends a data-only message and decodes it", async () => {
      const sent = await timed("send-data", () =>
        svm.send({ sender: wallet, receiver: EVM_RECEIVER, data: Buffer.from("hello evm"), gasLimit: 250_000n }),
      );
      console.log(`[svm-result] send-data@${ccipVersion}: ${await computeUnits(sent.signature)} compute units`);
      assert.equal(sent.ccipVersion, ccipVersion);
      assert.match(sent.messageId, /^0x[0-9a-f]{64}$/);
      assert.equal(sent.sourceChainSelector, SVM_SELECTOR);
      assert.equal(sent.destChainSelector, EVM_SELECTOR);
      assert.equal(sent.receiver, EVM_RECEIVER);
      assert.equal(Buffer.from(sent.data).toString(), "hello evm");
      assert.equal(sent.gasLimit, 250_000n);
      assert.deepEqual(sent.sender, wallet.publicKey.toBytes());
      assert.equal(sent.finality, "0x00000000");
      assert.equal(sent.token, undefined);
      assert.equal(sent.sequenceNumber, 1n);
      assert.equal(sent.nonce, ccipVersion === "1.6" ? 1n : 0n);
      if (ccipVersion === "2.0") {
        assert.ok(sent.encodedMessage);
        assert.equal(keccak256(sent.encodedMessage), sent.messageId, "the message id is the keccak256 of the encoded message");
      } else {
        assert.equal(sent.encodedMessage, undefined);
      }
    });

    it("increases the sequence number with every message", async () => {
      const first = await svm.send({ sender: wallet, receiver: EVM_RECEIVER, data: Buffer.from("one") });
      const second = await svm.send({ sender: wallet, receiver: EVM_RECEIVER, data: Buffer.from("two") });
      assert.equal(second.sequenceNumber, first.sequenceNumber + 1n);
      if (ccipVersion === "1.6") assert.equal(second.nonce, first.nonce + 1n);
      assert.notEqual(first.messageId, second.messageId);
    });

    it("sends zero-length data with the default gas limit", async () => {
      const sent = await timed("send-empty", () => svm.send({ sender: wallet, receiver: EVM_RECEIVER }));
      assert.equal(sent.data.length, 0);
      assert.equal(sent.gasLimit, 200_000n);
    });

    it("sends from the harness payer, and a wallet with no SOL fails until it is funded", async () => {
      const payerSent = await svm.send({ sender: svm.payer, receiver: EVM_RECEIVER, data: Buffer.from("payer") });
      assert.deepEqual(payerSent.sender, svm.payer.publicKey.toBytes());
      const fresh = Keypair.generate();
      const unfunded = await svm.send({ sender: fresh, receiver: EVM_RECEIVER, data: Buffer.from("fresh") }).then(
        () => "",
        (error: Error) => error.message,
      );
      console.log(`[svm-result] unfunded sender@${ccipVersion}: ${unfunded}`);
      // 1.6 fails in the Router's fee transfer; 2.0 already in its account resolution, which needs the sender to exist.
      assert.match(unfunded, ccipVersion === "1.6" ? /send failed.*GetFee/ : /account resolution failed.*AccountNotFound/);
      await fund(fresh.publicKey);
      const freshSent = await svm.send({ sender: fresh, receiver: EVM_RECEIVER, data: Buffer.from("fresh") });
      assert.deepEqual(freshSent.sender, fresh.publicKey.toBytes());
    });

    it("sends a token: the balance and the supply go down, and the token fields are decoded", async () => {
      const owner = Keypair.generate();
      await fund(owner.publicKey);
      const account = await svm.mintTokens(token.mint, owner.publicKey, 5n * ONE_TOKEN);
      assert.equal(await svm.tokenBalance(token.mint, owner.publicKey), 5n * ONE_TOKEN);
      const supplyBefore = BigInt((await svm.connection.getTokenSupply(token.mint)).value.amount);

      const sent = await timed("send-token", () =>
        svm.send({ sender: owner, receiver: EVM_RECEIVER, data: Buffer.from("tok"), token: { mint: token.mint, amount: 3n * ONE_TOKEN / 2n } }),
      );
      console.log(`[svm-result] send-token@${ccipVersion}: ${await computeUnits(sent.signature)} compute units`);
      assert.equal(await svm.tokenBalance(token.mint, owner.publicKey), 5n * ONE_TOKEN - 1_500_000_000n);
      assert.equal(BigInt((await svm.connection.getTokenSupply(token.mint)).value.amount), supplyBefore - 1_500_000_000n);
      assert.ok(account);

      assert.ok(sent.token);
      assert.equal(sent.token.mint.toBase58(), token.mint.toBase58());
      assert.equal(sent.token.destToken, EVM_TOKEN);
      assert.equal(sent.token.amount, 1_500_000_000n, "the amount is in mint decimals");
      assert.equal(sent.token.sourcePool.length, 32);
      assert.equal(BigInt("0x" + Buffer.from(sent.token.extraData).toString("hex")), 9n, "extraData is abi.encode(uint8 mintDecimals)");
      assert.equal(sent.token.extraData.length, 32);
      assert.equal(Buffer.from(sent.data).toString(), "tok");
      if (ccipVersion === "2.0") assert.equal(keccak256(sent.encodedMessage!), sent.messageId);
    });

    it("sends a token-only message", async () => {
      const owner = Keypair.generate();
      await fund(owner.publicKey);
      await svm.mintTokens(token.mint, owner.publicKey, ONE_TOKEN);
      const sent = await svm.send({ sender: owner, receiver: EVM_RECEIVER, token: { mint: token.mint, amount: ONE_TOKEN } });
      assert.equal(sent.data.length, 0);
      assert.equal(sent.token?.amount, ONE_TOKEN);
      assert.equal(await svm.tokenBalance(token.mint, owner.publicKey), 0n);
    });

    it("mints tokens on top of an existing balance and into the supply", async () => {
      const owner = Keypair.generate().publicKey;
      const supplyBefore = BigInt((await svm.connection.getTokenSupply(token.mint)).value.amount);
      await svm.mintTokens(token.mint, owner, 10n);
      const account = await svm.mintTokens(token.mint, owner, 5n);
      assert.equal(await svm.tokenBalance(token.mint, owner), 15n);
      assert.equal(BigInt((await svm.connection.getTokenSupply(token.mint)).value.amount), supplyBefore + 15n);
      assert.equal((await svm.connection.getTokenAccountBalance(account)).value.amount, "15");
    });

    it("throws a clear error for a mint that is not linked, and for other misuse", async () => {
      const unlinked = await svm.createBurnMintToken();
      await svm.mintTokens(unlinked.mint, wallet.publicKey, ONE_TOKEN);
      await assert.rejects(
        svm.send({ sender: wallet, receiver: EVM_RECEIVER, token: { mint: unlinked.mint, amount: 1n } }),
        /not linked to an EVM token.*linkToken/,
      );
      await assert.rejects(svm.send({ sender: wallet, receiver: "0x1234" }), /receiver must be a 0x-prefixed 20-byte/);
      await assert.rejects(svm.send({ sender: wallet, receiver: EVM_RECEIVER, gasLimit: -1n }), /gasLimit/);
      await assert.rejects(svm.send({ sender: wallet, receiver: EVM_RECEIVER, data: Buffer.alloc(601) }), /at most 600 bytes/);
      const largest = await svm.send({ sender: wallet, receiver: EVM_RECEIVER, data: Buffer.alloc(600, 7) });
      assert.equal(largest.data.length, 600);
      await assert.rejects(svm.send({ sender: wallet, receiver: EVM_RECEIVER, token: { mint: token.mint, amount: 0n } }), /token\.amount/);
      await assert.rejects(svm.send({ sender: wallet.publicKey as never, receiver: EVM_RECEIVER }), /sender must be a Keypair/);
      await assert.rejects(svm.mintTokens(Keypair.generate().publicKey, wallet.publicKey, 1n), /not a classic SPL Token mint/);
    });

    it("fails with the program's error when Solana rejects the send", async () => {
      await assert.rejects(svm.send({ sender: wallet, receiver: EVM_RECEIVER, gasLimit: 4_000_000n }), /send failed.*MessageGasLimitTooHigh/);
    });

    it("fails with a readable error when the sender holds too few tokens", async () => {
      const owner = Keypair.generate();
      await fund(owner.publicKey);
      await svm.mintTokens(token.mint, owner.publicKey, 1n);
      await assert.rejects(
        svm.send({ sender: owner, receiver: EVM_RECEIVER, token: { mint: token.mint, amount: 2n } }),
        /send failed/,
      );
    });

    it("finds a message by signature", async () => {
      const sent = await svm.send({ sender: wallet, receiver: EVM_RECEIVER, data: Buffer.from("find me") });
      const [found, ...rest] = await svm.sentMessages({ signature: sent.signature });
      assert.equal(rest.length, 0);
      assert.deepEqual(found, sent);
      await assert.rejects(svm.sentMessages({ signature: "1".repeat(64) }), /not found/);
      await assert.rejects(svm.sentMessages({ signature: sent.signature, afterSignature: sent.signature }), /not both/);
    });

    it("finds messages by scanning the Router, oldest first, after a signature", async () => {
      const all = await timed("sentMessages-all", () => svm.sentMessages());
      assert.ok(all.length >= 6, `found ${all.length} messages since start`);
      for (let i = 1; i < all.length; i++) {
        if (all[i].destChainSelector === all[i - 1].destChainSelector) assert.ok(all[i].messageId !== all[i - 1].messageId);
      }

      const marker = await svm.send({ sender: wallet, receiver: EVM_RECEIVER, data: Buffer.from("marker") });
      const a = await svm.send({ sender: wallet, receiver: EVM_RECEIVER, data: Buffer.from("a") });
      const b = await svm.send({ sender: wallet, receiver: EVM_RECEIVER, data: Buffer.from("b") });
      const after = await timed("sentMessages-after", () => svm.sentMessages({ afterSignature: marker.signature }));
      assert.deepEqual(after, [a, b]);
      assert.deepEqual(await svm.sentMessages({ afterSignature: b.signature }), []);
      assert.deepEqual((await svm.sentMessages()).slice(-3), [marker, a, b]);
      await assert.rejects(svm.sentMessages({ afterSignature: "1".repeat(64) }), /not a transaction of the Router/);
    });

    if (ccipVersion === "2.0") {
      it("names the placeholder offramp and the NO_EXECUTION executor of the lane", async () => {
        assert.match(PLACEHOLDER_OFFRAMP_2_0, /^0x[0-9a-f]{40}$/);
        assert.equal(NO_EXECUTION_EXECUTOR.toBytes().slice(0, 4).join(","), [0xeb, 0xa5, 0x17, 0xd2].join(","));
        const sent = await svm.send({ sender: wallet, receiver: EVM_RECEIVER, data: Buffer.from("x") });
        const encoded = Buffer.from(sent.encodedMessage!).toString("hex");
        assert.ok(encoded.includes(PLACEHOLDER_OFFRAMP_2_0.slice(2)), "the encoded message carries the placeholder offramp");
      });
    }
  });
}
