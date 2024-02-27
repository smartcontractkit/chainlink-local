## Chainlink Local

To get started:

- Clone this repo.
- Run `npm i && forge install` to install dependencies.
- Run `npx hardhat test` to run Hardhat tests.
- Run `forge test` to run Foundry tests.
- Optionally, try Hardhat scripting by running `npx hardhat run ./scripts/UnsafeTokenAndDataTransfer.ts`

### Usage

Chainlink Local is a set of smart contracts and scripts that aims to enable the development of Chainlink-enabled smart contracts within a local blockchain environment.

To use it, you will need to port `src/ccip`, `src/shared` and `src/interfaces` folders into your Foundry or Hardhat project, either manually or by installing them by running `npm install git+https://github.com/smartcontractkit/chainlink-local.git`

Then, import `CCIPLocalSimulator.sol` inside your tests or scripts, for example:

```solidity
// test/demo.t.sol

pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {CCIPLocalSimulator} from "@chainlink/local/ccip/CCIPLocalSimulator.sol";

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
        ) = ccipLocalSimulator.DOCUMENTATION();


        ccipLocalSimulator.requestLinkFromFaucet(
            receiver,
            amount
        );
    }

}
```

This project is a combination of Foundry and Hardhat development environments, so you could technically try the local simulator here with much less friction. Just develop (or reuse) client smart contracts from `src/test/ccip` folder and create a new test file under the `test` folder, or a new script file under the `scripts` folder.

You can check our current examples for reference:

- [Unsafe Token And Data Transfer Test in Foundry](./test/smoke/ccip/UnsafeTokenAndDataTransfer.t.sol)
- [Unsafe Token And Data Transfer Test in Hardhat](./test/smoke/ccip/UnsafeTokenAndDataTransfer.spec.ts)
- [Unsafe Token And Data Transfer Script in Hardhat](./scripts/UnsafeTokenAndDataTransfer.ts)

And also recreated test examples in Foundry from the [Official Chainlink Documentation](https://docs.chain.link/ccip):

- [Token Transferor](./test/smoke/ccip/TokenTransferor.t.sol)
- [Programmable Token Transfers](./test/smoke/ccip/ProgrammableTokenTransfers.t.sol)
- [Programmable Token Transfers - Defensive Example](./test/smoke/ccip/ProgrammableDefensiveTokenTransfers.t.sol)
