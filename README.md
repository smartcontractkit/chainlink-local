## Chainlink Local

Chainlink Local is an installable dependency. It provides a tool (the Chainlink Local Simulator) that developers import into their Foundry and Hardhat scripts. This tool runs [Chainlink CCIP](https://docs.chain.link/ccip) locally which means developers can rapidly explore prototype and iterate CCIP dApps off-chain, and move to testnet only when they're ready to test in a live environment.

The package exposes a set of smart contracts and scripts with which you build, deploy and execute CCIP token transfers and arbitrary messages on a local Hardhat or Anvil (Foundry) development node. Chainlink Local also supports forked nodes.

User Contracts tested with Chainlink Local can be deployed to test networks without any modifications.

### Installation

Before you start, please make sure you have the latest version of the Foundry tools by following the installation (and update) instructions [here](https://book.getfoundry.sh/getting-started/installation).

Install the package by running:

#### Foundry (git)

```
forge install smartcontractkit/chainlink-local --no-commit
```

This command will install chainlink-local into the `./lib` folder in your Foundry project.

Then you need to update [remappings](https://book.getfoundry.sh/projects/dependencies#remapping-dependencies) in either `remappings.txt` or `foundry.toml` file to: `@chainlink/local/=lib/chainlink-local/`.

For example the remappings property in `foundry.toml` could look like this:

```
remappings = [
    '@chainlink/local/=lib/chainlink-local/',
]
```

#### Hardhat (npm)

```
npm install git+https://github.com/smartcontractkit/chainlink-local.git
```

### Usage

Import `CCIPLocalSimulator.sol` inside your tests or scripts, and use the configuration data returned by [[CCIPLocalSimulator].configuration()](./DOCUMENTATION.md#cciplocalsimulatorconfiguration) use CCIP locally on your machine .

See this [Foundry Test Example](./DOCUMENTATION.md#foundry), and this [Hardhat Script Example](./DOCUMENTATION.md#hardhat).

