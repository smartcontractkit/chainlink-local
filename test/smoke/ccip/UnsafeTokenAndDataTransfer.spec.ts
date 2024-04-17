import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { ethers } from "hardhat";
import { expect } from "chai";

describe("CCIPSender_Unsafe", function () {

    async function deploy() {
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

        const CCIPReceiver_UnsafeFactory = await ethers.getContractFactory("CCIPReceiver_Unsafe");
        const CCIPReceiver_Unsafe = await CCIPReceiver_UnsafeFactory.deploy(config.destinationRouter_);

        const ccipBnMFactory = await ethers.getContractFactory("BurnMintERC677Helper");
        const ccipBnM = ccipBnMFactory.attach(config.ccipBnM_);

        return { localSimulator, CCIPSender_Unsafe, CCIPReceiver_Unsafe, config, ccipBnM };
    }

    it("should transfer Hello World and 100 CCIP_BnM tokens", async function () {
        const { CCIPSender_Unsafe, CCIPReceiver_Unsafe, config, ccipBnM } = await loadFixture(deploy);

        const ONE_ETHER = 1_000_000_000_000_000_000n;

        await ccipBnM.drip(CCIPSender_Unsafe.target);
        expect(await ccipBnM.totalSupply()).to.deep.equal(ONE_ETHER);

        const ccipSenderUnsafeBalanceBefore = await ccipBnM.balanceOf(CCIPSender_Unsafe.target);
        const ccipReceiverUnsafeBalanceBefore = await ccipBnM.balanceOf(CCIPReceiver_Unsafe.target);

        const textToSend = `Hello World`;
        const amountToSend = 100n;

        await CCIPSender_Unsafe.send(CCIPReceiver_Unsafe.target, textToSend, config.chainSelector_, config.ccipBnM_, amountToSend);

        const ccipSenderUnsafeBalanceAfter = await ccipBnM.balanceOf(CCIPSender_Unsafe.target);
        const ccipReceiverUnsafeBalanceAfter = await ccipBnM.balanceOf(CCIPReceiver_Unsafe.target);
        expect(ccipSenderUnsafeBalanceAfter).to.deep.equal(ccipSenderUnsafeBalanceBefore - amountToSend);
        expect(ccipReceiverUnsafeBalanceAfter).to.deep.equal(ccipReceiverUnsafeBalanceBefore + amountToSend);

        const received = await CCIPReceiver_Unsafe.text();
        expect(received).to.equal(textToSend);
    });
});

