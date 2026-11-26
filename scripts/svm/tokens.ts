// Tokens on the local Solana chain: a real SPL mint operated by the real CCIP BurnMint pool, registered in the real
// Router's token admin registry, so that a CCIP delivery mints the tokens to the receiver through the OffRamp.
//
// Both lanes deploy the same pool program id (`burnmint_token_pool`) from their own bundle. Setup follows what a
// live token does: the pool becomes the mint authority; the pool, the Router registry and a pool lookup table
// (the 10 accounts the OffRamp expects, in a fixed order) are initialised with the payer as every authority; the
// pool's remote config for the EVM chain names the EVM token, its pool and its decimals.
//
// Classic SPL Token only (no Token-2022), BurnMint pools only (no lock-and-release).

import anchor from "@anchor-lang/core";
import { Keypair, PublicKey, SystemProgram } from "@solana/web3.js";
import { keccak256 } from "ethers";
import { readIdl, readProgram, type CcipVersion } from "./artifacts.ts";
import { EVM_CHAIN_SELECTOR, SEEDS, pda, programDataAddress, selectorSeed } from "./constants.ts";
import { writeLookupTable } from "./execution.ts";
import { convertLegacyIdl } from "./legacyIdl.ts";
import { programIds } from "./programs.ts";
import type { SvmRuntime } from "./runtime.ts";
import { sendPacked, type AnchorProgram } from "./trust.ts";

const { AnchorProvider, BN, Program, Wallet } = anchor;

/** Program id of the BurnMint pool in both bundles (the binaries differ per version). */
export const BURNMINT_POOL_PROGRAM = new PublicKey("41FGToCmdaWa1dgZLKFAjvmx6e6AjVTX7SVRibvsMGVB");
export const TOKEN_PROGRAM = new PublicKey("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
const ASSOCIATED_TOKEN_PROGRAM = new PublicKey("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL");
const DEFAULT_MINT_DECIMALS = 9;
const DEFAULT_EVM_DECIMALS = 18;
const MINT_ACCOUNT_BYTES = 82;
/** `supply` follows the 36 bytes of the optional mint authority in the SPL mint layout. */
const MINT_SUPPLY_OFFSET = 36;
const MAX_UINT64 = (1n << 64n) - 1n;

/** A token made by `createBurnMintToken`. */
export interface BurnMintToken {
  mint: PublicKey;
  /** The BurnMint pool program, shared by all tokens of the local chain. */
  pool: PublicKey;
  decimals: number;
}

export interface LinkTokenOptions {
  /** Address of the token on the EVM chain (`0x` + 40 hex characters). */
  evmToken: string;
  /** Address of the EVM token pool. Default: a 20-byte address derived from `evmToken`. */
  evmPool?: string;
  /** Decimals of the EVM token. Default 18. */
  evmDecimals?: number;
}

/** What `deliver()` sends: `amount` of a linked EVM token, in the EVM token's smallest units, minted to `receiver`. */
export interface DeliverToken {
  evmToken: string;
  amount: bigint;
  /** Wallet that receives the tokens, in its associated token account. */
  receiver: PublicKey;
}

/** A `DeliverToken` resolved against the linked token: the bytes that go into the delivered message. */
export interface ResolvedToken {
  mint: PublicKey;
  /** 20 raw bytes, as the pool's remote config holds them. */
  evmToken: Buffer;
  evmPool: Buffer;
  evmDecimals: number;
  amount: bigint;
  receiver: PublicKey;
}

interface TokenState {
  mint: PublicKey;
  decimals: number;
  lookupTable: PublicKey;
  linked: boolean;
}

/** Types the 1.6 pool IDL references but omits (external crates). Layouts from the 1.6.4 sources; unused ones are empty. */
const POOL_1_6_MISSING_TYPES = [
  { name: "RemoteAddress", type: { kind: "struct", fields: [{ name: "address", type: "bytes" }] } },
  {
    name: "RemoteConfig",
    type: {
      kind: "struct",
      fields: [
        { name: "poolAddresses", type: { vec: { defined: "RemoteAddress" } } },
        { name: "tokenAddress", type: { defined: "RemoteAddress" } },
        { name: "decimals", type: "u8" },
      ],
    },
  },
  {
    name: "RateLimitConfig",
    type: {
      kind: "struct",
      fields: [
        { name: "enabled", type: "bool" },
        { name: "capacity", type: "u64" },
        { name: "rate", type: "u64" },
      ],
    },
  },
  ...["BaseConfig", "BaseChain", "RateLimitTokenBucket", "LockOrBurnInV1", "LockOrBurnOutV1", "ReleaseOrMintInV1", "ReleaseOrMintOutV1"].map(
    (name) => ({ name, type: { kind: "struct", fields: [] } }),
  ),
];

export function associatedTokenAddress(mint: PublicKey, owner: PublicKey): PublicKey {
  return pda([owner.toBuffer(), TOKEN_PROGRAM.toBuffer(), mint.toBuffer()], ASSOCIATED_TOKEN_PROGRAM);
}

/** `abi.encode(uint8 decimals)`: the extra data a source pool attaches to a transfer. */
export function encodeDecimals(decimals: number): Buffer {
  return Buffer.concat([Buffer.alloc(31), Buffer.from([decimals])]);
}

export function parseEvmAddress(what: string, value: unknown): Buffer {
  if (typeof value !== "string" || !/^0x[0-9a-fA-F]{40}$/.test(value)) {
    throw new Error(`${what} must be a 0x-prefixed 20-byte hex address, got ${JSON.stringify(value)}`);
  }
  return Buffer.from(value.slice(2), "hex");
}

function checkDecimals(what: string, value: number): void {
  if (!Number.isInteger(value) || value < 0 || value > 255) throw new Error(`${what} must be an integer in 0..255, got ${value}`);
}

export interface TokenSupportContext {
  runtime: SvmRuntime;
  ccipVersion: CcipVersion;
  bundleDir: string;
  /** Anchor client of the deployed Router (converted IDL on 1.6). */
  router: AnchorProgram;
  offRamp: PublicKey;
}

export class TokenSupport {
  private readonly context: TokenSupportContext;
  private readonly ids: Record<string, PublicKey>;
  private readonly tokens = new Map<string, TokenState>();
  private readonly links = new Map<string, ResolvedLink>();
  private poolProgram: AnchorProgram | undefined;
  private poolReady: Promise<void> | undefined;

  constructor(context: TokenSupportContext) {
    this.context = context;
    this.ids = Object.fromEntries(Object.entries(programIds(context.ccipVersion)).map(([name, id]) => [name, new PublicKey(id)]));
  }

  async createBurnMintToken(options: { decimals?: number } = {}): Promise<BurnMintToken> {
    const decimals = options.decimals ?? DEFAULT_MINT_DECIMALS;
    checkDecimals("createBurnMintToken: decimals", decimals);
    const { runtime } = this.context;
    const payer = runtime.payer.publicKey;
    const pool = await this.pool();
    const mint = Keypair.generate().publicKey;
    const a = this.addresses(mint);

    // The mint, with the pool's signer PDA as mint authority from the start (what `set_authority` would do),
    // and the pool's own token account.
    const mintData = Buffer.alloc(MINT_ACCOUNT_BYTES);
    mintData.writeUInt32LE(1, 0); // mint authority: Some
    a.poolSigner.toBuffer().copy(mintData, 4);
    mintData[44] = decimals;
    mintData[45] = 1; // is_initialized
    await runtime.setAccount(mint, {
      lamports: await runtime.connection.getMinimumBalanceForRentExemption(MINT_ACCOUNT_BYTES),
      owner: TOKEN_PROGRAM,
      data: mintData,
    });
    await runtime.setTokenAccount(a.poolSigner, mint, { amount: 0 });

    // The pool lookup table: the exact order the OffRamp expects, the table itself first. Indexes 4 (pool token
    // account) and 7 (mint) are the writable ones.
    const lookupTableKey = Keypair.generate().publicKey;
    await writeLookupTable(
      runtime,
      [lookupTableKey, a.registry, BURNMINT_POOL_PROGRAM, a.poolState, a.poolTokenAccount, a.poolSigner, TOKEN_PROGRAM, mint, a.feeTokenConfig, a.routerPoolSigner],
      lookupTableKey,
    );

    const { router } = this.context;
    await sendPacked(runtime, [
      await pool.methods
        .initialize()
        .accounts({ state: a.poolState, mint, authority: payer, systemProgram: SystemProgram.programId, program: BURNMINT_POOL_PROGRAM, programData: programDataAddress(BURNMINT_POOL_PROGRAM), config: a.poolConfig })
        .instruction(),
      await router.methods
        .ccipAdminProposeAdministrator(payer)
        .accounts({ config: a.routerConfig, tokenAdminRegistry: a.registry, mint, authority: payer, systemProgram: SystemProgram.programId })
        .instruction(),
      await router.methods
        .acceptAdminRoleTokenAdminRegistry()
        .accounts({ config: a.routerConfig, tokenAdminRegistry: a.registry, mint, authority: payer })
        .instruction(),
      await router.methods
        .setPool(Buffer.from([4, 7]))
        .accounts({ config: a.routerConfig, tokenAdminRegistry: a.registry, mint, poolLookuptable: lookupTableKey, authority: payer })
        .instruction(),
    ]);
    this.tokens.set(mint.toBase58(), { mint, decimals, lookupTable: lookupTableKey, linked: false });
    return { mint, pool: BURNMINT_POOL_PROGRAM, decimals };
  }

  async linkToken(token: { mint: PublicKey }, options: LinkTokenOptions): Promise<void> {
    const state = this.tokens.get(token?.mint?.toBase58());
    if (!state) throw new Error("linkToken: the mint was not created by createBurnMintToken on this chain");
    const evmToken = parseEvmAddress("linkToken: evmToken", options.evmToken);
    const evmPool =
      options.evmPool === undefined
        ? Buffer.from(keccak256(Buffer.concat([Buffer.from("chainlink-local-svm:evm-pool:"), evmToken])).slice(2, 42), "hex")
        : parseEvmAddress("linkToken: evmPool", options.evmPool);
    const evmDecimals = options.evmDecimals ?? DEFAULT_EVM_DECIMALS;
    checkDecimals("linkToken: evmDecimals", evmDecimals);
    const key = options.evmToken.toLowerCase();
    if (state.linked) throw new Error(`linkToken: mint ${state.mint.toBase58()} is already linked to an EVM token`);
    if (this.links.has(key)) throw new Error(`linkToken: ${key} is already linked to mint ${this.links.get(key)!.mint.toBase58()}`);

    const pool = await this.pool();
    const payer = this.context.runtime.payer.publicKey;
    const a = this.addresses(state.mint);
    const selector = new BN(EVM_CHAIN_SELECTOR.toString());
    const disabled = { enabled: false, capacity: new BN(0), rate: new BN(0) };
    await sendPacked(this.context.runtime, [
      await pool.methods
        .initChainRemoteConfig(selector, state.mint, { poolAddresses: [], tokenAddress: { address: Buffer.concat([Buffer.alloc(12), evmToken]) }, decimals: evmDecimals })
        .accounts({ state: a.poolState, chainConfig: a.chainConfig, authority: payer, systemProgram: SystemProgram.programId })
        .instruction(),
      await pool.methods
        .appendRemotePoolAddresses(selector, state.mint, [{ address: evmPool }])
        .accounts({ state: a.poolState, chainConfig: a.chainConfig, authority: payer, systemProgram: SystemProgram.programId })
        .instruction(),
      await pool.methods
        .setChainRateLimit(selector, state.mint, disabled, disabled)
        .accounts({ state: a.poolState, chainConfig: a.chainConfig, authority: payer })
        .instruction(),
    ]);
    state.linked = true;
    this.links.set(key, { mint: state.mint, evmToken, evmPool, evmDecimals });
  }

  linkedMint(evmToken: string): PublicKey | undefined {
    return this.links.get(String(evmToken).toLowerCase())?.mint;
  }

  /** Creates the associated token account of `owner` for `mint` (empty), or returns the existing one untouched. */
  async createTokenAccount(mint: PublicKey, owner: PublicKey): Promise<PublicKey> {
    const account = associatedTokenAddress(mint, owner);
    if (!(await this.context.runtime.connection.getAccountInfo(account))) {
      await this.context.runtime.setTokenAccount(owner, mint, { amount: 0 });
    }
    return account;
  }

  /** Balance of `owner`'s associated token account for `mint`, in the mint's smallest units. 0n when it does not exist. */
  async tokenBalance(mint: PublicKey, owner: PublicKey): Promise<bigint> {
    const { connection } = this.context.runtime;
    const account = associatedTokenAddress(mint, owner);
    if (!(await connection.getAccountInfo(account))) return 0n;
    return BigInt((await connection.getTokenAccountBalance(account)).value.amount);
  }

  /** Whether `mint` is connected to an EVM token, which a send needs for its destination token address. */
  isLinked(mint: PublicKey): boolean {
    return this.tokens.get(mint?.toBase58())?.linked === true;
  }

  /**
   * Adds `amount` to the associated token account of `owner` (created if needed) and to the mint's supply: a burn
   * needs the supply to cover it, and the token-account cheatcode does not touch the supply. Returns the account.
   */
  async mintTokens(mint: PublicKey, owner: PublicKey, amount: bigint): Promise<PublicKey> {
    if (!(mint instanceof PublicKey) || !(owner instanceof PublicKey)) throw new Error("mintTokens: mint and owner must be PublicKeys");
    if (typeof amount !== "bigint" || amount < 0n || amount > MAX_UINT64) {
      throw new Error(`mintTokens: amount must be a bigint in 0..2^64-1, got ${String(amount)}`);
    }
    const { runtime } = this.context;
    const mintAccount = await runtime.connection.getAccountInfo(mint);
    if (!mintAccount?.owner.equals(TOKEN_PROGRAM) || mintAccount.data.length !== MINT_ACCOUNT_BYTES) {
      throw new Error(`mintTokens: ${mint.toBase58()} is not a classic SPL Token mint on this chain`);
    }
    const supply = mintAccount.data.readBigUInt64LE(MINT_SUPPLY_OFFSET) + amount;
    const balance = (await this.tokenBalance(mint, owner)) + amount;
    if (supply > MAX_UINT64 || balance > MAX_UINT64) throw new Error("mintTokens: the amount overflows the supply of the mint");
    await runtime.setTokenAccount(owner, mint, { amount: balance });
    const data = Buffer.from(mintAccount.data);
    data.writeBigUInt64LE(supply, MINT_SUPPLY_OFFSET);
    await runtime.setAccount(mint, { data });
    return associatedTokenAddress(mint, owner);
  }

  /**
   * CCIP 1.6: the 13 accounts `ccip_send` takes after its fixed ones for one token, in the order the Router
   * expects: the sender's token account, the FeeQuoter per-chain token config, then the pool's.
   */
  sendAccounts16(mint: PublicKey, sender: PublicKey): { pubkey: PublicKey; isWritable: boolean }[] {
    const a = this.addresses(mint);
    const lookupTable = this.tokens.get(mint.toBase58())!.lookupTable;
    const accounts: [PublicKey, boolean][] = [
      [associatedTokenAddress(mint, sender), true],
      [pda([Buffer.from("per_chain_per_token_config"), selectorSeed(EVM_CHAIN_SELECTOR), mint.toBuffer()], this.ids.fee_quoter), false],
      [a.chainConfig, true],
      [lookupTable, false],
      [a.registry, false],
      [BURNMINT_POOL_PROGRAM, false],
      [a.poolState, false],
      [a.poolTokenAccount, true],
      [a.poolSigner, false],
      [TOKEN_PROGRAM, false],
      [mint, true],
      [a.feeTokenConfig, false],
      [a.routerPoolSigner, false],
    ];
    return accounts.map(([pubkey, isWritable]) => ({ pubkey, isWritable }));
  }

  /** The bytes a delivered message carries for `token`. Throws if the EVM token is not linked. */
  resolve(token: DeliverToken): ResolvedToken {
    const link = this.links.get(String(token.evmToken).toLowerCase());
    if (!link) {
      throw new Error(`deliver: EVM token ${token.evmToken} is not linked to a Solana token; call createBurnMintToken and linkToken first`);
    }
    return { ...link, amount: token.amount, receiver: token.receiver };
  }

  /**
   * CCIP 1.6: the accounts of one token transfer, appended after the messaging accounts. The OffRamp reads the
   * Router registry, the pool lookup table and the fee token config from this list, and calls the pool with it.
   */
  accounts16(token: ResolvedToken, sourceChainSelector: bigint): { pubkey: PublicKey; isWritable: boolean }[] {
    const a = this.addresses(token.mint);
    const lookupTable = this.tokens.get(token.mint.toBase58())!.lookupTable;
    const feeQuoter = this.ids.fee_quoter;
    const tokens: [PublicKey, boolean][] = [
      [pda([Buffer.from("external_token_pools_signer"), BURNMINT_POOL_PROGRAM.toBuffer()], this.context.offRamp), false],
      [associatedTokenAddress(token.mint, token.receiver), true],
      [pda([Buffer.from("per_chain_per_token_config"), selectorSeed(sourceChainSelector), token.mint.toBuffer()], feeQuoter), false],
      [a.chainConfig, true],
      [lookupTable, false],
      [a.registry, false],
      [BURNMINT_POOL_PROGRAM, false],
      [a.poolState, false],
      [a.poolTokenAccount, true],
      [a.poolSigner, false],
      [TOKEN_PROGRAM, false],
      [token.mint, true],
      [a.feeTokenConfig, false],
      [a.routerPoolSigner, false],
    ];
    return tokens.map(([pubkey, isWritable]) => ({ pubkey, isWritable }));
  }

  private addresses(mint: PublicKey) {
    const poolSigner = pda([Buffer.from("ccip_tokenpool_signer"), mint.toBuffer()], BURNMINT_POOL_PROGRAM);
    return {
      poolConfig: pda([Buffer.from(SEEDS.config)], BURNMINT_POOL_PROGRAM),
      poolState: pda([Buffer.from("ccip_tokenpool_config"), mint.toBuffer()], BURNMINT_POOL_PROGRAM),
      poolSigner,
      poolTokenAccount: associatedTokenAddress(mint, poolSigner),
      chainConfig: pda([Buffer.from("ccip_tokenpool_chainconfig"), selectorSeed(EVM_CHAIN_SELECTOR), mint.toBuffer()], BURNMINT_POOL_PROGRAM),
      registry: pda([Buffer.from("token_admin_registry"), mint.toBuffer()], this.ids.ccip_router),
      routerConfig: pda([Buffer.from(SEEDS.config)], this.ids.ccip_router),
      feeTokenConfig: pda([Buffer.from("fee_billing_token_config"), mint.toBuffer()], this.ids.fee_quoter),
      routerPoolSigner: pda([Buffer.from("external_token_pools_signer"), BURNMINT_POOL_PROGRAM.toBuffer()], this.ids.ccip_router),
    };
  }

  /** Deploys the version's BurnMint pool and creates its global config, once, on the first token. */
  private async pool(): Promise<AnchorProgram> {
    this.poolReady ??= this.deployPool().catch((error) => {
      this.poolReady = undefined;
      throw error;
    });
    await this.poolReady;
    return this.poolProgram;
  }

  private async deployPool(): Promise<void> {
    const { runtime, bundleDir, ccipVersion } = this.context;
    await runtime.writeProgram(BURNMINT_POOL_PROGRAM, readProgram(bundleDir, "burnmint_token_pool"));
    await runtime.setProgramAuthority(BURNMINT_POOL_PROGRAM, runtime.payer.publicKey);
    const idl = readIdl(bundleDir, "burnmint_token_pool");
    const provider = new AnchorProvider(runtime.connection, new Wallet(runtime.payer), { commitment: "confirmed" });
    this.poolProgram = new Program(
      (ccipVersion === "1.6" ? convertLegacyIdl(idl, BURNMINT_POOL_PROGRAM.toBase58(), POOL_1_6_MISSING_TYPES) : idl) as never,
      provider,
    );
    await sendPacked(runtime, [
      await this.poolProgram.methods
        .initGlobalConfig(this.ids.ccip_router, this.ids.rmn_remote)
        .accounts({
          config: pda([Buffer.from(SEEDS.config)], BURNMINT_POOL_PROGRAM),
          authority: runtime.payer.publicKey,
          systemProgram: SystemProgram.programId,
          program: BURNMINT_POOL_PROGRAM,
          programData: programDataAddress(BURNMINT_POOL_PROGRAM),
        })
        .instruction(),
    ]);
  }
}

interface ResolvedLink {
  mint: PublicKey;
  evmToken: Buffer;
  evmPool: Buffer;
  evmDecimals: number;
}
