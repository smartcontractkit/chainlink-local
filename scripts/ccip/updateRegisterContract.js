/**
 * @fileoverview Script to fetch and generate Register.sol with CCIP network details from Chainlink's API.
 * 
 * This script queries Chainlink's CCIP API endpoints to retrieve network configuration
 * details for all supported EVM chains. It fetches chain information (routers, selectors,
 * fee tokens) and token information (CCIP-BnM and CCIP-LnM addresses) for both testnet
 * and mainnet environments, then generates Register.sol with hardcoded network details
 * in the constructor.
 * 
 * Usage:
 *    CCIP_API_BASE_URL=<base_url> npm run update-register
 *    CCIP_API_BASE_URL=<base_url> node scripts/ccip/updateRegisterContract.js
 *
 * Requires: CCIP_API_BASE_URL environment variable (base URL for the CCIP API; paths are appended in code).
 *
 */

const fs = require("fs");
const path = require("path");

const CCIP_API_BASE_URL = process.env.CCIP_API_BASE_URL;
if (!CCIP_API_BASE_URL || CCIP_API_BASE_URL.trim() === "") {
  console.error("Error: CCIP_API_BASE_URL environment variable is required and must be set.");
  process.exit(1);
}

/** Normalized base URL (no trailing slash) for building API requests. */
const apiBase = CCIP_API_BASE_URL.trim().replace(/\/$/, "");

/**
 * Builds the full API URL for a given path and query parameters.
 * @param {string} path - Path segment (e.g. "chains", "tokens")
 * @param {Record<string, string>} params - Query parameters
 * @returns {string} Full URL
 */
function apiUrl(path, params) {
  const url = new URL(`${apiBase}/${path}`);
  Object.entries(params).forEach(([k, v]) => url.searchParams.set(k, v));
  return url.toString();
}

/**
 * Generates Register.sol with hardcoded network details in the constructor.
 * This makes the Register contract work in Hardhat and Remix without requiring
 * Foundry's vm functions or runtime JSON file reading.
 * 
 * @param {string} outputPath - Path to output Register.sol. Defaults to src/ccip/Register.sol
 * @param {Object} networkDetails - Network details object to generate from.
 */
function generateRegister(outputPath, networkDetails) {
    // Default output path
    const defaultOutputPath = path.join(__dirname, "../../src/ccip/Register.sol");
    const outputFilePath = outputPath || defaultOutputPath;
    
    // Generate Solidity code
    let constructorBody = "";
    
    // Sort chain IDs for consistent output
    const chainIds = Object.keys(networkDetails).sort((a, b) => Number(a) - Number(b));
    
    for (const chainId of chainIds) {
        const details = networkDetails[chainId];
        const name = details.name || `Chain ${chainId}`;
        
        // Handle empty strings for optional addresses
        const ccipBnMAddress = details.ccipBnMAddress === "" 
            ? "address(0)" 
            : `address(${details.ccipBnMAddress})`;
        const ccipLnMAddress = details.ccipLnMAddress === "" 
            ? "address(0)" 
            : `address(${details.ccipLnMAddress})`;
        
        constructorBody += `        // ${name}\n`;
        constructorBody += `        s_networkDetails[${chainId}] = NetworkDetails({\n`;
        constructorBody += `            chainSelector: ${details.chainSelector},\n`;
        constructorBody += `            routerAddress: address(${details.routerAddress}),\n`;
        constructorBody += `            linkAddress: address(${details.linkAddress}),\n`;
        constructorBody += `            wrappedNativeAddress: address(${details.wrappedNativeAddress}),\n`;
        constructorBody += `            ccipBnMAddress: ${ccipBnMAddress},\n`;
        constructorBody += `            ccipLnMAddress: ${ccipLnMAddress},\n`;
        constructorBody += `            rmnProxyAddress: address(${details.rmnProxyAddress}),\n`;
        constructorBody += `            registryModuleOwnerCustomAddress: address(${details.registryModuleOwnerCustomAddress}),\n`;
        constructorBody += `            tokenAdminRegistryAddress: address(${details.tokenAdminRegistryAddress})\n`;
        constructorBody += `        });\n\n`;
    }
    
    // Full constructor code for empty constructor case
    const fullConstructorCode = "    /// @notice Constructor to initialize network details for various chains.\n    constructor() {\n" + constructorBody + "    }";
    
    // Read the Register.sol file
    const registerPath = path.join(__dirname, "../../src/ccip/Register.sol");
    let registerCode = fs.readFileSync(registerPath, "utf8");
    
    // Replace the constructor with the generated one
    // Match either empty constructor or populated constructor
    const emptyConstructorRegex = /    \/\/\/ @notice Empty constructor\.\n    constructor\(\) \{\}/s;
    
    // Match populated constructor - match from the comment through the closing brace
    // The comment text is "Constructor to initialize the network details for various chains."
    const populatedConstructorRegex = /(    \/\/\/ @notice Constructor to initialize the network details for various chains\.\n    constructor\(\) \{)[\s\S]*?(\n    \})/;
    
    if (emptyConstructorRegex.test(registerCode)) {
        // Replace empty constructor
        registerCode = registerCode.replace(emptyConstructorRegex, fullConstructorCode);
    } else if (populatedConstructorRegex.test(registerCode)) {
        // Replace populated constructor - keep the comment, constructor declaration, and closing brace
        // Replace only the body (everything between "constructor() {" and the closing "}")
        // constructorBody already has proper indentation and ends with content (no trailing newlines after trim)
        registerCode = registerCode.replace(populatedConstructorRegex, (match, p1, p2) => {
            // p1 = comment + "constructor() {"
            // constructorBody = body content (trimmed to remove trailing whitespace)
            // p2 = "\n    }" (the closing brace with proper indentation)
            return p1 + '\n' + constructorBody.trimEnd() + p2;
        });
    } else {
        throw new Error("Could not find constructor in Register.sol. Expected either empty constructor or populated constructor with comment 'Constructor to initialize the network details for various chains.'");
    }
    
    // Write the generated file
    console.log(`Writing generated Register.sol to: ${outputFilePath}`);
    fs.writeFileSync(outputFilePath, registerCode, "utf8");
    
    console.log(`  Successfully generated Register.sol with ${chainIds.length} networks`);
    console.log(`  Output: ${outputFilePath}`);
}

/**
 * Fetches CCIP network details for a single environment from Chainlink's API.
 * 
 * @param {string} environment - The environment to fetch data for ("testnet" or "mainnet")
 * @returns {Promise<Object>} Network details object keyed by chain ID
 */
async function fetchNetworkDetails(environment) {
  const queryBase = { environment, outputKey: "chainId" };

  // Call Endpoint #1: chains
  const chainsRes = await fetch(apiUrl("chains", { ...queryBase, enrichFeeTokens: "true" }), {
    headers: { Accept: "application/json" }
  });
  if (!chainsRes.ok) {
    const body = await chainsRes.text();
    throw new Error(`Chains API HTTP ${chainsRes.status} ${chainsRes.statusText} for ${environment}\n${body}`);
  }
  const chainsData = await chainsRes.json();

  // Call Endpoint #2: tokens
  const tokensRes = await fetch(apiUrl("tokens", queryBase), {
    headers: { Accept: "application/json" }
  });
  if (!tokensRes.ok) {
    const body = await tokensRes.text();
    throw new Error(`Tokens API HTTP ${tokensRes.status} ${tokensRes.statusText} for ${environment}\n${body}`);
  }
  const tokensData = await tokensRes.json();

  // Process the data
  const networkDetails = {};
  const evmChains = chainsData.data.evm || {};
  const ccipBnM = tokensData.data["CCIP-BnM"] || {};
  const ccipLnM = tokensData.data["CCIP-LnM"] || {};

  // Iterate through all EVM chains
  for (const [chainId, chainInfo] of Object.entries(evmChains)) {
    // Find LINK token and wrapped native token from feeTokens
    const linkToken = chainInfo.feeTokens?.find(token => token.symbol === "LINK");
    const wrappedNativeToken = chainInfo.feeTokens?.find(token => token.symbol !== "LINK");

    // Get CCIP token addresses from tokens endpoint
    const bnMInfo = ccipBnM[chainId];
    const lnMInfo = ccipLnM[chainId];

    // Only include chains that have all required data
    if (linkToken && wrappedNativeToken && chainInfo.router && chainInfo.rmn && 
        chainInfo.registryModule && chainInfo.tokenAdminRegistry) {
      networkDetails[chainId] = {
        name: chainInfo.displayName,
        chainSelector: chainInfo.selector,
        routerAddress: chainInfo.router,
        linkAddress: linkToken.address,
        wrappedNativeAddress: wrappedNativeToken.address,
        ccipBnMAddress: bnMInfo?.tokenAddress || "",
        ccipLnMAddress: lnMInfo?.tokenAddress || "",
        rmnProxyAddress: chainInfo.rmn,
        registryModuleOwnerCustomAddress: chainInfo.registryModule,
        tokenAdminRegistryAddress: chainInfo.tokenAdminRegistry
      };
    }
  }

  return networkDetails;
}

/**
 * Fetches CCIP network details from Chainlink's API and generates Register.sol with hardcoded values.
 * Always fetches both testnet and mainnet network details.
 */
async function fetchAndGenerate() {
  try {
    let networkDetails = {};
    const environments = ["testnet", "mainnet"];

    // Fetch data for both environments in parallel
    console.log(`Fetching network details for: ${environments.join(", ")}...`);
    const fetchPromises = environments.map(env => fetchNetworkDetails(env));
    const results = await Promise.all(fetchPromises);

    // Merge network details from both environments
    // If there are duplicate chain IDs, mainnet takes precedence
    for (let i = 0; i < environments.length; i++) {
      const env = environments[i];
      const details = results[i];
      const envCount = Object.keys(details).length;
      console.log(`  ${env}: ${envCount} networks`);
      
      // Merge details, with later environments (mainnet) taking precedence
      for (const [chainId, chainDetails] of Object.entries(details)) {
        networkDetails[chainId] = chainDetails;
      }
    }

    // Generate Register.sol directly from API data
    const totalNetworks = Object.keys(networkDetails).length;
    console.log(`\nGenerating Register.sol with ${totalNetworks} total networks...`);
    generateRegister(null, networkDetails);
    
    console.log("\n  Register.sol generated successfully!");
  } catch (err) {
    console.error("Error:", err.message);
    process.exit(1);
  }
}

// Run the function
fetchAndGenerate();