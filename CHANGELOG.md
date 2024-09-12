# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.2-beta] - 12 September 2024

### Dependencies

| Package                   | Version      |
| ------------------------- | ------------ |
| @chainlink/contracts-ccip | 1.4.0        |
| @chainlink/contracts      | 1.5.0-beta.0 |

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
