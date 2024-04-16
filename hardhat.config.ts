import * as dotenv from "dotenv"

import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";

dotenv.config()

const config: HardhatUserConfig = {
  solidity: "0.8.19",
  paths: {
    sources: './src'
  },
};

export default config;
