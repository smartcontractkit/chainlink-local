# Try the Solana POC

A Solidity contract sends a CCIP message to a Solana program. The message is delivered through the real CCIP 2.0
Solana programs (OffRamp, Router, RMN Remote, FeeQuoter, CommitteeVerifier) running in a local Surfnet.

## Requirements

- Node.js 22.18 or newer (the tests are TypeScript files run by `node --test`).
- macOS or Linux x64.
- The git submodules in `lib/`, which the Solidity build reads: clone with `git clone --recurse-submodules`, or run
  `git submodule update --init --recursive` in an existing checkout. A project that installs `@chainlink/local` from
  npm does not need them.
- The first run downloads the pinned CCIP Solana programs (about 11 MB extracted, SHA-256 verified) into
  `~/.cache/chainlink-local/svm`. Set `CHAINLINK_LOCAL_SVM_ARTIFACTS` to an extracted bundle to skip the download.

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
- The EVM side of the send: `CCIPLocalRouter` applies the Router 1.2 and OnRamp 2.0 checks for Solana (extra-args tag,
  3,000,000 compute-unit cap, 255 accounts, no tokens, 30,000-byte payload, 32-byte receiver) and nothing more.
- The OffRamp accepts one onRamp for the EVM source chain, as a live lane does: the router that emitted the first
  routed message. A message from another onRamp fails on Solana with the OffRamp's `InvalidOnrampAddress`.
- Solana decides the outcome: a stray writable-bitmap bit, a receiver that is not a program, or a compute-unit limit
  above 1,400,000 are not rejected by the harness.

Simulated:

- The committee is local: `deliver()` signs the message with keys it generated and the CommitteeVerifier trusts
  them (threshold 1 of 8). There is no commit, no finality wait and no executor or offchain network.
- There is one EVM source chain (selector 16015286601757825753) and one Solana chain (devnet selector).
- Fees are the router's `setFee` value on the EVM side, with no Solana-side pricing. Token transfers to Solana
  are not supported.
- Surfnet clamps a compute-unit limit above 1,400,000 to 1,400,000, as a validator does, while the EVM send allows
  3,000,000. A message that needs more than 1.4M compute units cannot succeed on real Solana either.
- Until the first routed message, that one onRamp is a placeholder registered at startup, so `deliver()` works
  without an EVM chain. `deliver()` without `onRampAddress` always uses the onRamp the lane currently accepts.
