import { configVariable, defineConfig } from "hardhat/config";
import hardhatEthers from "@nomicfoundation/hardhat-ethers";
import * as dotenv from "dotenv";

dotenv.config();

// Forked networks used by the JavaScript fork helper tests (`npm run hardhat-test-js`). RPC URLs are only read from the
// environment when a network is connected to.
const fork = (chainId: number, rpcUrlVariable: string) => ({
  type: "edr-simulated" as const,
  chainType: "generic" as const,
  chainId,
  forking: { url: configVariable(rpcUrlVariable) },
});

export default defineConfig({
  plugins: [hardhatEthers],
  solidity: {
    compilers: [
      {
        version: "0.8.24",
        settings: {
          evmVersion: "cancun"
        },
      }
    ]
  },
  networks: {
    sepoliaFork: fork(11155111, "ETHEREUM_SEPOLIA_RPC_URL"),
    arbitrumSepoliaFork: fork(421614, "ARBITRUM_SEPOLIA_RPC_URL"),
    fujiFork: fork(43113, "AVALANCHE_FUJI_RPC_URL"),
  },
  paths: {
    sources: "./src",
  },
  docgen: {
    pages: "files",
    pageExtension: ".mdx",
    exclude: ["test", "vendor"],
    outputDir: "api_reference/solidity",
  },
});
