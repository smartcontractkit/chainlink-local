import { ethers, network } from "hardhat";
import { getEvm2EvmMessage, requestLinkFromTheFaucet, routeMessage } from "../CCIPLocalSimulatorFork";

// 1st Terminal: npx hardhat node
// 2nd Terminal: npx hardhat run ./scripts/examples/UnsafeTokenAndDataTransferFork.ts --network localhost

async function main() {
    const ETHEREUM_SEPOLIA_RPC_URL = process.env.ETHEREUM_SEPOLIA_RPC_URL;
    const ARBITRUM_SEPOLIA_RPC_URL = process.env.ARBITRUM_SEPOLIA_RPC_URL;

    await network.provider.request({
        method: "hardhat_reset",
        params: [{
            forking: {
                jsonRpcUrl: ARBITRUM_SEPOLIA_RPC_URL,
                blockNumber: 33079804
            },
        }],
    });

    const ccipRouterAddressArbSepolia = `0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165`;
    const ccipBnMTokenAddressArbSepolia = `0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D`

    const CCIPReceiver_UnsafeFactory = await ethers.getContractFactory("CCIPReceiver_Unsafe");
    let CCIPReceiver_Unsafe = await CCIPReceiver_UnsafeFactory.deploy(ccipRouterAddressArbSepolia);

    console.log("Deployed CCIPReceiver_Unsafe to: ", CCIPReceiver_Unsafe.target);

    const ccipBnMFactory = await ethers.getContractFactory("BurnMintERC677Helper");
    const ccipBnMArbSepolia = ccipBnMFactory.attach(ccipBnMTokenAddressArbSepolia);

    console.log(`Balance of CCIPReceiver_Unsafe before: `, await ccipBnMArbSepolia.balanceOf(CCIPReceiver_Unsafe.target));

    console.log("-------------------------------------------");


    await network.provider.request({
        method: "hardhat_reset",
        params: [{
            forking: {
                jsonRpcUrl: ETHEREUM_SEPOLIA_RPC_URL,
                blockNumber: 5663645
            },
        }],
    });

    const linkTokenAddressSepolia = `0x779877A7B0D9E8603169DdbD7836e478b4624789`;
    const ccipRouterAddressSepolia = `0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59`;
    const ccipBnMTokenAddressSepolia = `0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05`;

    const CCIPSender_UnsafeFactory = await ethers.getContractFactory("CCIPSender_Unsafe");
    const CCIPSender_Unsafe = await CCIPSender_UnsafeFactory.deploy(linkTokenAddressSepolia, ccipRouterAddressSepolia);

    console.log("Deployed CCIPSender_Unsafe to: ", CCIPSender_Unsafe.target);

    const ccipBnMSepolia = ccipBnMFactory.attach(ccipBnMTokenAddressSepolia);

    await ccipBnMSepolia.drip(CCIPSender_Unsafe.target);

    const linkAmountForFees = 5000000000000000000n; // 5 LINK
    await requestLinkFromTheFaucet(linkTokenAddressSepolia, await CCIPSender_Unsafe.getAddress(), linkAmountForFees);

    const textToSend = `Hello World`;
    const amountToSend = 100;
    const arbSepoliaChainSelector = 3478487238524512106n;

    console.log(`Balance of CCIPSender_Unsafe before: `, await ccipBnMSepolia.balanceOf(CCIPSender_Unsafe.target));

    const tx = await CCIPSender_Unsafe.send(CCIPReceiver_Unsafe.target, textToSend, arbSepoliaChainSelector, ccipBnMTokenAddressSepolia, amountToSend);
    console.log("Transaction hash: ", tx.hash);
    const receipt = await tx.wait();
    if (!receipt) return;
    const evm2EvmMessage = getEvm2EvmMessage(receipt);

    console.log(`Balance of CCIPSender_Unsafe after: `, await ccipBnMSepolia.balanceOf(CCIPSender_Unsafe.target));

    console.log("-------------------------------------------");

    await network.provider.request({
        method: "hardhat_reset",
        params: [{
            forking: {
                jsonRpcUrl: ARBITRUM_SEPOLIA_RPC_URL,
                blockNumber: 33079804
            },
        }],
    });

    // We must redeploy it because of the network reset but it will be deployed to the same address because of the CREATE opcode: address = keccak256(rlp([sender_address,sender_nonce]))[12:]
    CCIPReceiver_Unsafe = await CCIPReceiver_UnsafeFactory.deploy(ccipRouterAddressArbSepolia);

    if (!evm2EvmMessage) return;
    await routeMessage(ccipRouterAddressArbSepolia, evm2EvmMessage);

    const received = await CCIPReceiver_Unsafe.text();
    console.log(`Received:`, received);

    console.log(`Balance of CCIPReceiver_Unsafe after: `, await ccipBnMArbSepolia.balanceOf(CCIPReceiver_Unsafe.target));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
