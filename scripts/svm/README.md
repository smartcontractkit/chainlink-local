# Try the Solana POC

A Solidity contract sends a CCIP message to a Solana program. The message is delivered through the real CCIP Solana
programs running in a local Surfnet: by default the CCIP 2.0 programs (OffRamp, Router, RMN Remote, FeeQuoter,
CommitteeVerifier), or with `ccipVersion: "1.6"` the CCIP 1.6 programs (OffRamp, Router, RMN Remote, FeeQuoter).

## Requirements

- Node.js 22.18 or newer (the tests are TypeScript files run by `node --test`).
- macOS or Linux x64.
- The git submodules in `lib/`, which the Solidity build reads: clone with `git clone --recurse-submodules`, or run
  `git submodule update --init --recursive` in an existing checkout. A project that installs `@chainlink/local` from
  npm does not need them.
- The first run of each CCIP version downloads its pinned Solana programs (SHA-256 verified) into
  `~/.cache/chainlink-local/svm`. Set `CHAINLINK_LOCAL_SVM_ARTIFACTS` (2.0) or `CHAINLINK_LOCAL_SVM_ARTIFACTS_1_6`
  (1.6) to an extracted bundle to skip the download, and `CHAINLINK_LOCAL_SVM_OFFLINE=1` to forbid it.

## CCIP versions

`startSvmLocal({ ccipVersion })` picks the lane. `deliver()` and its result are the same.

| `ccipVersion` | Pinned release | Download |
| --- | --- | --- |
| `"2.0"` (default) | `smartcontractkit/chainlink-ccip-solana` `contracts/v2.1.0` | about 11 MB extracted |
| `"1.6"` | `smartcontractkit/chainlink-ccip` `solana-v1.6.4` | 2.2 MB, about 9 MB extracted |

`svm.ccipVersion` reports the choice. `exampleReceiver({ ccipVersion })` returns that bundle's `test_ccip_receiver`; the
1.6 bundle ships Anchor 0.29 IDLs, so the returned `idl` is converted to the format `anchor.Program` 1.x reads.

On a 1.6 lane `deliver()` plays both DONs: it commits a one-message Merkle root signed by 2 of 4 local OCR3 keys, then
executes the message, both sent by the one transmitter (the payer). Differences from 2.0 you can observe:

- `messageNumber` is ignored. The sequence number of a message is the OffRamp's next expected one.
- `messageId` is a local id (the OffRamp treats the id as opaque), not the EVM-side id.
- `computeUnits` limits the execute transaction; the commit transaction has its own limit.
- A failed commit returns `state: "Failure"` with `error` starting `commit failed:`. A failed execute still leaves the
  root committed, as on a live lane, and the next `deliver()` commits the next sequence number.

## Tokens

`deliver({ token })` mints a token to a Solana wallet through the real BurnMint pool, the way a CCIP token transfer does.
Both lane versions support it, with the same API. Only BurnMint pools and classic SPL Token mints are supported
(no lock-and-release pools, no Token-2022).

```ts
const token = await svm.createBurnMintToken({ decimals: 9 }); // { mint, pool, decimals }; decimals default 9
await svm.linkToken(token, { evmToken: "0x...", evmDecimals: 18 }); // evmPool defaults to a derived address; evmDecimals to 18
svm.linkedMint("0x...");                                          // the mint, or undefined

const wallet = Keypair.generate().publicKey;
await svm.createTokenAccount(token.mint, wallet);                 // the wallet's associated token account (ATA), returned
const result = await svm.deliver({ token: { evmToken: "0x...", amount: 1_500_000_000_000_000_000n, receiver: wallet } });
await svm.tokenBalance(token.mint, wallet);                       // 1_500_000_000n; 0n if the ATA does not exist
```

- `createBurnMintToken` writes the mint with the pool's signer as mint authority, deploys the version's
  `burnmint_token_pool` on the first call, and sets up the pool, the Router's token admin registry and the pool lookup
  table, with the payer as every authority. `linkToken` writes the pool's remote config for the EVM chain (token, pool
  and decimals) and records `evmToken` (case-insensitive) as the token's EVM counterpart. Linking a mint or an EVM token
  twice throws.
- `deliver({ token })` sends `amount`, in the EVM token's smallest units. Without `receiverProgram` the delivery is
  token-only (`receiverAccounts`, `receiverWritableBitmap` and `data` must be left out). With `receiverProgram` the
  tokens and the message arrive in one execution. An `evmToken` that is not linked throws.
- Decimals: the pool converts from the EVM token's decimals to the mint's. 1.5e18 of an 18-decimal token becomes
  1,500,000,000 on a 9-decimal mint. Anything below one Solana unit is dropped, not rounded: 999,999,999 wei mints 0
  and still succeeds, and 1,999,999,999 wei mints 1.
- Receiver token account, the one difference between the versions: on 2.0 the OffRamp creates the receiver's ATA if it
  is missing. On 1.6 the ATA must already exist, as on the live lane, or the execution fails with `AccountNotInitialized`;
  call `createTokenAccount` first. A failed execute still leaves its root committed (see "CCIP versions").
- Compute units: a token delivery measured 170,000 to 255,000 units, against about 50,000 for data only. With a
  `token`, the execution limit is `computeUnits` (the receiver's budget, default 200,000) plus 300,000 for the pool,
  as a live executor covers the token's destination gas overhead on top of the receiver's. `computeUnitsUsed` reports
  the real figure.

## Enable Solana sends on the router

Solana-bound sends are validated by `CCIPLocalSvmLane`, a separate contract that is not built into
`CCIPLocalSimulator`, so EVM-only users do not pay for its size. Register it once; without it a send to Solana reverts
`SvmLaneNotSet()`. Sends to EVM destinations never need it.

```solidity
CCIPLocalRouter(router).setSvmLane(address(new CCIPLocalSvmLane()));
```

```ts
// Hardhat 3: add "@chainlink/local/src/ccip/CCIPLocalSvmLane.sol" and "@chainlink/local/src/ccip/CCIPLocalRouter.sol"
// to solidity.npmFilesToBuild.
const routerContract = await ethers.getContractAt("CCIPLocalRouter", router);
await routerContract.setSvmLane(await ethers.deployContract("CCIPLocalSvmLane"));
```

## Lane version on both sides

A lane has one CCIP version, and both halves must agree. On Solana, `startSvmLocal({ ccipVersion })` picks the programs.
On the EVM side, `router.setSvmLaneVersion(1)` makes `CCIPLocalRouter` apply the CCIP 1.6 send rules to Solana-bound
messages (0 = `V2_0`, the default; `getSvmLaneVersion()` reads it back). On 1.6 the router rejects at send time what the
live 1.6 lane rejects: more than 1,400,000 compute units or 1,280 bytes (payload plus 32 bytes per account and 2
fixed ones), a writable bitmap with bits beyond the accounts (`InvalidSVMExtraArgsWritableBitmap`), more than 64
accounts, accounts with a zero receiver. The 2.0 limits are 3,000,000 compute units and 30,000 bytes. `routeToSvm` reads the
router's version from the receipt's provider and throws if it differs from `svm.ccipVersion`.

```ts
await router.setSvmLaneVersion(1); // V1_6
const svm = await startSvmLocal({ ccipVersion: "1.6" });
const receiver = await exampleReceiver({ ccipVersion: "1.6" });
// deploy and initialise the receiver as above, then send and route exactly as for 2.0
const [result] = await routeToSvm(svm, receipt);
```

## Run it

```sh
git submodule update --init --recursive && npm ci && npm run test:svm
```

It compiles the Solidity contracts, builds `dist/svm`, then runs the unit tests and the smoke tests, which include
`test/smoke/svm/MessageToSolana.test.ts`. The smoke tests run once per lane version, and timing lines carry the version
as a suffix. Expected output ends with every test passing, and prints lines such as:

```
[svm-timing] startSvmLocal@2.0 342ms
[svm-timing] journey-2 send-to-result@2.0 62ms
[svm-timing] startSvmLocal@1.6 173ms
[svm-timing] journey-2 send-to-result@1.6 55ms
[svm-timing] journey-3 token-only send-to-result@2.0 80ms
[svm-result] BnM token-only@2.0: 168488 compute units
[svm-result] 1000 CU: compute budget exceeded: used 1000 of 1000 compute units; raise computeUnits
```

## Use it

```ts
const { ethers } = await network.connect();
const simulator = await ethers.deployContract("CCIPLocalSimulator");
const [, router, , , link] = await simulator.configuration();
await (await ethers.getContractAt("CCIPLocalRouter", router)).setSvmLane(await ethers.deployContract("CCIPLocalSvmLane"));
const sender = await ethers.deployContract("SvmMessageSender", [router, link]);

const svm = await startSvmLocal();
await svm.deployProgram(receiverSoPath, receiverProgramId);

const extraArgs = svmExtraArgs({ computeUnits: 200_000, accounts, writableBitmap: 0b11n });
const receipt = await (await sender.send(16423721717087811551n, receiverProgramId.toBytes(), "0x68656c6c6f", extraArgs, ethers.ZeroAddress)).wait();
const [result] = await routeToSvm(svm, receipt); // { state: "Success" | "Failure", error?, evmMessageId, ... }
svm.stop();
```

`exampleReceiver()` returns `{ programId, programPath, idl }` for `test_ccip_receiver`, the stand-in receiver program
shipped in the pinned CCIP Solana bundle (downloaded on first use). Pass `programPath` and `programId` to
`svm.deployProgram`, and `idl` to `new anchor.Program(idl as never, provider)`. It does not deploy or initialize
anything, and your own program replaces it in a real project.

## Tokens from Solidity

A Solana-bound `ccipSend` may carry one ERC20 (`SvmMessageSender.sendToken` in `src/test/ccip/` is a minimal sender; the
sender approves the router for the amount). The router pulls the token after the fee and emits `SvmMessageSent` with
`token` and `tokenAmount` (both zero without a token); the wallet that receives it on Solana is
`extraArgs.tokenReceiver`. The router does not know which tokens exist on Solana, so link the EVM token before routing:

```ts
const [, router, , , , ccipBnM] = await simulator.configuration();   // CCIP-BnM; BurnMintERC677Helper.drip() mints one
const token = await svm.createBurnMintToken();
await svm.linkToken(token, { evmToken: ccipBnM });                    // routeToSvm throws for an unlinked token
const extraArgs = svmExtraArgs({ computeUnits: 0, accounts: [], writableBitmap: 0n, tokenReceiver: wallet });
const receipt = await (await sender.sendToken(selector, new Uint8Array(32), "0x", extraArgs, ethers.ZeroAddress, ccipBnM, amount)).wait();
const [result] = await routeToSvm(svm, receipt);
await svm.tokenBalance(token.mint, wallet);                           // amount converted to the mint's decimals
```

- A zero `receiver` is a token-only message: no program runs and `computeUnits` is 0 (a 1.6 lane requires it for a zero
  receiver). A program as `receiver` delivers the tokens and the data together, with `computeUnits` as the receiver's
  budget; the token overhead comes on top.
- On 1.6 the receiver's token account must exist (`svm.createTokenAccount(mint, wallet)`), or the delivery returns
  `Failure` with `AccountNotInitialized`, as on the live lane. On 2.0 the OffRamp creates it.
- 2.0 accepts a zero `tokenReceiver` at send time (as OnRamp 2.0 does) and the OffRamp mints to the token account of the
  all-zero address, where nobody can spend the tokens. 1.6 rejects it at send time (`InvalidTokenReceiver`).

## Timing

Measured on a MacBook (Apple silicon), warm cache unless noted; ranges over several runs.

| Step | CCIP 2.0 | CCIP 1.6 |
| --- | --- | --- |
| First run, cold program cache: `startSvmLocal()` (includes the download) | 668–1163 ms | not measured |
| `startSvmLocal()` | 320–401 ms | 161–182 ms |
| One `deliver()` (receiver-only test, first call) | 39–51 ms | 33–41 ms |
| Journey 2, from `send` to result | 56–65 ms | 52–56 ms |
| `MessageToSolana.test.ts`, whole file | 836–1096 ms | 1844 ms |

A 1.6 `deliver()` sends two transactions (commit, then execute) and is still about as fast as 2.0. The cold-cache
download time depends on the network.

## What is real and what is simulated

Real:

- The CCIP 2.0 Solana programs, at the pinned release, executing `execute_v2` with the real account resolution,
  CommitteeVerifier signature check, RMN Remote curse check, source-chain and onRamp check, and the receiver's CPI.
- With `ccipVersion: "1.6"`, the CCIP 1.6 programs executing the real `commit` (OCR3 signature check, Merkle root
  stored per source chain, sequence-interval and onRamp checks) and `execute` (transmitter check, Merkle proof of the
  message and its receiver accounts, RMN Remote curse check, the receiver's CPI).
- The EVM side of the send, through `CCIPLocalRouter` and its `CCIPLocalSvmLane`:
  - 2.0 lane (default): the Router 1.2 and OnRamp 2.0 checks for Solana (extra-args tag, 3,000,000 compute-unit cap,
    255 accounts, no tokens, 30,000-byte payload, 32-byte receiver) and nothing more.
  - 1.6 lane (`setSvmLaneVersion(1)`): the Router 1.2, OnRamp 1.6.0 and FeeQuoter 2.0.0 checks of the live mainnet
    Ethereum -> Solana lane, in its order and with its errors: 1,400,000 compute units, 1,280 bytes (payload plus 32
    bytes per account and 2 fixed ones), at most 64 accounts, the writable bitmap, no accounts for a zero receiver, a
    token receiver when tokens are sent, one token at most.
- The OffRamp accepts one onRamp for the EVM source chain, as a live lane does: the router that emitted the first
  routed message. A message from another onRamp fails on Solana: on 2.0 with the OffRamp's `InvalidOnrampAddress` at
  execution, on 1.6 with `OnrampNotConfigured` at commit.
- Solana decides the outcome of anything the EVM side lets through: on 2.0 a stray writable-bitmap bit, a receiver
  that is not a program, or a compute-unit limit above 1,400,000 are not rejected by the harness.

Simulated:

- On 2.0 the committee is local: `deliver()` signs the message with keys it generated and the CommitteeVerifier trusts
  them (threshold 1 of 8). There is no commit, no finality wait and no executor or offchain network.
- On 1.6 the commit and execution DONs are local: 4 deterministic signer keys with F = 1 (2 signatures per commit), the
  payer as the only transmitter, no RMN signatures and no price updates (the FeeQuoter is deployed but not initialised).
- There is one EVM source chain (selector 16015286601757825753) and one Solana chain (devnet selector).
- Fees are the router's `setFee` value on the EVM side, with no Solana-side pricing.
- Tokens: the Solana side of a transfer is real (see "Tokens"); the EVM side is the router pulling the token and
  emitting the event (see "Tokens from Solidity"), with no EVM pool, so nothing is burned on the EVM side. There is no
  rate limit on the pool and no pool-side attestation.
- Surfnet clamps a compute-unit limit above 1,400,000 to 1,400,000, as a validator does, while a 2.0 EVM send allows
  3,000,000. A message that needs more than 1.4M compute units cannot succeed on real Solana either.
- Until the first routed message, that one onRamp is a placeholder registered at startup, so `deliver()` works
  without an EVM chain. `deliver()` without `onRampAddress` always uses the onRamp the lane currently accepts.
