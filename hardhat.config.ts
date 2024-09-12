import * as dotenv from "dotenv";
import "solidity-docgen";

import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.24",
        settings: {
          evmVersion: "paris"
        },
      }
    ]
  },
  paths: {
    sources: "./src",
  },
  docgen: {
    pages: "files",
    pageExtension: ".mdx",
    exclude: ["test"],
    outputDir: "api_reference/solidity",
  },
};

export default config;
