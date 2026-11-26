// Solana -> EVM on a CCIP 2.0 lane: the send setup (FeeQuoter, the EVM destination in the Router, the committee
// verifier) and `ccip_send_v2`, the real Router instruction, with its `CCIPMessageSentV2` event decoded.
//
// The accounts of a send come from the Router's own staged `resolve_accounts` (resolver.ts), as for inbound
// execution. Two things stand in for the EVM side, since no EVM chain exists locally:
//  - the destination's OffRamp address (`PLACEHOLDER_OFFRAMP_2_0`), which the Router stores and puts in the message;
//  - the executor: `NO_EXECUTION`, the sentinel a lane uses to say "nobody executes this message for you", so the
//    real Executor program is not initialised. Fees therefore carry no executor cost.

import anchor from "@anchor-lang/core";
import { PublicKey, SystemProgram, TransactionInstruction } from "@solana/web3.js";
import { getAddress } from "ethers";
import { readIdl } from "./artifacts.ts";
import { decodeMessage, decodeTokenTransfer } from "./codec.ts";
import { EVM_CHAIN_SELECTOR, SEEDS, pda, selectorSeed } from "./constants.ts";
import { CCIP_PROGRAMS } from "./programs.ts";
import { resolveAccounts } from "./resolver.ts";
import type { SvmRuntime } from "./runtime.ts";
import { NATIVE_MINT, SendSupport, eventDiscriminator, u224, type CheckedSend, type SvmSentMessage } from "./send.ts";
import { TOKEN_PROGRAM, associatedTokenAddress, type TokenSupport } from "./tokens.ts";
import { sendPacked, type CcipPrograms } from "./trust.ts";

const { BN } = anchor;

/**
 * Address of the EVM OffRamp the local lane names as the destination of Solana-sent messages: 20 fixed bytes, since
 * no EVM chain runs next to the Surfnet. (The inbound placeholders are 0x01..01, the onRamp, and 0x02..02, the sender.)
 */
export const PLACEHOLDER_OFFRAMP_2_0 = "0x" + "03".repeat(20);
/** `NO_EXECUTION_TAG` (`0xeba517d2`) followed by 28 zero bytes, as the 32-byte executor address. */
export const NO_EXECUTION_EXECUTOR = new PublicKey(Buffer.concat([Buffer.from("eba517d2", "hex"), Buffer.alloc(28)]));

/** `GenericExtraArgsV3` tag, big-endian. */
const GENERIC_EXTRA_ARGS_V3_TAG = Buffer.from("a69dd4aa", "hex");
/** `bytes4(keccak256("CCIP ChainFamilySelector EVM"))`. */
const EVM_FAMILY_SELECTOR = Buffer.from("2812d52c", "hex");
const ONE_E18 = new BN("1000000000000000000");
/** Anchor's event-CPI instruction tag: the Router calls itself with the event as instruction data. */
const EVENT_CPI_TAG = Buffer.from("e445a52e51cb9a1d", "hex");
const MESSAGE_SENT_V2 = eventDiscriminator("CCIPMessageSentV2");

const u32le = (n: number): Buffer => {
  const buf = Buffer.alloc(4);
  buf.writeUInt32LE(n);
  return buf;
};

/** The EVM destination: FeeQuoter prices and config, the Router's destination chain, and the verifier the Router signs for. */
async function setupSend20(runtime: SvmRuntime, programs: CcipPrograms): Promise<void> {
  const authority = runtime.payer.publicKey;
  const router = new PublicKey(CCIP_PROGRAMS.ccip_router);
  const feeQuoter = new PublicKey(CCIP_PROGRAMS.fee_quoter);
  const committeeVerifier = new PublicKey(CCIP_PROGRAMS.committee_verifier);
  const config = (program: PublicKey) => pda([Buffer.from(SEEDS.config)], program);
  const eventAuthority = (program: PublicKey) => pda([Buffer.from("__event_authority")], program);
  const billingSigner = pda([Buffer.from("fee_billing_signer")], router);
  const billingConfig = pda([Buffer.from("fee_billing_token_config"), NATIVE_MINT.toBuffer()], feeQuoter);
  const allowedUpdater = pda([Buffer.from("allowed_price_updater"), authority.toBuffer()], feeQuoter);
  const evmSelector = new BN(EVM_CHAIN_SELECTOR.toString());
  const legacyDestChain = pda([Buffer.from("dest_chain"), selectorSeed(EVM_CHAIN_SELECTOR)], feeQuoter);
  const family = Array.from(EVM_FAMILY_SELECTOR);

  await sendPacked(runtime, [
    await programs.feeQuoter.methods
      .addBillingTokenConfig({
        enabled: true,
        mint: NATIVE_MINT,
        usdPerToken: { value: u224(0n), timestamp: new BN(0) },
        premiumMultiplierWeiPerEth: ONE_E18,
      })
      .accounts({
        config: config(feeQuoter),
        billingTokenConfig: billingConfig,
        tokenProgram: TOKEN_PROGRAM,
        feeTokenMint: NATIVE_MINT,
        feeTokenReceiver: associatedTokenAddress(NATIVE_MINT, billingSigner),
        authority,
        feeBillingSigner: billingSigner,
        associatedTokenProgram: new PublicKey("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"),
        systemProgram: SystemProgram.programId,
      })
      .instruction(),
    // The legacy destination config holds the gas price the V2 config reads.
    await programs.feeQuoter.methods
      .addDestChain(evmSelector, {
        isEnabled: true,
        laneCodeVersion: { default: {} },
        maxNumberOfTokensPerMsg: 1,
        maxDataBytes: 30_000,
        maxPerMsgGasLimit: [3_000_000],
        destGasOverhead: [300_000],
        destGasPerPayloadByteBase: [16],
        destGasPerPayloadByteHigh: [40],
        destGasPerPayloadByteThreshold: 3000,
        destDataAvailabilityOverheadGas: [100],
        destGasPerDataAvailabilityByte: 16,
        destDataAvailabilityMultiplierBps: 1,
        defaultTokenFeeUsdcents: 50,
        defaultTokenDestGasOverhead: [90_000],
        defaultTxGasLimit: [200_000],
        gasMultiplierWeiPerEth: ONE_E18,
        networkFee: [50],
        gasPriceStalenessThreshold: 0,
        enforceOutOfOrder: false,
        chainFamilySelector: family,
      })
      .accounts({ config: config(feeQuoter), destChain: legacyDestChain, authority, systemProgram: SystemProgram.programId })
      .instruction(),
    await programs.feeQuoter.methods
      .addPriceUpdater(authority)
      .accounts({ allowedPriceUpdater: allowedUpdater, config: config(feeQuoter), authority, systemProgram: SystemProgram.programId })
      .instruction(),
    // Local prices, not live ones: SOL $150 and EVM gas 30 gwei at ETH $3,000. Fees only have to be non-zero.
    await programs.feeQuoter.methods
      .updatePrices(
        [{ sourceToken: NATIVE_MINT, usdPerToken: u224(150n * 10n ** 27n) }],
        [{ destChainSelector: evmSelector, usdPerUnitGas: u224(9n * 10n ** 13n) }],
      )
      .accounts({ authority, allowedPriceUpdater: allowedUpdater, config: config(feeQuoter) })
      .remainingAccounts([billingConfig, legacyDestChain].map((pubkey) => ({ pubkey, isWritable: true, isSigner: false })))
      .instruction(),
    await programs.feeQuoter.methods
      .upsertDestChainConfigV2({
        chainSelector: evmSelector,
        destChainConfig: {
          isEnabled: true,
          laneCodeVersion: { default: {} },
          maxDataBytes: 30_000,
          maxPerMsgGasLimit: [3_000_000],
          destGasOverhead: [300_000],
          destGasPerPayloadByteBase: [16],
          chainFamilySelector: family,
          defaultTokenFeeUsdCents: 50,
          defaultTokenDestGasOverhead: [90_000],
          defaultTxGasLimit: [200_000],
          networkFee: [50],
          linkFeeMultiplierPercent: 90,
        },
      })
      .accounts({
        config: config(feeQuoter),
        destChain: pda([Buffer.from("dest_chain_v2"), selectorSeed(EVM_CHAIN_SELECTOR)], feeQuoter),
        authority,
        systemProgram: SystemProgram.programId,
        eventAuthority: eventAuthority(feeQuoter),
        program: feeQuoter,
      })
      .instruction(),
    // The verifier (its Router signer is set in trust.ts) is the default one; the executor is NO_EXECUTION.
    await programs.router.methods
      .addDestChainV2({
        newChainSelector: evmSelector,
        destChainConfig: {
          laneCodeVersion: { default: {} },
          addressBytesLength: 20,
          tokenReceiverAllowed: false,
          allowedSenders: [],
          allowListEnabled: false,
          defaultCcvs: [committeeVerifier],
          laneMandatedCcvs: [],
          defaultExecutor: NO_EXECUTION_EXECUTOR,
          offramp: Buffer.from(PLACEHOLDER_OFFRAMP_2_0.slice(2), "hex"),
          messageNetworkFee: [10],
          tokenTransferNetworkFee: [10],
          baseExecutionGasCost: [50_000],
          maxFeePerMessage: [1_000_000],
        },
      })
      .accounts({
        destChainState: pda([Buffer.from("dest_chain_state_v2"), selectorSeed(EVM_CHAIN_SELECTOR)], router),
        config: config(router),
        authority,
        systemProgram: SystemProgram.programId,
        eventAuthority: eventAuthority(router),
        program: router,
      })
      .instruction(),
  ]);
}

export class Sender20 extends SendSupport {
  private readonly programs: CcipPrograms;
  private readonly routerIdl: { instructions: { name: string; discriminator: number[] }[] };

  /** Runs the send setup, then returns the sender. */
  static async create(runtime: SvmRuntime, programs: CcipPrograms, bundleDir: string, tokens: TokenSupport): Promise<Sender20> {
    await setupSend20(runtime, programs);
    const sender = new Sender20(runtime, programs, bundleDir, tokens);
    await sender.markSetupDone();
    return sender;
  }

  private constructor(runtime: SvmRuntime, programs: CcipPrograms, bundleDir: string, tokens: TokenSupport) {
    super(runtime, tokens, new PublicKey(CCIP_PROGRAMS.ccip_router));
    this.programs = programs;
    this.routerIdl = readIdl(bundleDir, "ccip_router") as never;
  }

  protected async buildSend(send: CheckedSend): Promise<TransactionInstruction> {
    const { router } = this;
    // The 32-byte left-padded EVM address; the Router keeps the 20 the destination's `address_bytes_length` asks for.
    const receiver = Buffer.alloc(32);
    send.receiver.copy(receiver, 12);
    // GenericExtraArgsV3: tag, then Borsh { gas_limit u32, finality { flags u16, block_depth u16 }, ccvs [], ccv_args [],
    // executor (zero = the destination's default), executor_args [], token_receiver [], token_args [] }.
    const extraArgs = Buffer.concat([
      GENERIC_EXTRA_ARGS_V3_TAG,
      u32le(Number(send.gasLimit)),
      Buffer.alloc(4),
      u32le(0),
      u32le(0),
      Buffer.alloc(32),
      u32le(0),
      u32le(0),
      u32le(0),
    ]);
    const message = {
      receiver,
      data: send.data,
      tokenAmounts: send.token ? [{ token: send.token.mint, amount: new BN(send.token.amount.toString()) }] : [],
      feeToken: PublicKey.default, // zero = native SOL
      extraArgs,
    };
    const encode = (resolutionMetadata: Uint8Array): Buffer =>
      this.programs.router.coder.instruction.encode("ccipSendV2", {
        params: {
          destChainSelector: new BN(EVM_CHAIN_SELECTOR.toString()),
          message,
          resolutionMetadata: Buffer.from(resolutionMetadata),
        },
      });

    // The caller of the resolution is the sender: the token accounts it names are the sender's.
    const resolved = await resolveAccounts({
      connection: this.runtime.connection,
      programId: router,
      idl: this.routerIdl,
      payer: send.sender,
      config: pda([Buffer.from(SEEDS.config)], router),
      ixData: encode(new Uint8Array(0)),
    });
    return new TransactionInstruction({ programId: router, keys: resolved.accounts, data: encode(resolved.metadata) });
  }

  protected decodeEvent(programId: PublicKey, data: Buffer, signature: string): SvmSentMessage | undefined {
    if (!programId.equals(this.router) || data.length < 16 || !data.subarray(0, 8).equals(EVENT_CPI_TAG)) return undefined;
    if (!data.subarray(8, 16).equals(MESSAGE_SENT_V2)) return undefined;
    // The event coder takes the base64 of discriminator + Borsh fields, as in a "Program data" log.
    const decoded = this.programs.router.coder.events.decode(data.subarray(8).toString("base64"));
    if (decoded?.name !== "ccipMessageSentV2") return undefined;
    const event = decoded.data;
    const encodedMessage = Uint8Array.from(event.encodedMessage);
    const message = decodeMessage(encodedMessage);

    let token: SvmSentMessage["token"];
    if (message.tokenTransfer.length > 0) {
      const transfer = decodeTokenTransfer(message.tokenTransfer);
      token = {
        mint: new PublicKey(transfer.sourceToken),
        sourcePool: transfer.sourcePool,
        destToken: getAddress("0x" + Buffer.from(transfer.destToken).toString("hex")),
        amount: transfer.amount,
        extraData: transfer.extraData,
      };
    }
    const hex = (value: number) => value.toString(16).padStart(4, "0");
    return {
      ccipVersion: "2.0",
      signature,
      messageId: "0x" + Buffer.from(event.messageId).toString("hex"),
      sourceChainSelector: message.sourceChainSelector,
      destChainSelector: message.destChainSelector,
      sequenceNumber: message.messageNumber,
      nonce: 0n,
      sender: message.sender,
      receiver: getAddress("0x" + Buffer.from(message.receiver).toString("hex")),
      data: message.data,
      gasLimit: BigInt(message.ccipReceiveGasLimit),
      finality: "0x" + hex(message.finalityFlags) + hex(message.finalityBlockDepth),
      ...(token && { token }),
      encodedMessage,
    };
  }
}
