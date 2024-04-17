## Chainlink Local

Chainlink Local is a simulator for developers to be able to use Chainlink CCIP locally in Hardhat and Foundry.

It is a set of smart contracts and scripts that aims to enable you to build, deploy and execute CCIP token transfers and arbitrary messages on a local Hardhat or Anvil (Foundry) node, both with and without forking.

### Installation

Install the package by running:

#### Foundry (git)

```
forge install smartcontractkit/chainlink-local
```

and the set remappings to: `@chainlink/local/=lib/chainlink-local/` in either `remmapings.txt` or `foundry.toml` file

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
import {CCIPLocalSimulator} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";

contract Demo is Test {
    CCIPLocalSimulator public ccipLocalSimulator;

    function setUp() public {
        ccipLocalSimulator = new CCIPLocalSimulator();

        (
            uint64 chainSelector,
            Router sourceRouter,
            Router destinationRouter,
            WETH9 wrappedNative,
            LinkToken linkToken,
            BurnMintERC677Helper ccipBnM,
            BurnMintERC677Helper ccipLnM,
        ) = ccipLocalSimulator.configuration();


        ccipLocalSimulator.requestLinkFromFaucet(
            receiver,
            amount
        );
    }

}
```

### Learn more

To view detailed documentation and more examples, visit [DOCUMENTATION.md](./DOCUMENTATION.md).
