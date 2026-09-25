## Chainlink Local

Chainlink Local is an installable dependency. It provides a tool (the Chainlink Local Simulator) that developers import into their Foundry or Hardhat or Remix projects. This tool runs [Chainlink CCIP](https://docs.chain.link/ccip) locally which means developers can rapidly explore, prototype and iterate CCIP dApps off-chain in a local environment, and move to testnet only when they're ready to test in a live environment.

The package exposes a set of smart contracts and scripts with which you build, deploy and execute CCIP token transfers and arbitrary messages on a local Remix, Hardhat or Anvil (Foundry) development node. Chainlink Local also supports forked nodes.

User Contracts tested with Chainlink Local can be deployed to test networks without any modifications (assuming network specific contract addresses such as Router contracts and LINK token addresses are passed in via a constructor).

To view more detailed documentation and more examples, visit the [Chainlink Local Documentation](https://docs.chain.link/chainlink-local).

<p align="center">
  <a href="https://www.youtube.com/watch?v=rEVjU9tOf74&list=PL3ZUTf1nxlFyHKswTYFa2tffUsR94KAEv">
    <img src="./assets/thumbnail.png" alt="Watch the demo on YouTube" style="width:75%; border-radius:5%;">
  </a>
</p>

### Installation

`0.3.x` (V3) is published under the `beta` npm tag until the stable release; plain `npm install @chainlink/local` and the
default `main` branch still give `0.2.x`. Pin the version:

#### Foundry (git)

```
forge install smartcontractkit/chainlink-local@v0.3.0-beta
```

and then set remappings to: `@chainlink/local/=lib/chainlink-local/` in either `remappings.txt` or `foundry.toml` file

#### Foundry (soldeer)

```
forge soldeer install chainlink-local~v0.3.0-beta https://github.com/smartcontractkit/chainlink-local.git
```

#### Hardhat 3 (npm)

```
npm install @chainlink/local@0.3.0-beta
```

Hardhat 3 (Node.js 22) Solidity tests need no remappings: the package ships its own `remappings.txt`, and its
OpenZeppelin and `forge-std` dependencies are installed with it. Fork tests need `evmVersion: "cancun"` or later:

```ts
// hardhat.config.ts
import { defineConfig } from "hardhat/config";

export default defineConfig({
  solidity: { version: "0.8.24", settings: { evmVersion: "cancun" } },
});
```

```
npx hardhat test solidity
```

For the JavaScript/TypeScript fork helpers (`@chainlink/local/scripts/CCIPLocalSimulatorFork.js`), also install and
register the ethers plugin, and add forked networks:

```
npm install --save-dev @nomicfoundation/hardhat-ethers ethers
```

```ts
import { configVariable, defineConfig } from "hardhat/config";
import hardhatEthers from "@nomicfoundation/hardhat-ethers";

export default defineConfig({
  plugins: [hardhatEthers],
  solidity: { version: "0.8.24", settings: { evmVersion: "cancun" } },
  networks: {
    sepoliaFork: {
      type: "edr-simulated",
      chainType: "generic",
      chainId: 11155111,
      forking: { url: configVariable("ETHEREUM_SEPOLIA_RPC_URL") },
    },
  },
});
```

#### Foundry (npm)

Installing from npm into a Foundry project works too; list the package's dependencies in your `remappings.txt`
(Foundry does not load the remappings of packages under `node_modules`):

```
@chainlink/local/=node_modules/@chainlink/local/
@chainlink/contracts-ccip/=node_modules/@chainlink/contracts-ccip/
@chainlink/contracts/=node_modules/@chainlink/contracts/
@openzeppelin/contracts@4.8.3/=node_modules/@openzeppelin/contracts-4.8.3/
@openzeppelin/contracts@5.3.0/=node_modules/@openzeppelin/contracts-5.3.0/
forge-std/=node_modules/forge-std/src/
```

#### Remix IDE (local mode)

```solidity
import "https://github.com/smartcontractkit/chainlink-local/blob/v0.3.0-beta/src/ccip/CCIPLocalSimulator.sol";
```

Remix resolves the `@chainlink/contracts` and `@chainlink/contracts-ccip` imports to their latest npm versions.

Once you have installed CCIP Local, you are now ready to start using it with your project.

### Usage

Import `CCIPLocalSimulator.sol` inside your tests or scripts, for example (this is
[test/smoke/ccip/ReadmeUsageExample.t.sol](./test/smoke/ccip/ReadmeUsageExample.t.sol)):

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {
    CCIPLocalSimulator,
    IRouterClient,
    WETH9,
    LinkToken,
    BurnMintERC677Helper
} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

contract ReadmeUsageExampleTest is Test {
    CCIPLocalSimulator public ccipLocalSimulator;
    uint64 public chainSelector;
    IRouterClient public sourceRouter;
    LinkToken public linkToken;
    BurnMintERC677Helper public ccipBnM;

    function setUp() public {
        ccipLocalSimulator = new CCIPLocalSimulator();

        WETH9 wrappedNative;
        IRouterClient destinationRouter;
        BurnMintERC677Helper ccipLnM;
        (chainSelector, sourceRouter, destinationRouter, wrappedNative, linkToken, ccipBnM, ccipLnM) =
            ccipLocalSimulator.configuration();
    }

    function test_sendTokens() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        ccipLocalSimulator.requestLinkFromFaucet(alice, 5 ether);
        ccipBnM.drip(alice);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(ccipBnM), amount: 1 ether});
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(bob),
            data: "",
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 0, allowOutOfOrderExecution: true})),
            feeToken: address(linkToken)
        });

        vm.startPrank(alice);
        uint256 fee = sourceRouter.getFee(chainSelector, message);
        linkToken.approve(address(sourceRouter), fee);
        ccipBnM.approve(address(sourceRouter), 1 ether);
        sourceRouter.ccipSend(chainSelector, message);
        vm.stopPrank();

        assertEq(ccipBnM.balanceOf(bob), 1 ether);
    }
}
```

### Fork mode and CCIP 2.0

`CCIPLocalSimulatorFork` routes messages on forked networks for every CCIP era: pre-1.6 (`EVM2EVMOnRamp`), 1.6 and
CCIP 2.0 (CCV-based lanes, which live testnet lanes run today). Requirements for fork tests:

- Compile fork tests with `evm_version = "cancun"` or later (deployed CCIP 2.0 contracts use Cancun opcodes; `paris`
  fails with `EvmError: NotActivated`). Use a fork-only profile so your deployed bytecode is not affected:
  `[profile.fork]` with `evm_version = "cancun"` in `foundry.toml`, then `FOUNDRY_PROFILE=fork forge test`.
- Foundry >= 1.5.1 for fork tests (Hardhat 3 requires Node.js 22).

```solidity
CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
vm.makePersistent(address(ccipLocalSimulatorFork));

// Send through the router returned by getNetworkDetails(block.chainid).routerAddress, or through the dedicated
// CCIP 2.0 router where one exists: ccipLocalSimulatorFork.getCCIPV2RouterAddress(block.chainid).
// ...ccipSend(...)

ccipLocalSimulatorFork.switchChainAndRouteMessage(destinationForkId);
```

Routing is strict by default: `switchChainAndRouteMessage` reverts with
`CCIPLocalSimulatorFork__MessageNotRouted(messageId, reason)` when a captured message cannot be routed to any of the given
forks, and with `CCIPLocalSimulatorFork__MessageExecutionFailed(messageId, reason)` (the decoded revert data) when it does
not execute successfully. Call `setStrictRouting(false)` to record failures instead and read them with
`getMessageStatus(messageId)`. With several destinations, either pass every destination fork at once with the
`uint256[] forkIds` overload, or call `switchChainAndRouteMessage` once per destination fork: a 1.6 or 2.0 message to a
chain that is not in the call stays `QUEUED` and is routed by the call that includes its destination fork.

Hardhat 3 JavaScript/TypeScript tests can route the same way with `scripts/CCIPLocalSimulatorFork.js` (requires
`@nomicfoundation/hardhat-ethers`; TypeScript declarations ship next to it):

```js
import { network } from "hardhat";
import { getCCIPMessages, routeMessage } from "@chainlink/local/scripts/CCIPLocalSimulatorFork.js";

const source = await network.connect({ network: "sepoliaFork" });
const destination = await network.connect({ network: "arbitrumSepoliaFork" });
const receipt = await (await sourceRouter.ccipSend(destChainSelector, message, { value: fee })).wait();
const [sent] = getCCIPMessages(source, receipt);
await routeMessage(destination, destinationRouterAddress, sent);
```

| Environment | 0.3.x | 0.2.x |
| --- | --- | --- |
| Foundry, Hardhat 3 (Solidity tests, local + fork) | ✅ | Foundry only |
| Hardhat 3 JavaScript/TypeScript helpers | ✅ | - |
| Hardhat 2 | - (not supported: Hardhat 2 cannot resolve the `@openzeppelin/contracts@4.8.3/` style imports) | ✅ pre-1.6 fork routing only |
| Remix IDE (local mode) | ✅ | ✅ |

On CCIP 2.0 lanes the destination OffRamp selects the CCVs and executes the message (`V2VerificationMode.OFFRAMP_DERIVED`,
the default); CCV attestations are simulated. Fast Transfer messages with data are only delivered to receivers that
opt in through `getCCVsAndFinalityConfig`, as in production. See [CHANGELOG.md](./CHANGELOG.md) for the 0.3.0 breaking
changes, migration guide and known limitations.

### Local mode limitations

`CCIPLocalSimulator` delivers messages synchronously inside `ccipSend` and applies the CCIP 2.0 OnRamp and OffRamp message
rules (finality, one token per message, no zero amounts, no V3 `tokenReceiver` on EVM lanes, V2 receiver CCV config
validation). It does not simulate:

- token pools (pool finality policies, rate limits and pool-required CCVs are not enforced; tokens go directly to the
  receiver);
- CCVs or block confirmations (receiver CCV lists are validated, not verified);
- the supported-token list (`getSupportedTokens` is informational);
- manual execution (`NO_EXECUTION_ADDRESS` messages are executed immediately);
- the lane's `maxPerMsgGasLimit` (only V1/V2 extraArgs gas limits above `uint32` revert `MessageGasLimitTooHigh`).

Use fork mode to test these against the real contracts.

### Learn more

To view detailed documentation and more examples, visit the [Chainlink Local Documentation](https://docs.chain.link/chainlink-local).

> **Note**
>
> _This tutorial represents an educational example to use a Chainlink system, product, or service and is provided to demonstrate how to interact with Chainlink’s systems, products, and services to integrate them into your own. This template is provided “AS IS” and “AS AVAILABLE” without warranties of any kind, it has not been audited, and it may be missing key checks or error handling to make the usage of the system, product or service more clear. Do not use the code in this example in a production environment without completing your own audits and application of best practices. Neither Chainlink Labs, the Chainlink Foundation, nor Chainlink node operators are responsible for unintended outputs that are generated due to errors in code._
