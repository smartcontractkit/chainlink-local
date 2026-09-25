# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Target release: `0.3.0-beta` (V3). This is a **breaking** release: `CCIPLocalSimulatorFork` and the Hardhat 3
JavaScript fork helper now support CCIP 2.0 (CCV-based) lanes, which is the protocol version live testnet and mainnet
lanes run today, alongside the pre-1.6 and 1.6 eras.

#### Support matrix

| Environment | 0.3.x (V3) | 0.2.x |
| --- | --- | --- |
| Foundry (Solidity tests, local + fork) | Supported | Supported |
| Hardhat 3 (Solidity tests, local + fork) | Supported | - |
| Hardhat 3 (JavaScript/TypeScript, `scripts/*.js` helpers) | Supported (ESM, `@nomicfoundation/hardhat-ethers`) | - |
| Hardhat 2 | Not supported: the contracts do not compile (Hardhat 2 cannot resolve the `@openzeppelin/contracts@4.8.3/` style imports, `HH411`) | Supported (pre-1.6 fork routing only) |
| Remix IDE (local mode) | Supported | Supported |

### Dependencies

| Package                   | Version |
| ------------------------- | ------- |
| @chainlink/contracts-ccip | 2.0.0   |
| @chainlink/contracts      | 1.5.0   |
| @openzeppelin/contracts-4.8.3 | npm:@openzeppelin/contracts@4.8.3 |
| @openzeppelin/contracts-5.3.0 | npm:@openzeppelin/contracts@5.3.0 |
| forge-std                 | github:foundry-rs/forge-std#v1.9.4 |

The OpenZeppelin aliases and `forge-std` are now runtime `dependencies` (the shipped sources import them). `hardhat`,
`@nomicfoundation/hardhat-ethers` and `ethers` are optional `peerDependencies`, needed only for the JavaScript helpers.
`engines.node` is `>=22`. `forge-std` is a git dependency (the npm `forge-std` package is stale), so `npm install` needs
access to GitHub.

`lib/chainlink-ccip` is pinned to tag `contracts-ccip-v2.0.0` (`c2c125c27f056db2e98d21501922b6eff5750f36`) in the
gitlink, `.gitmodules` (no `branch = develop`) and `foundry.lock`, so `forge install` and `forge update` resolve it
to the tag.

### Breaking changes

- **`@chainlink/contracts-ccip` 1.6.2 -> 2.0.0.** Upstream CCIP 2.0 moved every finality value from `uint16` block
  confirmations to a `bytes4` `FinalityCodec` config. This changes the on-chain wire format of `GenericExtraArgsV3`
  (`blockConfirmations` -> `requestedFinalityConfig`, base size 17 -> 19 bytes) and of `MessageV1` (`finality`).
  Receivers implement `getCCVsAndFinalityConfig(...)` returning `bytes4 allowedFinalityConfig` instead of
  `getCCVsAndMinBlockDepth(...)` returning `uint16 minBlockDepth`; token pools use `setAllowedFinalityConfig(bytes4)`
  instead of `setMinBlockConfirmations(uint16)`. See the migration guide below.
- **Default `V2VerificationMode` is now `OFFRAMP_DERIVED`** (was `HYBRID`). CCIP 2.0 messages are executed through the
  destination OffRamp's permissionless `execute` with the CCVs it selects (`getCCVsForMessage`), without decoding the
  message locally. `STRICT`, `HYBRID` and `SYNTHETIC_ONLY` remain available through `setV2VerificationMode`.
- **Fork routing is strict by default.** `switchChainAndRouteMessage` (and `executePendingV2Message`) now revert when a
  captured CCIP message cannot be routed to any of the given forks
  (`CCIPLocalSimulatorFork__MessageNotRouted(messageId, reason)`) or does not execute successfully
  (`CCIPLocalSimulatorFork__MessageExecutionFailed(messageId, reason)`, with the decoded revert data, e.g.
  `InvalidRequestedFinality(...)` or the receiver's revert). 0.2.6 to 0.2.9 logged execution failures and carried on, and
  dropped unroutable messages without any output; 0.2.5 and earlier reverted. Call `setStrictRouting(false)` to log and
  record failures instead (see `getMessageStatus`). A 1.6 or 2.0 message to a chain that is not in `forkIds` is not a
  failure: it stays `QUEUED` and is routed by a later `switchChainAndRouteMessage` call that includes its destination
  fork (0.2.x dropped it). Pre-1.6 logs do not name their destination, so route them in a call that includes it.
- **Fast Transfer delivery follows production rules.** OffRamp 2.0 only delivers a Fast Transfer message with data (or a
  non-zero gas limit) to a receiver that opts in through `getCCVsAndFinalityConfig`. A plain `CCIPReceiver` only accepts
  finalized messages, so the OffRamp records the execution as `FAILURE`: routing reverts with
  `InvalidRequestedFinality` in strict mode, or records it as `FAILED`.
- **Fork mode needs `evm_version = "cancun"` or later** (not `paris`/`shanghai`): deployed CCIP 2.0 contracts use Cancun
  opcodes, and `paris` fails with `EvmError: NotActivated`. Set it only for fork tests (see the migration guide), so
  your deployed bytecode is not affected.
- **Foundry >= 1.5.1 is required for fork tests.** forge 1.1.0 panics (`revm journaled_state.rs:402`) when an OffRamp
  2.0 execution records a `FAILURE`.
- **Local mode applies the CCIP 2.0 OnRamp and OffRamp rules.** `CCIPLocalSimulator` now uses `CCIPLocalRouter`
  (same ABI as the upstream `MockCCIPRouter`, which it replaces). `ccipSend` now reverts where production rejects the
  message, with the production error:
  - `InvalidRequestedFinality(requested, allowed)`: a Fast Transfer message with data or a non-zero gas limit to a
    receiver that does not allow that finality. `RequestedFinalityCanOnlyHaveOneMode`: a malformed finality config.
  - For every message that is not a token-only transfer to an `IAny2EVMMessageReceiverV2` receiver (finalized messages
    included), `getCCVsAndFinalityConfig` is called and validated: its revert, `DuplicateCCVNotAllowed` or
    `InvalidOptionalThreshold` fails the send.
  - `TokenReceiverNotAllowed(destChainSelector)`: a non-empty `GenericExtraArgsV3.tokenReceiver` (rejected on EVM lanes).
  - `CanOnlySendOneTokenPerMessage` (more than one token) and `CannotSendZeroTokens` (a zero amount).
  - `MessageGasLimitTooHigh`: a `GenericExtraArgsV2` / `EVMExtraArgsV1` gas limit above `type(uint32).max` (the upstream
    mock truncated it to 32 bits; production rejects it against the lane's `uint32` `maxPerMsgGasLimit`).

  ExtraArgs shorter than 4 bytes are now treated as empty (default gas limit), as in production, instead of reverting
  `InvalidExtraArgsTag`. **Local `messageId`s are now unique per send** (they include a nonce, the sender and the
  destination), so IDs differ from earlier versions and identical sends no longer collide.
- **`src/vendor/**` was removed** (70 files: vendored OpenZeppelin 4.7.3 / 4.8.3 / 5.0.2, `MockRouter`,
  `BurnMintERC677` and shared Chainlink contracts). Sources import `@openzeppelin/contracts@4.8.3/...`,
  `@openzeppelin/contracts@5.3.0/...` and `@chainlink/contracts(-ccip)` instead; `CCIPLocalSimulator`'s `AccessControl`
  support now uses OpenZeppelin 5.3.0 (was 5.0.2). Imports of `@chainlink/local/src/vendor/...` must move to those
  packages.
- **`Register` keeps its built-in network details in code.** `getNetworkDetails`, `setNetworkDetails` and
  `NetworkDetails` are unchanged. The details are returned by a generated pure function instead of being written to
  storage in the constructor, and `CCIPLocalSimulatorFork` places its `Register` with `vm.etch`. Code that read
  `Register` storage slots directly breaks.
- **`Register` data is regenerated from the CCIP directory API** (`https://docs.chain.link/api/ccip/v1`, Sep 2026):
  134 chains (was 148). Router addresses are unchanged for every chain in both versions.
  - `wrappedNativeAddress` changes on 17 chains. The generator used the first non-LINK fee token, which was GHO on
    e.g. Ethereum, Ethereum Sepolia, Arbitrum One, Arbitrum Sepolia and Base, and a bridged WETH on Monad Testnet and
    Plasma Testnet; it now picks the wrapped native token (e.g. WETH, WAVAX, WMON). It is `address(0)` on Stable and
    Botanix, where the API lists no unambiguous wrapped native token.
  - Removed (no longer in the API, or without fee tokens): Blast, Blast Sepolia, Polygon zkEVM, Polygon zkEVM Cardona,
    Scroll Sepolia, Mint, Mint Sepolia, Mind Network, Mind Network Testnet, Tac, Everclear, Memento, Memento Testnet,
    Tempo (42429), Corn, Corn Testnet, Janction Testnet, B² Testnet, Kroma Sepolia, Fraxtal Testnet, Botanix Testnet,
    MegaETH Testnet (6342), Superseed Sepolia, Berachain Bartio, Katana Tatara, Taiko Hekla, Bitlayer Testnet and
    Treasure Topaz. `getNetworkDetails` returns an all-zero struct for them; use `setNetworkDetails`.
  - Added: Avalanche, Kaia, Neo X, Robinhood Chain, Robinhood Chain Testnet, HyperEVM Testnet, Tempo Mainnet, Tempo
    Testnet Moderato, MegaETH Testnet (6343), Mova Mainnet, Mova Testnet, 0G Galileo Testnet, Creditcoin Mainnet and
    Ronin Sepolia.
  - Changed on existing chains: 8 LINK addresses, 8 CCIP-BnM addresses and 3 `registryModuleOwnerCustomAddress`es, as
    listed by the API.
- **Hardhat JavaScript helpers target Hardhat 3** (ES modules; they did not load in Hardhat 3 before). Every function
  takes the `NetworkConnection` from `network.connect()` and needs `@nomicfoundation/hardhat-ethers`:
  - `scripts/CCIPLocalSimulatorFork.js`: `getEvm2EvmMessage(receipt)` -> `getCCIPMessages(connection, receipt)`
    (all eras); `routeMessage(routerAddress, message)` -> `routeMessage(connection, routerAddresses, sent, options)`;
    `requestLinkFromTheFaucet(linkAddress, to, amount)` -> `requestLinkFromTheFaucet(connection, linkAddress, to, amount)`.
  - `scripts/data-streams/`: `new MockReportGenerator(initialPrice)` -> `new MockReportGenerator(connection, initialPrice)`;
    `requestLinkFromFaucet` / `requestNativeFromFaucet` take `connection` first.
  - Hardhat 2 JavaScript users: stay on 0.2.x (see the support matrix).
- Removed `IRouterFork.OffRamp`; `IRouterFork.getOffRamps()` returns `CCIPForkAdapterTypes.RouterOffRamp[]`
  (ABI-identical: `(uint64 sourceChainSelector, address offRamp)`).
- Test helpers (not shipped in the npm package, but commonly copied): `EncodeExtraArgsOffchain.encodeV3` takes
  `bytes4 requestedFinalityConfig`, `encodeV3Basic(uint32, bytes4)` takes a finality config and the new
  `encodeV3BasicBlockDepth(uint32, uint16)` takes a block depth; `BasicMessageReceiverWithCCVs.setMinBlockDepth` is
  replaced by `setAllowedFinalityConfig(uint64, bytes4)`.

### Added

- CCIP 2.0 routing in `CCIPLocalSimulatorFork` (adapter architecture in `src/ccip/adapters/`, era detection from the
  emitted event), including the `NO_EXECUTION_ADDRESS` queue
  (`V2ExecutionMode`, `getPendingV2MessageIds`, `executePendingV2Message`).
- `V2VerificationMode.OFFRAMP_DERIVED` (Stefano Magini, magiodev-cll/chainlink-local#3): routes CCIP 2.0 messages
  without the local `MessageV1` codec, so fork tests keep working when the on-chain wire format moves ahead of the
  pinned dependency. CCVs that are owner-configurable verifier resolvers are pointed at a synthetic fork verifier, so
  live lanes work without mocking; `getOffRampForLane`, `setLaneDefaultCCVs` and the `CCVNoOpVerifier` test double
  (`src/test/ccip/CCVNoOpVerifier.sol`) remain available to mock a lane's default CCV instead.
- Hardhat 3 JavaScript fork routing for 1.6 and CCIP 2.0 in `scripts/CCIPLocalSimulatorFork.js` (pre-1.6 kept,
  including `EVM2EVMOffRamp` 1.2 and 1.5), with the same `typeAndVersion`-based OffRamp lookup and CCIP 2.0 execution as
  the Solidity simulator; `CCIP_V2_ROUTERS`; execution failures are thrown with a decoded reason. Tests:
  `npm run hardhat-test-js` (fork) and `npm run js-unit-test` (offline: log decoding for every era from pinned ABIs,
  OffRamp lookup and execution against mocked OffRamps).
- TypeScript declarations for the CCIP JavaScript helper (`scripts/CCIPLocalSimulatorFork.d.ts`, shipped in the npm
  package).
- CI workflow (`.github/workflows/test.yml`): Foundry build, `fmt --check` and non-fork tests, Hardhat Solidity and
  JavaScript unit tests, and an npm-tarball consumer smoke test (`.github/scripts/consumer-smoke.sh`) for Hardhat 3 and
  Foundry (npm). Fork suites run on manual dispatch with RPC secrets.
- `src/ccip/CCIPLocalRouter.sol`, the local-mode router with the CCIP 2.0 OnRamp and OffRamp checks.
- `CCIPLocalSimulatorFork.getMessageStatus(messageId)` returns `NOT_FOUND`, `QUEUED`, `FAILED` or `SUCCESS` and the
  failure reason; `setStrictRouting(bool)` / `getStrictRouting()`.
- Mainnet CCIP 2.0 fork test (Ethereum -> Arbitrum One; needs `ETHEREUM_MAINNET_RPC_URL` / `ARBITRUM_MAINNET_RPC_URL`).
- CCIP 2.0 routers: `getCCIPV2RouterAddress(chainId)` / `setCCIPV2RouterAddress(chainId, router)`. Some chains run a
  dedicated CCIP 2.0 router next to the router `getNetworkDetails` returns (Ethereum Sepolia
  `0x784d49a71BB4C48eB7dA4cD7e6Ecb424f9b5EAB1`, Avalanche Fuji `0x7C9B8B4e8024e5Ee8A630F6FCe9015e470dA5763`, seeded by
  default). `switchChainAndRouteMessage` routes messages sent through either router. `Register` / `getNetworkDetails`
  are unchanged (`routerAddress` is still the router from the CCIP docs API).

### Removed

- `abi/*.json` (`EVM2EVMOnRamp`, `EVM2EVMOffRamp`, `OnRamp`, `Router`, `LinkToken`) are no longer shipped in the npm
  package; the JavaScript helpers use inline human-readable ABIs. Import ABIs from `@chainlink/contracts-ccip` /
  `@chainlink/contracts` artifacts instead.
- Hardhat 2 example scripts (`scripts/examples/`) and Hardhat 2 `.spec.ts` tests, which could not run on Hardhat 3.

### Fixed

- `switchChainAndRouteMessage` no longer reverts when a router lists OffRamps of several versions for the same source
  chain (e.g. 1.2, 1.5, 1.6 and 2.0 during lane migrations). OffRamp 1.6 and 2.0 share `getSourceChainConfig(uint64)`
  and `getStaticConfig()` selectors with other versions but return different structs, and a mismatched return payload
  failed to decode in the caller, which `try/catch` does not catch. OffRamps are now matched by `typeAndVersion`
  (`OffRamp 2.*` against `onRamps[]`, `OffRamp 1.6*` against `onRamp`, `EVM2EVMOffRamp 1.*` against `getStaticConfig`),
  every decode is isolated, and an OffRamp of unknown shape is skipped.
- CCIP 2.0 (`OFFRAMP_DERIVED`): a message is marked processed only when the OffRamp reports `SUCCESS`. OffRamp 2.0
  `execute` does not revert when verification or the receiver fails on a first attempt; it records `FAILURE`, which was
  previously treated as delivered. Only the OffRamp bound to the emitting OnRamp is executed (previously every OffRamp on
  the router was tried), and `RESPECT_NO_EXEC` / `MANUAL_ONLY` queueing now applies in this mode too.
- CCIP 2.0: an unexpected `getCCVsForMessage` or verifier-resolver `owner()` response (including a CCV without code) no
  longer reverts routing.
- v1.6: `Any2EVMRampMessage.sender` is `abi.encode(address)` (32 bytes, as production 1.6 lanes deliver) instead of
  `abi.encodePacked` (20 bytes); receivers doing `abi.decode(message.sender, (address))` reverted (#62 / #65).
- **CCIP 2.0 CCV selection matches the OffRamp quorum.** The simulator passed `max(required, threshold)` CCVs in total,
  so a receiver with required CCVs plus optional CCVs (e.g. `required=[A], optional=[B,C], threshold=1`) failed with
  `OptionalCCVQuorumNotReached` where production delivers. It now passes every required CCV plus `threshold` optional
  ones (optional CCVs that are also required count toward the threshold), in the Solidity simulator, the local-codec
  adapter and the JavaScript helper.
- **1.6 messages execute only on their destination fork.** 1.6 OnRamps serve every destination from one address, so
  with several destination forks a 1.6 message could execute on the first fork whose OffRamp served the source lane
  (and be marked processed there). 1.6 logs are now filtered by `destChainSelector` like 2.0 logs.
- **`CCIPLocalSimulatorFork` deploys in ~14.4M gas** (was ~36M): `new CCIPLocalSimulatorFork()` right after
  `createSelectFork` ran out of gas on forks with a 30M block gas limit.
- `setLaneDefaultCCVs` keeps the lane's `laneMandatedCCVs` (it cleared them, making the fork lane less strict than
  production).
- Routing hardening: a 32-byte OnRamp or owner word that is not an address is skipped instead of reverting the lookup;
  a 2.0 log whose `messageId` topic differs from `keccak256(encodedMessage)` is rejected; a foreign event with a CCIP
  event signature but fewer indexed topics no longer panics routing; the unused OnRamp era probe was removed (routing
  always followed the event's era, and the probe classified `"EVM2EVMOnRamp 1.2.0"` as 2.0); the 2.0 destination filter reads `topics[1]` in every
  `V2VerificationMode`, so a non-default mode no longer decodes `MessageV1` before the emitter check.
- **The npm package compiles for Hardhat 3 and npm-based Foundry consumers.** It ships a `remappings.txt` for
  `node_modules` layouts (`remappings-npm.txt`, swapped in by the `prepack` script and restored by `postpack`; git and
  `forge install` consumers keep the `lib/` remappings), so Hardhat 3 no longer fails with `HHE902` on the
  `@openzeppelin/contracts@4.8.3/...` imports.
- The JavaScript helpers throw a clear error naming `@nomicfoundation/hardhat-ethers` when the connection has no
  `ethers` (was `Cannot read properties of undefined (reading 'Interface')`), and decode `OptionalCCVQuorumNotReached`,
  `InvalidOptionalThreshold`, `InvalidVerifierResultsLength`, `NoStateProgressMade` and `InvalidEVMAddress`.
- 1.6 and pre-1.6 fork execution (Solidity and JavaScript) passes zero `tokenGasOverrides`, so each token keeps the `destGasAmount` stamped by the
  source OnRamp, as when a DON executes the message. The message gas limit was passed as every token's release/mint
  gas budget instead.
- CCIP 2.0 (`OFFRAMP_DERIVED` and the JavaScript helper): the OffRamp stamped in the message
  (`MessageV1.offRampAddress`) is used when it serves the lane. OffRamp 2.0 rejects a message stamped with another OffRamp (`InvalidOffRamp`), and the router lookup returned
  the newest OffRamp of the lane, which differs while an OffRamp is being replaced.
- The synthetic CCV setup is read from the resolver on every route instead of being cached, and the no-op verifier is
  redeployed when it has no code: after `vm.rollFork` or a snapshot revert on the destination fork, 2.0 messages failed
  with the cached (now missing) configuration.
- The single-fork `switchChainAndRouteMessage(forkId)` always returns with `forkId` selected, as documented (it stayed on
  the source fork when nothing was routed).
- `CCIPLocalRouter` declares `pragma solidity ^0.8.20`, the floor its OpenZeppelin 5.3.0 imports already required.
- The JavaScript helper checks that a 1.6 message's destination is the connected chain before executing it (1.6 OnRamps
  serve several destinations, and `executeSingleMessage` does not check it), and every execution transaction's revert
  is thrown with the decoded reason (the original error is kept as `cause`); it also decodes `TokenHandlingError`,
  `ReleaseOrMintBalanceMismatch`, `InvalidMessageDestChainSelector` and `CursedByRMN`.
- The npm package lists the CCIP JavaScript helper with its actual file name (`scripts/CCIPLocalSimulatorFork.js`); the
  lowercase entry did not match on case-sensitive file systems, so published packages could omit the helper.

### Known limitations

- **Live 1.6 lanes are not available on the tested testnets.** Every Register-router lane between Ethereum Sepolia,
  Avalanche Fuji, Arbitrum Sepolia and Base Sepolia runs CCIP 2.0 as of Sep 2026. The 1.6 path is covered by unit tests
  and by a fork regression pinned to Sepolia block 11,500,000 / Arbitrum Sepolia block 298,680,335 (needs archive RPCs).
  Ethereum <-> Arbitrum One mainnet is also CCIP 2.0, so 1.6 mainnet lanes were not fork-tested.
- **Pre-1.6 (`EVM2EVMOnRamp`) routing** is covered by unit tests only; no live pre-1.6 lane was fork-tested. The
  Solidity simulator executes pre-1.6 messages with the `EVM2EVMOffRamp` 1.5 signature only (the JavaScript helper
  also supports 1.2).
- **Mainnet token transfers over CCIP 2.0 were not fork-tested**: as of Sep 2026 the Ethereum LINK pool rejects
  Arbitrum One on the 2.0 lane (`ChainNotAllowed`). Mainnet messages are fork-tested.
- **CCVs are simulated, not verified.** On a fork there are no live attestations: resolver CCVs are pointed at a
  synthetic no-op verifier (or mocked with `setLaneDefaultCCVs`). CCV selection, quorum, finality checks, token
  release/mint and the receiver call run production OffRamp code. A CCV that is not an owner-configurable resolver and
  is not mocked makes execution fail (logged, message not marked processed).
- **Dedicated CCIP 2.0 routers are known for Ethereum Sepolia and Avalanche Fuji only.** Set others with
  `setCCIPV2RouterAddress`. As of Sep 2026 these routers reject CCIP-BnM (`UnsupportedToken`); CCIP-BnM token transfers
  over CCIP 2.0 work through the Register routers' 2.0 lanes.
- **Local mode limitations** (use fork mode for these):
  - No token pools: pool policies (e.g. a minimum Fast Transfer block depth, `FTFNotSupportedOnPoolV1`, rate limits)
    are not enforced, and tokens are transferred directly to the receiver.
  - No CCVs and no block confirmations: messages are delivered synchronously inside `ccipSend`, and receiver CCV lists
    are only validated, not verified.
  - The supported-token list (`getSupportedTokens`) is not enforced by the router.
  - `NO_EXECUTION_ADDRESS` messages are executed immediately (fork mode queues them for `executePendingV2Message`).
  - There is no per-lane `maxPerMsgGasLimit` cap: production reverts `MessageGasLimitTooHigh` above the lane's cap, local
    mode only above `type(uint32).max`.
- **Fork mode executes 1.6 and pre-1.6 messages by impersonating the OffRamp** and calling `executeSingleMessage`, which
  skips the checks of the OffRamp's `execute` entrypoint (commit/merkle proofs, RMN). CCIP 2.0 messages go through the
  permissionless `execute`, so all 2.0 OffRamp checks run.
- **Hard-coded values can go stale**: the dedicated CCIP 2.0 router map (Ethereum Sepolia and Avalanche Fuji only),
  `Register` data and the known OffRamp `typeAndVersion` prefixes. A message on a lane the simulator cannot resolve now
  fails loudly in strict mode (`CCIPLocalSimulatorFork__MessageNotRouted`) instead of being dropped. Override with
  `setCCIPV2RouterAddress` / `setNetworkDetails`.
- **Synthetic CCV verification persists on the fork**: routing registers a no-op verifier for the `"FORK"` result
  version on real resolver CCVs, so after a routed 2.0 message, a forged message with `"FORK"` results can also execute
  on that fork.
- **Recorded logs are consumed** by `switchChainAndRouteMessage`. 1.6 and 2.0 messages whose destination fork was not
  passed are kept (`QUEUED`) for a later call; one whose destination fork is never passed is never routed, so check
  `getMessageStatus` when in doubt. Pre-1.6 messages must be routed in the call that includes their destination.
- **The Hardhat JavaScript helper executes CCIP 2.0 messages with a fixed 15M gas limit** (capped at the block gas
  limit), because OffRamp 2.0 `execute` records `FAILURE` instead of reverting when it runs out of gas.
- Hardhat 3 runs every fork test in parallel; with a rate-limited RPC provider fork `setUp` can fail. Run fork suites
  individually (`npx hardhat test solidity <file>`) or with a higher-throughput provider.

### Migration guide (0.2.x -> 0.3.0)

1. Bump `@chainlink/contracts-ccip` to `2.0.0` (Foundry: `lib/chainlink-ccip` at `contracts-ccip-v2.0.0`) and
   `@chainlink/local` to `0.3.0-beta` (published under the `beta` tag: `npm install @chainlink/local@0.3.0-beta`,
   `forge install smartcontractkit/chainlink-local@v0.3.0-beta`). Use Node.js 22 for Hardhat 3. Hardhat 3 Solidity
   tests need no remappings; Foundry projects installing from npm list the package's dependencies in `remappings.txt`
   (see the README).
2. Fork tests: compile them with `cancun` or later, without changing the EVM version your contracts are deployed with,
   and use Foundry >= 1.5.1 (forge 1.1.0 panics on a failed CCIP 2.0 execution). For example, add a fork profile to
   `foundry.toml` and run fork tests with `FOUNDRY_PROFILE=fork forge test`:
   ```toml
   [profile.fork]
   evm_version = "cancun"
   ```
   or pass `--evm-version cancun` to `forge test`. In Hardhat 3, set `evmVersion: "cancun"` in the Solidity settings of
   the build profile you run fork tests with.
3. Extra args V3: replace block confirmations with a `FinalityCodec` config.
   ```solidity
   // before: ExtraArgsCodec._getBasicEncodedExtraArgsV3(gasLimit, uint16(blockConfirmations))
   ExtraArgsCodec._getBasicEncodedExtraArgsV3(gasLimit, FinalityCodec.WAIT_FOR_FINALITY_FLAG); // finality
   ExtraArgsCodec._getBasicEncodedExtraArgsV3BlockDepth(gasLimit, 5); // Fast Transfer, 5 blocks
   ExtraArgsCodec._getBasicEncodedExtraArgsV3FastConfirmationRule(gasLimit); // wait for the `safe` tag
   ```
   `GenericExtraArgsV2` / `EVMExtraArgsV1` are unaffected.
4. Receivers implementing `IAny2EVMMessageReceiverV2`: rename `getCCVsAndMinBlockDepth` to `getCCVsAndFinalityConfig`
   and return `bytes4` (`FinalityCodec.WAIT_FOR_FINALITY_FLAG` for finality only, `FinalityCodec._encodeBlockDepth(n)`
   to accept Fast Transfers of at least `n` blocks). A receiver must opt in this way to receive Fast Transfer messages with data.
5. Token pools: `setMinBlockConfirmations(n)` -> `setAllowedFinalityConfig(FinalityCodec._encodeBlockDepth(n))`. Read a
   live pool's policy with `getAllowedFinalityConfig()`; requested Fast Transfer block depth must be >= the pool's allowed depth.
6. Fork tests on CCIP 2.0 lanes need no extra setup in the default mode. If you relied on the previous default, call
   `setV2VerificationMode(V2VerificationMode.HYBRID)`. If you referenced `IRouterFork.OffRamp`, use
   `CCIPForkAdapterTypes.RouterOffRamp`.
7. Local mode: Fast Transfer messages with data now need an opted-in receiver (step 4), as on a fork and in production. Tests that
   sent Fast Transfer data to a plain `CCIPReceiver` must switch the receiver or request finality.
8. Hardhat JavaScript/TypeScript tests: move to Hardhat 3 and `@nomicfoundation/hardhat-ethers`, and pass the network
   connection to the helpers:
   ```js
   import { network } from "hardhat";
   import { getCCIPMessages, routeMessage } from "@chainlink/local/scripts/CCIPLocalSimulatorFork.js";

   const source = await network.connect({ network: "sepoliaFork" }); // edr-simulated networks with `forking`
   const destination = await network.connect({ network: "arbitrumSepoliaFork" });
   const receipt = await (await sourceRouter.ccipSend(destChainSelector, message, { value: fee })).wait();
   const [sent] = getCCIPMessages(source, receipt);
   await routeMessage(destination, destinationRouterAddress, sent); // throws with the reason if execution fails
   ```
   Pass an array of routers (e.g. `[routerAddress, CCIP_V2_ROUTERS[chainId]]`) to route through dedicated CCIP 2.0
   routers, and `{ forceExecution: true }` to execute a `NO_EXECUTION_ADDRESS` message.
9. Strict routing: tests that tolerated failed or unroutable messages now revert. Assert the failure with
   `vm.expectRevert(abi.encodeWithSelector(CCIPLocalSimulatorFork.CCIPLocalSimulatorFork__MessageExecutionFailed.selector, messageId, expectedReason))`,
   or call `setStrictRouting(false)` and check `getMessageStatus(messageId)`.
10. Local mode: sends with more than one token, a zero token amount, a non-empty V3 `tokenReceiver` or a V1/V2 gas limit
    above `type(uint32).max` now revert, as in production; V2 receivers' `getCCVsAndFinalityConfig` must not revert and must return a valid config; do not rely on
    local `messageId` values being equal for identical sends.
11. `Register`: if you used `wrappedNativeAddress` on the chains listed under Breaking changes, it now points at the
    wrapped native token (it was GHO on e.g. Ethereum Sepolia). For a removed chain, set its details with
    `setNetworkDetails`.
12. Replace `@chainlink/local/src/vendor/...` imports with `@openzeppelin/contracts@4.8.3/...`,
    `@openzeppelin/contracts@5.3.0/...` or `@chainlink/contracts-ccip/...`.
13. To use a dedicated CCIP 2.0 router, send through `getCCIPV2RouterAddress(block.chainid)` and deploy receivers with
   the destination chain's CCIP 2.0 router (the destination router must be the one whose OffRamp delivers the message).

## [0.2.9] - 19 May 2026

### Dependencies

| Package                   | Version |
| ------------------------- | ------- |
| @chainlink/contracts-ccip | 1.6.2   |
| @chainlink/contracts      | 1.5.0   |

### Fixed

- `CCIPLocalSimulatorFork.switchChainAndRouteMessage` now pairs the destination OffRamp with the source OnRamp by reading `getSourceChainConfig` (v1.6+) and `getStaticConfig` (pre-v1.6), and falls back to trying other OffRamps with the same `sourceChainSelector` when execution fails or no deterministic match is found.
- `CCIPLocalSimulatorFork.switchChainAndRouteMessage` now correctly decodes `destTokenAddress` for v1.6 token transfers. The 32-byte `abi.encode(address)` value was previously truncated via a `bytes20` cast, yielding a garbage address and causing the destination OffRamp's `TokenAdminRegistry.getPool` lookup to revert. Decoding now handles both 32-byte ABI-encoded and 20-byte packed forms, matching production OffRamp behavior, and is shared with `receiver` decoding via a single internal `_decodeEVMAddress` helper.
- For v1.6 token transfers, `sourcePoolAddress` is now passed to `Internal.Any2EVMTokenTransfer` as `abi.encode(address)` (32-byte word), matching production OnRamp output and destination pool validation. The simulator previously used `abi.encodePacked(address)` (20 bytes), which caused compatible pools to revert with `InvalidSourcePoolAddress` during fork testing.

## [0.2.9-beta.0] - 7 May 2026

### Dependencies

| Package                   | Version |
| ------------------------- | ------- |
| @chainlink/contracts-ccip | 1.6.2   |
| @chainlink/contracts      | 1.5.0   |

### Fixed

- `CCIPLocalSimulatorFork.switchChainAndRouteMessage` now correctly decodes `destTokenAddress` for v1.6 token transfers. The 32-byte `abi.encode(address)` value was previously truncated via a `bytes20` cast, yielding a garbage address and causing the destination OffRamp's `TokenAdminRegistry.getPool` lookup to revert. Decoding now handles both 32-byte ABI-encoded and 20-byte packed forms, matching production OffRamp behavior, and is shared with `receiver` decoding via a single internal `_decodeEVMAddress` helper.
- For v1.6 token transfers, `sourcePoolAddress` is now passed to `Internal.Any2EVMTokenTransfer` as `abi.encode(address)` (32-byte word), matching production OnRamp output and destination pool validation. The simulator previously used `abi.encodePacked(address)` (20 bytes), which caused compatible pools to revert with `InvalidSourcePoolAddress` during fork testing.

## [0.2.9-beta] - 6 May 2026

### Dependencies

| Package                   | Version |
| ------------------------- | ------- |
| @chainlink/contracts-ccip | 1.6.2   |
| @chainlink/contracts      | 1.5.0   |

### Fixed

- `CCIPLocalSimulatorFork.switchChainAndRouteMessage` now pairs the destination OffRamp with the source OnRamp by reading `getSourceChainConfig` (v1.6+) and `getStaticConfig` (pre-v1.6), and falls back to trying other OffRamps with the same `sourceChainSelector` when execution fails or no deterministic match is found.

## [0.2.8] - 5 May 2026

### Dependencies

| Package                   | Version |
| ------------------------- | ------- |
| @chainlink/contracts-ccip | 1.6.2   |
| @chainlink/contracts      | 1.5.0   |

### Added

- Data Streams Report versions V1, V5-V13
- CCIP Network Details Update Script to fetch and update CCIP network details from Chainlink's API

## [0.2.8-beta] - 14 January 2026

### Dependencies

| Package                   | Version |
| ------------------------- | ------- |
| @chainlink/contracts-ccip | 1.6.2   |
| @chainlink/contracts      | 1.5.0   |

### Added

- CCIP Network Details Update Script to fetch and update CCIP network details from Chainlink's API

## [0.2.7] - 9 November 2025

### Dependencies

| Package                   | Version |
| ------------------------- | ------- |
| @chainlink/contracts-ccip | 1.6.2   |
| @chainlink/contracts      | 1.5.0   |

### Added

- Data Streams billing mechanism toggle in `DataStreamsLocalSimulator.sol`
- `enableOffChainBilling()` and `enableOnChainBilling()` functions
- `getBillingMechanism()` helper function
- Developer-friendly error messages for billing mechanism mismatches
- Comprehensive test suite for billing mechanisms
- Trusted publishing workflow with OIDC authentication
- Automatic version and branch validation in CI/CD

### Changed

- Bumped `@chainlink/contracts-ccip` to `1.6.2` version
- Bumped `@chainlink/contracts` to `1.5.0` version
- Updated import paths to use vendored OpenZeppelin contracts
- Enhanced `configuration()` function to return current fee manager state
- Unified publish workflows into single automated workflow

### Fixed

- Fixed Hardhat 2 compilation issues by vendoring OpenZeppelin contracts
- Fixed import path issues that occurred with updated dependency versions

## [0.2.7-beta.0] - 9 October 2025

### Dependencies

| Package                   | Version |
| ------------------------- | ------- |
| @chainlink/contracts-ccip | 1.6.2   |
| @chainlink/contracts      | 1.5.0   |

### Added

- Data Streams billing mechanism toggle in `DataStreamsLocalSimulator.sol`
- `enableOffChainBilling()` and `enableOnChainBilling()` functions
- `getBillingMechanism()` helper function
- Developer-friendly error messages for billing mechanism mismatches
- Comprehensive test suite for billing mechanisms
- Trusted publishing workflow with OIDC authentication
- Automatic version and branch validation in CI/CD

### Changed

- Bumped `@chainlink/contracts-ccip` to `1.6.2` version
- Bumped `@chainlink/contracts` to `1.5.0` version
- Updated import paths to use vendored OpenZeppelin contracts
- Enhanced `configuration()` function to return current fee manager state
- Unified publish workflows into single automated workflow

### Fixed

- Fixed Hardhat 2 compilation issues by vendoring OpenZeppelin contracts
- Fixed import path issues that occurred with updated dependency versions

## [0.2.6] - 18 September 2025

### Dependencies

| Package                   | Version |
| ------------------------- | ------- |
| @chainlink/contracts-ccip | 1.6.0   |
| @chainlink/contracts      | 1.4.0   |

### Added

- Added `switchChainAndRouteMessage(uint256[] memory chainIds)` function which is an overlap of already existing `switchChainAndRouteMessage(chainId)` in the `CCIPLocalSimulatorFork.sol` contract. This new function can be used to route multiple CCIP messages to multiple chains in a single call.

### Changed

- Refactored `CCIPLocalSimulatorFork.sol` so it can route all CCIP messages sent from a loop and not just the first one

## [0.2.6-beta.0] - 10 September 2025

### Dependencies

| Package                   | Version |
| ------------------------- | ------- |
| @chainlink/contracts-ccip | 1.6.0   |
| @chainlink/contracts      | 1.4.0   |

### Services

- [x] Chainlink CCIP v1.6

### Changed

- Refactored `CCIPLocalSimulatorFork.sol` to deliver more than one message to more than one chain in a same call

## [0.2.6-beta] - 11 June 2025

### Dependencies

| Package                   | Version |
| ------------------------- | ------- |
| @chainlink/contracts-ccip | 1.6.0   |
| @chainlink/contracts      | 1.4.0   |

### Services

- [x] Chainlink CCIP v1.6

### Changed

- Refactored `CCIPLocalSimulatorFork.sol` so it can route all CCIP messages sent
  from a loop and not just the first one

## [0.2.5] - 10 June 2025

### Dependencies

| Package                   | Version |
| ------------------------- | ------- |
| @chainlink/contracts-ccip | 1.6.0   |
| @chainlink/contracts      | 1.4.0   |

### Services

- [x] Chainlink CCIP v1.6

### Added

- Added support for Chainlink CCIP v1.6

### Changed

- Bumped `@chainlink/contracts-ccip` to `1.6.0` version
- Bumped `@chainlink/contracts` to `1.4.0` version

## [0.2.5-beta.0] - 20 May 2025

### Dependencies

| Package                   | Version |
| ------------------------- | ------- |
| @chainlink/contracts-ccip | 1.6.0   |
| @chainlink/contracts      | 1.4.0   |

### Services

- [x] Chainlink CCIP v1.6

### Changed

- Bumped `@chainlink/contracts-ccip` to `1.6.0` version
- Bumped `@chainlink/contracts` to `1.4.0` version

## [0.2.5-beta] - 14 May 2025

### Dependencies

| Package                   | Version      |
| ------------------------- | ------------ |
| @chainlink/contracts-ccip | 1.6.0-beta.3 |
| @chainlink/contracts      | 1.4.0-beta.0 |

### Services

- [x] Chainlink CCIP v1.6

### Added

- Added support for Chainlink CCIP v1.6

## [0.2.4] - 25 March 2025

### Dependencies

| Package                   | Version      |
| ------------------------- | ------------ |
| @chainlink/contracts-ccip | 1.5.1-beta.0 |
| @chainlink/contracts      | 1.3.0        |

### Services

- [x] Chainlink CCIP
- [x] Chainlink CCIP v1.5
- [x] Chainlink Data Feeds
- [x] Chainlink Data Streams
- [ ] Chainlink Automation
- [ ] Chainlink VRF 2
- [ ] Chainlink VRF 2.5

### Added

- Added full support for Data Streams by adding `DataStreamsLocalSimulator.sol`
  (Foundry/Hardhat/Remix IDE local mode), `DataStreamsLocalSimulatorFork.sol`
  (Foundry forked mode), `DataStreamsLocalSimulatorFork.js` (Hardhat forked
  mode) and `MockReportGenerator.sol` & `MockReportGenerator.js` to mock
  generating unverified reports by Data Streams DON for local modes in Foundry
  and Hardhat respectively.
- Instructions to install Chainlink Local using Soldeer

### Changed

- Bumped `@chainlink/contracts` to `1.3.0` version
- Started returning raw Report structs from `generateReportV2`,
  `generateReportV3` and`generateReportV4` functions alongside the
  `signedReport` bytes blob which is already returned

## [0.2.4-beta.1] - 24 February 2025

### Dependencies

| Package                   | Version      |
| ------------------------- | ------------ |
| @chainlink/contracts-ccip | 1.5.1-beta.0 |
| @chainlink/contracts      | 1.3.0        |

### Services

- [x] Chainlink CCIP
- [x] Chainlink CCIP v1.5
- [x] Chainlink Data Feeds
- [x] Chainlink Data Streams
- [ ] Chainlink Automation
- [ ] Chainlink VRF 2
- [ ] Chainlink VRF 2.5

### Changed

- Fixed incorrect import path for `Math.sol` in `MockFeeManager.sol`

## [0.2.4-beta.0] - 23 February 2025

### Dependencies

| Package                   | Version      |
| ------------------------- | ------------ |
| @chainlink/contracts-ccip | 1.5.1-beta.0 |
| @chainlink/contracts      | 1.3.0        |

### Services

- [x] Chainlink CCIP
- [x] Chainlink CCIP v1.5
- [x] Chainlink Data Feeds
- [x] Chainlink Data Streams
- [ ] Chainlink Automation
- [ ] Chainlink VRF 2
- [ ] Chainlink VRF 2.5

### Added

- Instructions to install Chainlink Local using Soldeer

### Changed

- Bumped `@chainlink/contracts` to `1.3.0` version
- Started returning raw Report structs from `generateReportV2`,
  `generateReportV3` and`generateReportV4` functions alongside the
  `signedReport` bytes blob which is already returned

## [0.2.4-beta] - 10 December 2024

### Dependencies

| Package                   | Version      |
| ------------------------- | ------------ |
| @chainlink/contracts-ccip | 1.5.1-beta.0 |
| @chainlink/contracts      | 1.1.1        |

### Services

- [x] Chainlink CCIP
- [x] Chainlink CCIP v1.5
- [x] Chainlink Data Feeds
- [x] Chainlink Data Streams
- [ ] Chainlink Automation
- [ ] Chainlink VRF 2
- [ ] Chainlink VRF 2.5

### Added

- Added full support for Data Streams by adding `DataStreamsLocalSimulator.sol`
  (Foundry/Hardhat/Remix IDE local mode), `DataStreamsLocalSimulatorFork.sol`
  (Foundry forked mode), `DataStreamsLocalSimulatorFork.js` (Hardhat forked
  mode) and `MockReportGenerator.sol` & `MockReportGenerator.js` to mock
  generating unverified reports by Data Streams DON for local modes in Foundry
  and Hardhat respectively.

## [0.2.3] - 30 November 2024

### Dependencies

| Package                   | Version      |
| ------------------------- | ------------ |
| @chainlink/contracts-ccip | 1.5.1-beta.0 |
| @chainlink/contracts      | 1.1.1        |

- [x] Chainlink CCIP
- [x] Chainlink CCIP v1.5
- [x] Chainlink Data Feeds
- [ ] Chainlink Automation
- [ ] Chainlink VRF 2
- [ ] Chainlink VRF 2.5

### Added

- Added `supportNewTokenViaAccessControlDefaultAdmin` function to
  `CCIPLocalSimulator.sol`
- Bumped `@chainlink/contracts-ccip` to `1.5.1-beta.0` to reflect new changes in
  the CCIP `TokenPool.sol` smart contract (check
  [CCIPv1_5BurnMintPoolFork.t.sol](./test/e2e/ccip/CCIPv1_5ForkBurnMintPoolFork.t.sol)
  and
  [CCIPv1_5LockReleasePoolFork.t.sol](./test/e2e/ccip/CCIPv1_5ForkLockReleasePoolFork.t.sol)
  tests) and to support `EVMExtraArgsV2` in `MockCCIPRouter.sol`

## [0.2.2] - 15 October 2024

### Dependencies

| Package                   | Version |
| ------------------------- | ------- |
| @chainlink/contracts-ccip | 1.5.0   |
| @chainlink/contracts      | 1.1.1   |

### Services

- [x] Chainlink CCIP
- [x] Chainlink CCIP v1.5
- [x] Chainlink Data Feeds
- [ ] Chainlink Automation
- [ ] Chainlink VRF 2
- [ ] Chainlink VRF 2.5

### Added

- Support for Chainlink CCIP v1.5 (bumped `@chainlink/contracts-ccip` to
  `1.5.0`)
- Added CCIP v1.5 config details to `Register.sol` for all available testnet
  lanes
- Set EVM Version strictly to `paris` for all contracts
- Added `supportNewTokenViaOwner` and `supportNewTokenViaGetCCIPAdmin` functions
  to `CCIPLocalSimulator.sol` instead of `supportNewToken` function
- Added `rmnProxyAddress`, `tokenAdminRegistryAddress` and
  `registryModuleOwnerCustomAddress` to the `NetworkDetails` struct of the
  `Register.sol` smart contract
- Added unit tests for new functions in the `CCIPLocalSimulator.sol` contract
- Added e2e test for new changes in the `CCIPLocalSimulatorFork.sol` contract.
  There is a test with ERC-20 token with an `owner()` function implemented and
  Burn & Mint Pool, and test with ERC-20 token with a `getCCIPAdmin()` function
  implemented and Lock & Release Pool
- Genereted new docs artifacts

### Changed

- Bumped Solidity compiler version from 0.8.19 to 0.8.24
- The `getSupportedTokens()` function now only exists in the
  `CCIPLocalSimulator.sol` contract, it has been removed from the CCIP's
  `Router.sol` contract. Calling that function from the `Router.sol` contract in
  the Forking mode will now revert
- Added `uint32[] memory tokenGasOverrides` as function parameter to the
  `executeSingleMessage` function in the `CCIPLocalSimulatorFork.sol` contract
  to reflect new changes in the CCIP's `EVM2EVMOffRamp.sol` smart contract
- Bumped pragma solidity version of `BasicTokenSender.sol`,
  `CCIPReceiver_Unsafe.sol`, `ProgrammableTokenTransfers` and
  `ProgrammableDefensiveTokenTransfers.sol` contracts from the `src/test` folder
  from `0.8.19` to `0.8.24`

### Removed

- Removed `supportNewToken` function from `CCIPLocalSimulator.sol`
- Removed `CCIPLocalSimulatorV0.sol` and `MockEvm2EvmOffRamp.sol` contracts as
  they have not being used for a while
- Removed `DOCUMENTATION.md` file since the official documentation is now
  available at https://docs.chain.link/chainlink-local
- Removed `remix-001.png` and `remix-002.png` images from the `assets` folder,
  because they are no longer needed

## [0.2.2-beta.1] - 10 October 2024

### Dependencies

| Package                   | Version      |
| ------------------------- | ------------ |
| @chainlink/contracts-ccip | 1.5.0-beta.1 |
| @chainlink/contracts      | 1.1.1        |

### Services

- [x] Chainlink CCIP
- [x] Chainlink CCIP v1.5
- [x] Chainlink Data Feeds
- [ ] Chainlink Automation
- [ ] Chainlink VRF 2
- [ ] Chainlink VRF 2.5

### Changed

- Bumped the version of `@chainlink/contracts-ccip` NPM package to
  `1.5.0-beta.1` to test that release
- Fixed the bug in the `CCIPLocalSimulatorFork.sol` where the
  `switchChainAndRouteMessage` function was used the outdated EVM2EVMOffRamp
  contract
- Genereted new docs artifacts

## [0.2.2-beta.0] - 04 October 2024

### Dependencies

| Package                   | Version      |
| ------------------------- | ------------ |
| @chainlink/contracts-ccip | 1.5.0-beta.0 |
| @chainlink/contracts      | 1.1.1        |

### Services

- [x] Chainlink CCIP
- [x] Chainlink CCIP v1.5
- [x] Chainlink Data Feeds
- [ ] Chainlink Automation
- [ ] Chainlink VRF 2
- [ ] Chainlink VRF 2.5

### Added

- Added CCIP v1.5 config details to `Register.sol` for all available testnet
  lanes

## [0.2.2-beta] - 12 September 2024

### Dependencies

| Package                   | Version      |
| ------------------------- | ------------ |
| @chainlink/contracts-ccip | 1.5.0-beta.0 |
| @chainlink/contracts      | 1.1.1        |

### Services

- [x] Chainlink CCIP
- [x] Chainlink CCIP v1.5
- [x] Chainlink Data Feeds
- [ ] Chainlink VRF 2
- [ ] Chainlink VRF 2.5

### Added

- Support for Chainlink CCIP v1.5 (bumped `@chainlink/contracts-ccip` to
  `1.5.0-beta.0`)
- Set EVM Version strictly to `paris` for all contracts
- Added `supportNewTokenViaOwner` and `supportNewTokenViaGetCCIPAdmin` functions
  to `CCIPLocalSimulator.sol` instead of `supportNewToken` function
- Added `rmnProxyAddress`, `tokenAdminRegistryAddress` and
  `registryModuleOwnerCustomAddress` to the `NetworkDetails` struct of the
  `Register.sol` smart contract
- Added unit tests for new functions in the `CCIPLocalSimulator.sol` contract
- Added e2e test for new changes in the `CCIPLocalSimulatorFork.sol` contract.
  There is a test with ERC-20 token with an `owner()` function implemented and
  Burn & Mint Pool, and test with ERC-20 token with a `getCCIPAdmin()` function
  implemented and Lock & Release Pool

### Changed

- Bumped Solidity compiler version from 0.8.19 to 0.8.24
- The `getSupportedTokens()` function now only exists in the
  `CCIPLocalSimulator.sol` contract, it has been removed from the CCIP's
  `Router.sol` contract. Calling that function from the `Router.sol` contract in
  the Forking mode will now revert
- Added `uint32[] memory tokenGasOverrides` as function parameter to the
  `executeSingleMessage` function in the `CCIPLocalSimulatorFork.sol` contract
  to reflect new changes in the CCIP's `EVM2EVMOffRamp.sol` smart contract
- Bumped pragma solidity version of `BasicTokenSender.sol`,
  `CCIPReceiver_Unsafe.sol`, `ProgrammableTokenTransfers` and
  `ProgrammableDefensiveTokenTransfers.sol` contracts from the `src/test` folder
  from `0.8.19` to `0.8.24`

### Removed

- Removed `supportNewToken` function from `CCIPLocalSimulator.sol`
- Removed `CCIPLocalSimulatorV0.sol` and `MockEvm2EvmOffRamp.sol` contracts as
  they have not being used for a while

## [0.2.1] - 5 July 2024

### Dependencies

| Package                   | Version |
| ------------------------- | ------- |
| @chainlink/contracts-ccip | 1.4.0   |
| @chainlink/contracts      | 1.1.1   |

### Services

- [x] Chainlink CCIP
- [x] Chainlink Data Feeds
- [ ] Chainlink VRF 2
- [ ] Chainlink VRF 2.5

### Added

- Support for Chainlink Data Feeds by adding `MockV3Aggregator.sol` and
  `MockOffchainAggregator.sol` mock contracts
- Showcase tests for testing in a forking actual networks environment

## [0.2.1-beta] - 26 June 2024

### Dependencies

| Package                   | Version |
| ------------------------- | ------- |
| @chainlink/contracts-ccip | 1.4.0   |
| @chainlink/contracts      | 1.1.1   |

### Services

- [x] Chainlink CCIP
- [x] Chainlink Data Feeds
- [ ] Chainlink VRF 2
- [ ] Chainlink VRF 2.5

### Fixed

- Bug in propose & confirm aggregator flow that could lead to aggregator being
  set to `address(0)`
- The `maxAnswer` variable in the `MockOffchainAggregator.sol` contract was set
  to an incorrect value
- Bug in the `MockOffchainAggregator.sol` contract where the `minAnswer`
  could've been set to the value greater than `maxAnswer`

## [0.2.0-beta] - 24 June 2024

### Dependencies

| Package                   | Version |
| ------------------------- | ------- |
| @chainlink/contracts-ccip | 1.4.0   |
| @chainlink/contracts      | 1.1.1   |

### Services

- [x] Chainlink CCIP
- [x] Chainlink Data Feeds
- [ ] Chainlink VRF 2
- [ ] Chainlink VRF 2.5

### Added

- Mock Data Feeds contracts to test in a local environment
- Showcase tests for testing in a forking actual networks environment

## [0.1.0] - 03 June 2024

### Dependencies

| Package                   | Version |
| ------------------------- | ------- |
| @chainlink/contracts-ccip | 1.4.0   |
| @chainlink/contracts      | -       |

### Services

- [x] Chainlink CCIP
- [ ] Chainlink Data Feeds

### Added

- Initial release of the project

[0.1.0]: https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.1.0
[0.2.0-beta]:
  https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.0-beta
[0.2.1-beta]:
  https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.1-beta
[0.2.1]: https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.1
[0.2.2-beta]:
  https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.2-beta
[0.2.2-beta.0]:
  https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.2-beta.0
[0.2.2-beta.1]:
  https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.2-beta.1
[0.2.2]: https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.2
[0.2.3]: https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.3
[0.2.4-beta]:
  https://github.com/smartcontractkit/chainlink-local/releases/tag/0.2.4-beta
[0.2.4-beta.0]:
  https://github.com/smartcontractkit/chainlink-local/releases/tag/0.2.4-beta.0
[0.2.4-beta.1]:
  https://github.com/smartcontractkit/chainlink-local/releases/tag/0.2.4-beta.1
[0.2.4]: https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.4
[0.2.5-beta]:
  https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.5-beta
[0.2.5-beta.0]:
  https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.5-beta.0
[0.2.5]: https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.5
[0.2.6-beta]:
  https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.6-beta
[0.2.6-beta.0]:
  https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.6-beta.0
[0.2.6]: https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.6
[0.2.7-beta.0]: https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.7-beta.0
[0.2.7]: https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.7
[0.2.8-beta]: https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.8-beta
[0.2.8]: https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.8
[0.2.9-beta]: https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.9-beta
[0.2.9-beta.0]: https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.9-beta.0
[0.2.9]: https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.9
[0.3.0-beta]: https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.3.0-beta