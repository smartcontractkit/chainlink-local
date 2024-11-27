const { ethers } = require("hardhat");
const { setBalance } = require("@nomicfoundation/hardhat-toolbox/network-helpers");

const LinkTokenAbi = require("../../abi/LinkToken.json");

/**
 * Requests LINK tokens from the faucet and returns the transaction hash
 *
 * @param {string} linkAddress The address of the LINK contract on the current network
 * @param {string} to The address to send LINK to
 * @param {bigint} amount The amount of LINK to request
 * @returns {Promise<string>} Promise resolving to the transaction hash of the fund transfer
 */
async function requestLinkFromFaucet(linkAddress, to, amount) {
    const LINK_FAUCET_ADDRESS = `0x4281eCF07378Ee595C564a59048801330f3084eE`;
    const linkFaucetImpersonated = await ethers.getImpersonatedSigner(LINK_FAUCET_ADDRESS);

    const linkToken = new ethers.Contract(linkAddress, LinkTokenAbi, ethers.provider);
    const tx = await linkToken.connect(linkFaucetImpersonated).transfer(to, amount);

    return tx.hash;
}

/**
 * Requests native coins from the faucet
 * 
 * @param {string} to The address to send coins to
 * @param {bigint} amount The amount of coins to request
 */
async function requestNativeFromFaucet(to, amount) {
    await setBalance(to, amount);
}

module.exports = {
    requestLinkFromFaucet,
    requestNativeFromFaucet
};