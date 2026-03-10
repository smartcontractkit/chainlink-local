import { defineConfig } from "hardhat/config";
import * as dotenv from "dotenv";

dotenv.config();

export default defineConfig({
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
    exclude: ["test", "vendor"],
    outputDir: "api_reference/solidity",
  },
});