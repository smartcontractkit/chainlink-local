import { ethers } from "hardhat";

// npx hardhat run ./scripts/examples/UnsafeTokenAndDataTransfer.ts

async function main() {
    const localSimulatorFactory = await ethers.getContractFactory("CCIPLocalSimulator");
    const localSimulator = await localSimulatorFactory.deploy();

    const config: {
        chainSelector_: bigint;
        sourceRouter_: string;
        destinationRouter_: string;
        wrappedNative_: string;
        linkToken_: string;
        ccipBnM_: string;
        ccipLnM_: string;
    } = await localSimulator.configuration();

    const CCIPSender_UnsafeFactory = await ethers.getContractFactory("CCIPSender_Unsafe");
    const CCIPSender_Unsafe = await CCIPSender_UnsafeFactory.deploy(config.linkToken_, config.sourceRouter_);

    console.log("Deployed CCIPSender_Unsafe to: ", CCIPSender_Unsafe.target);

    const CCIPReceiver_UnsafeFactory = await ethers.getContractFactory("CCIPReceiver_Unsafe");
    const CCIPReceiver_Unsafe = await CCIPReceiver_UnsafeFactory.deploy(config.destinationRouter_);

    console.log("Deployed CCIPReceiver_Unsafe to: ", CCIPReceiver_Unsafe.target);

    console.log("-------------------------------------------")

    const ccipBnMFactory = await ethers.getContractFactory("BurnMintERC677Helper");
    const ccipBnM = ccipBnMFactory.attach(config.ccipBnM_);

    await ccipBnM.drip(CCIPSender_Unsafe.target);

    const textToSend = `Hello World`;
    const amountToSend = 100;

    console.log(`Balance of CCIPSender_Unsafe before: `, await ccipBnM.balanceOf(CCIPSender_Unsafe.target));
    console.log(`Balance of CCIPReceiver_Unsafe before: `, await ccipBnM.balanceOf(CCIPReceiver_Unsafe.target));
    console.log("-------------------------------------------")

    const tx = await CCIPSender_Unsafe.send(CCIPReceiver_Unsafe.target, textToSend, config.chainSelector_, config.ccipBnM_, amountToSend);
    console.log("Transaction hash: ", tx.hash);

    console.log("-------------------------------------------")
    console.log(`Balance of CCIPSender_Unsafe after: `, await ccipBnM.balanceOf(CCIPSender_Unsafe.target));
    console.log(`Balance of CCIPReceiver_Unsafe after: `, await ccipBnM.balanceOf(CCIPReceiver_Unsafe.target));

    console.log("-------------------------------------------")
    const received = await CCIPReceiver_Unsafe.text();
    console.log(`Received:`, received);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
