# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
