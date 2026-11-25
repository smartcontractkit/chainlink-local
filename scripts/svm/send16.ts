// Solana -> EVM on a CCIP 1.6 lane: the send setup (FeeQuoter, billing tokens, the EVM destination, RMN event
// authority) and `ccip_send`, the real Router instruction, with its `CCIPMessageSent` event decoded.
//
// A live Router is billed in the token the sender picks; here the fee is native SOL, wrapped by the Router, at the
// prices set below (not live prices). The sender approves the Router's fee billing signer as delegate on its token
// account, and the BurnMint pool burns through the Router, so a token send is the real pool path.

import { createHash } from "node:crypto";
import anchor from "@anchor-lang/core";
import { PublicKey, SystemProgram, TransactionInstruction } from "@solana/web3.js";
import { getAddress } from "ethers";
import { EVM_CHAIN_SELECTOR, pda, programDataAddress, selectorSeed } from "./constants.ts";
import { CCIP_PROGRAMS_1_6 } from "./programs.ts";
import type { SvmRuntime } from "./runtime.ts";
import {
  NATIVE_MINT,
  SendSupport,
  eventDiscriminator,
  readUint256,
  u224,
  type CheckedSend,
  type SvmSentMessage,
} from "./send.ts";
import { TOKEN_PROGRAM, associatedTokenAddress, type TokenSupport } from "./tokens.ts";
import { createStandInMint, sendPacked } from "./trust.ts";
import type { CcipPrograms16 } from "./trust16.ts";

const { BN } = anchor;

const ASSOCIATED_TOKEN_PROGRAM = new PublicKey("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL");
/** `GenericExtraArgsV2` tag, big-endian: `bytes4(keccak256("CCIP EVMExtraArgsV2"))`. */
const GENERIC_EXTRA_ARGS_V2_TAG = 0x181dcf10;
/** `bytes4(keccak256("CCIP ChainFamilySelector EVM"))`. */
const EVM_FAMILY_SELECTOR = Buffer.from("2812d52c", "hex");
const ONE_E18 = new BN("1000000000000000000");
const CPI_EVENT_DISCRIMINATOR = createHash("sha256").update("global:cpi_event").digest().subarray(0, 8);
const MESSAGE_SENT = eventDiscriminator("CCIPMessageSent");

/**
 * Initialises what `ccip_send` needs to the EVM chain: the LINK stand-in mint, the FeeQuoter (wSOL and LINK billing,
 * the EVM destination, prices), the RMN Remote event authority and the EVM destination in the Router.
 */
async function setupSend16(runtime: SvmRuntime, programs: CcipPrograms16): Promise<PublicKey> {
  const authority = runtime.payer.publicKey;
  const router = new PublicKey(CCIP_PROGRAMS_1_6.ccip_router);
  const feeQuoter = new PublicKey(CCIP_PROGRAMS_1_6.fee_quoter);
  const rmnRemote = new PublicKey(CCIP_PROGRAMS_1_6.rmn_remote);
  const config = (program: PublicKey) => pda([Buffer.from("config")], program);
  const billingSigner = pda([Buffer.from("fee_billing_signer")], router);
  const billingConfig = (mint: PublicKey) => pda([Buffer.from("fee_billing_token_config"), mint.toBuffer()], feeQuoter);
  const allowedUpdater = pda([Buffer.from("allowed_price_updater"), authority.toBuffer()], feeQuoter);
  const evmSelector = new BN(EVM_CHAIN_SELECTOR.toString());
  const destChain = pda([Buffer.from("dest_chain"), selectorSeed(EVM_CHAIN_SELECTOR)], feeQuoter);
  const linkMint = await createStandInMint(runtime, 9);

  const billingToken = async (mint: PublicKey) =>
    programs.feeQuoter.methods
      .addBillingTokenConfig({
        enabled: true,
        mint,
        usdPerToken: { value: u224(0n), timestamp: new BN(0) },
        premiumMultiplierWeiPerEth: ONE_E18,
      })
      .accounts({
        config: config(feeQuoter),
        billingTokenConfig: billingConfig(mint),
        tokenProgram: TOKEN_PROGRAM,
        feeTokenMint: mint,
        feeTokenReceiver: associatedTokenAddress(mint, billingSigner),
        authority,
        feeBillingSigner: billingSigner,
        associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM,
        systemProgram: SystemProgram.programId,
      })
      .instruction();

  await sendPacked(runtime, [
    await programs.router.methods
      .setLinkTokenMint(linkMint)
      .accounts({ config: config(router), authority, systemProgram: SystemProgram.programId })
      .instruction(),
    await programs.feeQuoter.methods
      .initialize(new BN("1000000000000000000000"), router)
      .accounts({
        config: config(feeQuoter),
        linkTokenMint: linkMint,
        authority,
        systemProgram: SystemProgram.programId,
        program: feeQuoter,
        programData: programDataAddress(feeQuoter),
      })
      .instruction(),
    await billingToken(NATIVE_MINT),
    await billingToken(linkMint),
    await programs.feeQuoter.methods
      .addDestChain(evmSelector, {
        isEnabled: true,
        laneCodeVersion: { default: {} },
        maxNumberOfTokensPerMsg: 5,
        maxDataBytes: 30_000,
        maxPerMsgGasLimit: 3_000_000,
        destGasOverhead: 300_000,
        destGasPerPayloadByteBase: 16,
        destGasPerPayloadByteHigh: 40,
        destGasPerPayloadByteThreshold: 3000,
        destDataAvailabilityOverheadGas: 100,
        destGasPerDataAvailabilityByte: 16,
        destDataAvailabilityMultiplierBps: 1,
        defaultTokenFeeUsdcents: 50,
        defaultTokenDestGasOverhead: 90_000,
        defaultTxGasLimit: 200_000,
        gasMultiplierWeiPerEth: ONE_E18,
        networkFeeUsdcents: 50,
        gasPriceStalenessThreshold: 0,
        enforceOutOfOrder: false,
        chainFamilySelector: Array.from(EVM_FAMILY_SELECTOR),
      })
      .accounts({ config: config(feeQuoter), destChain, authority, systemProgram: SystemProgram.programId })
      .instruction(),
    await programs.feeQuoter.methods
      .addPriceUpdater(authority)
      .accounts({ allowedPriceUpdater: allowedUpdater, config: config(feeQuoter), authority, systemProgram: SystemProgram.programId })
      .instruction(),
    // Local prices, not live ones: SOL $150, LINK $15, EVM gas 30 gwei at ETH $3,000. Fees only have to be non-zero.
    await programs.feeQuoter.methods
      .updatePrices(
        [
          { sourceToken: NATIVE_MINT, usdPerToken: u224(150n * 10n ** 27n) },
          { sourceToken: linkMint, usdPerToken: u224(15n * 10n ** 27n) },
        ],
        [{ destChainSelector: evmSelector, usdPerUnitGas: u224(9n * 10n ** 13n) }],
      )
      .accounts({ authority, allowedPriceUpdater: allowedUpdater, config: config(feeQuoter) })
      .remainingAccounts([billingConfig(NATIVE_MINT), billingConfig(linkMint), destChain].map((pubkey) => ({ pubkey, isWritable: true, isSigner: false })))
      .instruction(),
    // Without this authority the Router's event CPI into RMN Remote fails with Unauthorized.
    await programs.rmnRemote.methods
      .setEventAuthorities([billingSigner])
      .accounts({ config: config(rmnRemote), authority, systemProgram: SystemProgram.programId })
      .instruction(),
    await programs.router.methods
      .addChainSelector(evmSelector, { laneCodeVersion: { default: {} }, allowedSenders: [], allowListEnabled: false })
      .accounts({
        destChainState: pda([Buffer.from("dest_chain_state"), selectorSeed(EVM_CHAIN_SELECTOR)], router),
        config: config(router),
        authority,
        systemProgram: SystemProgram.programId,
      })
      .instruction(),
  ]);
  return linkMint;
}

export class Sender16 extends SendSupport {
  private readonly programs: CcipPrograms16;
  /** The LINK stand-in the Router and FeeQuoter validate; every send passes its billing config. */
  private readonly linkMint: PublicKey;
  private readonly feeQuoter = new PublicKey(CCIP_PROGRAMS_1_6.fee_quoter);
  private readonly rmnRemote = new PublicKey(CCIP_PROGRAMS_1_6.rmn_remote);

  /** Runs the send setup, then returns the sender. */
  static async create(runtime: SvmRuntime, programs: CcipPrograms16, tokens: TokenSupport): Promise<Sender16> {
    const linkMint = await setupSend16(runtime, programs);
    const sender = new Sender16(runtime, programs, tokens, linkMint);
    await sender.markSetupDone();
    return sender;
  }

  private constructor(runtime: SvmRuntime, programs: CcipPrograms16, tokens: TokenSupport, linkMint: PublicKey) {
    super(runtime, tokens, new PublicKey(CCIP_PROGRAMS_1_6.ccip_router));
    this.programs = programs;
    this.linkMint = linkMint;
  }

  protected async buildSend(send: CheckedSend): Promise<TransactionInstruction> {
    const { feeQuoter, router } = this;
    const config = (program: PublicKey) => pda([Buffer.from("config")], program);
    const billingConfig = (mint: PublicKey) => pda([Buffer.from("fee_billing_token_config"), mint.toBuffer()], feeQuoter);
    const authority = send.sender.publicKey;
    const evmSelector = new BN(EVM_CHAIN_SELECTOR.toString());

    // Receiver: the 20-byte EVM address left-padded to 32. Extra args: tag, gas limit (u128 LE), out-of-order false.
    const receiver = Buffer.alloc(32);
    send.receiver.copy(receiver, 12);
    const extraArgs = Buffer.alloc(21);
    extraArgs.writeUInt32BE(GENERIC_EXTRA_ARGS_V2_TAG, 0);
    extraArgs.writeBigUInt64LE(send.gasLimit, 4);
    const message = {
      receiver,
      data: send.data,
      tokenAmounts: send.token ? [{ token: send.token.mint, amount: new BN(send.token.amount.toString()) }] : [],
      feeToken: PublicKey.default, // zero = native SOL
      extraArgs,
    };
    return this.programs.router.methods
      .ccipSend(evmSelector, message, Buffer.from(send.token ? [0] : []))
      .accounts({
        config: config(router),
        destChainState: pda([Buffer.from("dest_chain_state"), selectorSeed(EVM_CHAIN_SELECTOR)], router),
        nonce: pda([Buffer.from("nonce"), selectorSeed(EVM_CHAIN_SELECTOR), authority.toBuffer()], router),
        authority,
        systemProgram: SystemProgram.programId,
        feeTokenProgram: TOKEN_PROGRAM,
        feeTokenMint: NATIVE_MINT,
        feeTokenUserAssociatedAccount: PublicKey.default,
        feeTokenReceiver: associatedTokenAddress(NATIVE_MINT, this.billingSigner),
        feeBillingSigner: this.billingSigner,
        feeQuoter,
        feeQuoterConfig: config(feeQuoter),
        feeQuoterDestChain: pda([Buffer.from("dest_chain"), selectorSeed(EVM_CHAIN_SELECTOR)], feeQuoter),
        feeQuoterBillingTokenConfig: billingConfig(NATIVE_MINT),
        feeQuoterLinkTokenConfig: billingConfig(this.linkMint),
        rmnRemote: this.rmnRemote,
        rmnRemoteCurses: pda([Buffer.from("curses")], this.rmnRemote),
        rmnRemoteConfig: config(this.rmnRemote),
      })
      .remainingAccounts(
        send.token ? this.tokens.sendAccounts16(send.token.mint, authority).map((account) => ({ ...account, isSigner: false })) : [],
      )
      .instruction();
  }

  /** The event is an inner instruction of RMN Remote: `cpi_event` discriminator | u32 length | event (discriminator + Borsh). */
  protected decodeEvent(programId: PublicKey, data: Buffer, signature: string): SvmSentMessage | undefined {
    if (!programId.equals(this.rmnRemote) || data.length < 12 || !data.subarray(0, 8).equals(CPI_EVENT_DISCRIMINATOR)) return undefined;
    const event = data.subarray(12, 12 + data.readUInt32LE(8));
    if (!event.subarray(0, 8).equals(MESSAGE_SENT)) return undefined;
    // Event fields: dest_chain_selector u64, sequence_number u64, then the message. (Anchor camel-cases type names.)
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const m: any = this.programs.router.coder.types.decode("svm2AnyRampMessage", event.subarray(8 + 16));

    const [tokenAmount] = m.tokenAmounts as { sourcePoolAddress: PublicKey; destTokenAddress: Uint8Array; extraData: Uint8Array; amount: { leBytes: number[] } }[];
    let token: SvmSentMessage["token"];
    if (tokenAmount) {
      const destToken = getAddress("0x" + Buffer.from(tokenAmount.destTokenAddress).subarray(12).toString("hex"));
      // The event names the EVM token, not the Solana mint: the link made by `linkToken` maps one to the other.
      const mint = this.tokens.linkedMint(destToken);
      if (!mint) throw new Error(`sentMessages: the message of ${signature} carries EVM token ${destToken}, which is not linked to a mint`);
      token = {
        mint,
        sourcePool: tokenAmount.sourcePoolAddress.toBytes(),
        destToken,
        amount: readUint256(tokenAmount.amount.leBytes, "le"),
        extraData: Uint8Array.from(tokenAmount.extraData),
      };
    }
    const extraArgs = Buffer.from(m.extraArgs);
    return {
      ccipVersion: "1.6",
      signature,
      messageId: "0x" + Buffer.from(m.header.messageId).toString("hex"),
      sourceChainSelector: BigInt(m.header.sourceChainSelector.toString()),
      destChainSelector: BigInt(m.header.destChainSelector.toString()),
      sequenceNumber: BigInt(m.header.sequenceNumber.toString()),
      nonce: BigInt(m.header.nonce.toString()),
      sender: m.sender.toBytes(),
      receiver: getAddress("0x" + Buffer.from(m.receiver).subarray(12).toString("hex")),
      data: Uint8Array.from(m.data),
      // GenericExtraArgsV2: 4-byte tag, then the gas limit as a u128 LE.
      gasLimit: readUint256(extraArgs.subarray(4, 20), "le"),
      finality: "0x00000000",
      ...(token && { token }),
    };
  }
}
