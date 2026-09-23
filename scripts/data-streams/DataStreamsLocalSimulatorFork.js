/**
 * Hardhat 3 helpers for Data Streams fork tests. Every function takes the `NetworkConnection` returned by
 * `network.connect()` and requires the `@nomicfoundation/hardhat-ethers` plugin (it uses `connection.ethers`).
 */

const LINK_FAUCET_ADDRESS = "0x4281eCF07378Ee595C564a59048801330f3084eE";

/**
 * Requests LINK tokens from the faucet and returns the transaction hash
 *
 * @param {object} connection Network connection from `network.connect()`
 * @param {string} linkAddress The address of the LINK contract on the current network
 * @param {string} to The address to send LINK to
 * @param {bigint} amount The amount of LINK to request
 * @returns {Promise<string>} Promise resolving to the transaction hash of the fund transfer
 */
export async function requestLinkFromFaucet(connection, linkAddress, to, amount) {
    const { ethers } = connection;
    await connection.provider.request({ method: "hardhat_impersonateAccount", params: [LINK_FAUCET_ADDRESS] });
    await requestNativeFromFaucet(connection, LINK_FAUCET_ADDRESS, ethers.parseEther("100"));
    const faucet = await ethers.getSigner(LINK_FAUCET_ADDRESS);

    const linkToken = new ethers.Contract(linkAddress, ["function transfer(address to, uint256 amount) returns (bool)"], faucet);
    const tx = await linkToken.transfer(to, amount);

    return tx.hash;
}

/**
 * Requests native coins from the faucet (sets the balance of `to`)
 *
 * @param {object} connection Network connection from `network.connect()`
 * @param {string} to The address to send coins to
 * @param {bigint} amount The amount of coins to request
 */
export async function requestNativeFromFaucet(connection, to, amount) {
    await connection.provider.request({ method: "hardhat_setBalance", params: [to, `0x${BigInt(amount).toString(16)}`] });
}
