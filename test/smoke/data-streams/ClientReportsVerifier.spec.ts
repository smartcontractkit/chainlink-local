import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { ethers } from "hardhat";
import { assert } from "chai";
import { MockReportGenerator } from "../../../scripts/data-streams/MockReportGenerator";

describe("ClientReportsVerifier", function () {

    async function deploy() {
        const localSimulatorFactory = await ethers.getContractFactory("DataStreamsLocalSimulator");
        const localSimulator = await localSimulatorFactory.deploy();

        const config: {
            wrappedNative_: string;
            linkToken_: string;
            mockVerifier_: string;
            mockVerifierProxy_: string;
            mockFeeManager_: string;
            mockRewardManager_: string;
        } = await localSimulator.configuration();

        const initialPrice = ethers.parseEther("1");
        const mockReportGenerator = new MockReportGenerator(initialPrice);

        const consumerFactory = await ethers.getContractFactory("ClientReportsVerifier");
        const consumer = await consumerFactory.deploy(config.mockVerifierProxy_);

        await mockReportGenerator.updateFees(ethers.parseEther("1"), ethers.parseEther("0.5"));

        await localSimulator.requestLinkFromFaucet(consumer.target, ethers.parseEther("1"));

        // const mockFeeManager = await ethers.getContractAt("MockFeeManager", config.mockFeeManager_);
        // await mockFeeManager.setMockDiscount(consumer.target, ethers.parseEther("1")); // 1e18 => 100% discount on fees

        return { consumer, initialPrice, mockReportGenerator };
    }

    it("should verify Data Streams report", async function () {
        const { consumer, initialPrice, mockReportGenerator } = await loadFixture(deploy);

        const { signedReport, report } = await mockReportGenerator.generateReportV3();

        await consumer.verifyReport(signedReport);

        const lastDecodedPrice = await consumer.lastDecodedPrice();
        assert(lastDecodedPrice === initialPrice);
    });
});

