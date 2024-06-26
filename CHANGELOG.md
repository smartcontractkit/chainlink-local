# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

- Bug in propose & confirm aggregator flow that could lead to aggregator being set to `address(0)`
- The `maxAnswer` variable in the `MockOffchainAggregator.sol` contract was set to an incorrect value
- Bug in the `MockOffchainAggregator.sol` contract where the `minAnswer` could've been set to the value greather than `maxAnswer`

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
[0.2.0-beta]: https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.0-beta
[0.2.1-beta]: https://github.com/smartcontractkit/chainlink-local/releases/tag/v0.2.1-beta
