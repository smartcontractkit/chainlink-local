## Chainlink Local

Chainlink Local is an installable package. It provides a simulation tool for developers to be able to depend on [Chainlink CCIP](https://docs.chain.link/ccip) locally in their Hardhat and Foundry projects.

The package exposes a set of smart contracts and scripts with which you build, deploy and execute CCIP token transfers and arbitrary messages on a local Hardhat or Anvil (Foundry) development node. Chainlink Local also supports forked nodes.

User Contracts tested with Chainlink Local can be deployed to test networks without any modifications.

<p align="center">
  <a href="https://youtu.be/rEVjU9tOf74?si=w-SHJQmFxJ0zi24q">
    <img src="https://github.com/smartcontractkit/chainlink-local/assets/37881789/9f8c2444-b238-431f-bb0b-8805be9c936f" alt="Watch the demo on YouTube" style="width:75%; border-radius:5%;">
  </a>
</p>

### Installation

Install the package by running:

#### Foundry (git)

```
forge install smartcontractkit/chainlink-local
```

and then set remappings to: `@chainlink/local/=lib/chainlink-local/` in either `remappings.txt` or `foundry.toml` file

#### Hardhat (npm)

```
npm install git+https://github.com/smartcontractkit/chainlink-local.git
```

### Usage

Import `CCIPLocalSimulator.sol` inside your tests or scripts, for example:

```solidity
// test/demo.t.sol

pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {IRouterClient, WETH9, LinkToken, BurnMintERC677Helper} from "@chainlink/local/src/ccip/CCIPLocalSimulator/sol";
import {CCIPLocalSimulator} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";

contract Demo is Test {
    CCIPLocalSimulator public ccipLocalSimulator;

    function setUp() public {
        ccipLocalSimulator = new CCIPLocalSimulator();

        (
            uint64 chainSelector,
            IRouterClient sourceRouter,
            IRouterClient destinationRouter,
            WETH9 wrappedNative,
            LinkToken linkToken,
            BurnMintERC677Helper ccipBnM,
            BurnMintERC677Helper ccipLnM
        ) = ccipLocalSimulator.configuration();


        ccipLocalSimulator.requestLinkFromFaucet(receiver, amount);
    }

}
```

### Learn more

To view detailed documentation and more examples, visit [DOCUMENTATION.md](./DOCUMENTATION.md).

> **Note**
>
> _This tutorial represents an educational example to use a Chainlink system, product, or service and is provided to demonstrate how to interact with Chainlink’s systems, products, and services to integrate them into your own. This template is provided “AS IS” and “AS AVAILABLE” without warranties of any kind, it has not been audited, and it may be missing key checks or error handling to make the usage of the system, product or service more clear. Do not use the code in this example in a production environment without completing your own audits and application of best practices. Neither Chainlink Labs, the Chainlink Foundation, nor Chainlink node operators are responsible for unintended outputs that are generated due to errors in code._
