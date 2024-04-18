import {ethers} from "hardhat";
import {TransactionReceipt} from "ethers";
import {setBalance} from "@nomicfoundation/hardhat-toolbox/network-helpers";

import RouterAbi from "../abi/Router.json";
import LinkTokenAbi from "../abi/LinkToken.json";
import EVM2EVMOnRampAbi from "../abi/EVM2EVMOnRamp.json";
import EVM2EVMOffRampAbi from "../abi/EVM2EVMOffRamp.json";

export type Evm2EvmMessage = {
  sourceChainSelector: bigint;
  sender: string;
  receiver: string;
  sequenceNumber: bigint;
  gasLimit: bigint;
  strict: boolean;
  nonce: bigint;
  feeToken: string;
  feeTokenAmount: bigint;
  data: string;
  tokenAmounts: [];
  sourceTokenData: [];
  messageId: string;
};

export type OffRamp = {
  sourceChainSelector: bigint;
  offRamp: string;
};

/**
 * Requests LINK tokens from the faucet and returns the transaction hash
 *
 * @param {string} linkAddress The address of the LINK contract on the current network
 * @param {string} to The address to send LINK to
 * @param {bigint} amount The amount of LINK to request
 * @returns {Promise<string>} Promise resolving to the transaction hash of the fund transfer
 */
export async function requestLinkFromTheFaucet(linkAddress: string, to: string, amount: bigint): Promise<string> {
  const LINK_FAUCET_ADDRESS = `0x4281eCF07378Ee595C564a59048801330f3084eE`;
  const linkFaucetImpersonated = await ethers.getImpersonatedSigner(LINK_FAUCET_ADDRESS);

  const linkToken = new ethers.Contract(linkAddress, LinkTokenAbi, ethers.provider);
  const tx = await linkToken.connect(linkFaucetImpersonated).transfer(to, amount);

  return tx.hash;
}

/**
 * Parses a transaction receipt to extract the sent message
 * Scans through transaction logs to find a `CCIPSendRequested` event and then decodes it to Evm2EvmMessage
 *
 * @param {TransactionReceipt} receipt - The transaction receipt from the `ccipSend` call
 * @returns {Evm2EvmMessage | null} Returns either the sent message or null if provided receipt does not contain `CCIPSendRequested` log
 */
export function getEvm2EvmMessage(receipt: TransactionReceipt): Evm2EvmMessage | null {
  const evm2EvmOnRampInterface = new ethers.Interface(EVM2EVMOnRampAbi);

  for (const log of receipt.logs) {
    try {
      const parsedLog = evm2EvmOnRampInterface.parseLog(log);
      if (parsedLog?.name == `CCIPSendRequested`) {
        const [
          sourceChainSelector,
          sender,
          receiver,
          sequenceNumber,
          gasLimit,
          strict,
          nonce,
          feeToken,
          feeTokenAmount,
          data,
          tokenAmountsRaw,
          sourceTokenDataRaw,
          messageId,
        ] = parsedLog?.args[0];
        const tokenAmounts = tokenAmountsRaw.map(([token, amount]) => ({
          token,
          amount,
        }));
        const sourceTokenData = sourceTokenDataRaw.map(data => data);
        const evm2EvmMessage: Evm2EvmMessage = {
          sourceChainSelector,
          sender,
          receiver,
          sequenceNumber,
          gasLimit,
          strict,
          nonce,
          feeToken,
          feeTokenAmount,
          data,
          tokenAmounts,
          sourceTokenData,
          messageId,
        };
        return evm2EvmMessage;
      }
    } catch (error) {
      return null;
    }
  }

  return null;
}

/**
 * Routes the sent message from the source network (got it from the `getEvm2EvmMessage` function) on the destination (current) network
 *
 * @param {string} routerAddress - Address of the destination Router (Router on the current network)
 * @param {Evm2EvmMessage} evm2EvmMessage - Sent cross-chain message, (got from the `getEvm2EvmMessage` function)
 * @returns {Promise<void>} Either resolves with no value if the message is successfully routed, or reverts
 * @throws {Error} Fails if no off-ramp matches the message's source chain selector or if calling `router.getOffRamps()`
 */
export async function routeMessage(routerAddress: string, evm2EvmMessage: Evm2EvmMessage): Promise<void> {
  const router = new ethers.Contract(routerAddress, RouterAbi, ethers.provider);

  let offRamps: OffRamp[];

  try {
    const offRampsRaw = await router.getOffRamps();
    offRamps = offRampsRaw.map(([sourceChainSelector, offRamp]) => ({sourceChainSelector, offRamp}));
  } catch (error) {
    throw new Error(`Calling router.getOffRamps threw the following error: ${error}`);
  }

  for (const offRamp of offRamps) {
    if (offRamp.sourceChainSelector == evm2EvmMessage.sourceChainSelector) {
      const evm2EvmOffRamp = new ethers.Contract(offRamp.offRamp, EVM2EVMOffRampAbi);

      const self = await ethers.getImpersonatedSigner(offRamp.offRamp);
      setBalance(self.address, 100n ** 18n);

      const offchainTokenData: string[] = new Array(evm2EvmMessage.tokenAmounts.length).fill("0x");

      // This is crucial step, executeSingleMessage MUST be called by the OffRamp contract itself
      await evm2EvmOffRamp.connect(self).executeSingleMessage(evm2EvmMessage, offchainTokenData);

      return;
    }
  }

  throw new Error(`No offRamp contract found, message has not been routed. Check your input parameters please`);
}
