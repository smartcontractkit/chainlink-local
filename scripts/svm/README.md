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
`test/smoke/svm/MessageToSolana.test.ts`. Expected output ends with every test passing, and prints lines such as:

```
[svm-timing] startSvmLocal 342ms
[svm-timing] journey-2 send-to-result 63ms
[svm-result] 1000 CU: compute budget exceeded: used 1000 of 1000 compute units; raise computeUnits
```

## Use it

```ts
const { ethers } = await network.connect();
const simulator = await ethers.deployContract("CCIPLocalSimulator");
const [, router, , , link] = await simulator.configuration();
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

## Timing

Measured on a MacBook (Apple silicon), warm unless noted; two runs.

| Step | Run 1 | Run 2 |
| --- | --- | --- |
| First run, cold program cache: `startSvmLocal()` (includes the download) | 1163 ms | 668 ms |
| `startSvmLocal()`, warm cache | 320 ms | 351 ms |
| One `deliver()` (receiver-only test, first call) | 51 ms | 43 ms |
| Journey 2, from `send` to result | 56 ms | 57 ms |
| `MessageToSolana.test.ts`, whole file | 836 ms | 886 ms |

The cold-cache download time depends on the network.

## What is real and what is simulated

Real:

- The CCIP 2.0 Solana programs, at the pinned release, executing `execute_v2` with the real account resolution,
  CommitteeVerifier signature check, RMN Remote curse check, source-chain and onRamp check, and the receiver's CPI.
- With `ccipVersion: "1.6"`, the CCIP 1.6 programs executing the real `commit` (OCR3 signature check, Merkle root
  stored per source chain, sequence-interval and onRamp checks) and `execute` (transmitter check, Merkle proof of the
  message and its receiver accounts, RMN Remote curse check, the receiver's CPI).
- The EVM side of the send: `CCIPLocalRouter` applies the Router 1.2 and OnRamp 2.0 checks for Solana (extra-args tag,
  3,000,000 compute-unit cap, 255 accounts, no tokens, 30,000-byte payload, 32-byte receiver) and nothing more.
- The OffRamp accepts one onRamp for the EVM source chain, as a live lane does: the router that emitted the first
  routed message. A message from another onRamp fails on Solana with the OffRamp's `InvalidOnrampAddress`.
- Solana decides the outcome: a stray writable-bitmap bit, a receiver that is not a program, or a compute-unit limit
  above 1,400,000 are not rejected by the harness.

Simulated:

- The committee is local: `deliver()` signs the message with keys it generated and the CommitteeVerifier trusts
  them (threshold 1 of 8). There is no commit, no finality wait and no executor or offchain network.
- On 1.6 the commit and execution DONs are local: 4 deterministic signer keys with F = 1 (2 signatures per commit), the
  payer as the only transmitter, no RMN signatures and no price updates (the FeeQuoter is deployed but not initialised).
- There is one EVM source chain (selector 16015286601757825753) and one Solana chain (devnet selector).
- Fees are the router's `setFee` value on the EVM side, with no Solana-side pricing. Token transfers to Solana
  are not supported.
- Surfnet clamps a compute-unit limit above 1,400,000 to 1,400,000, as a validator does, while the EVM send allows
  3,000,000. A message that needs more than 1.4M compute units cannot succeed on real Solana either.
- Until the first routed message, that one onRamp is a placeholder registered at startup, so `deliver()` works
  without an EVM chain. `deliver()` without `onRampAddress` always uses the onRamp the lane currently accepts.
