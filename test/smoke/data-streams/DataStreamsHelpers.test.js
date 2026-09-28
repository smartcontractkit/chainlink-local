// Local (no RPC) tests for the Hardhat 3 Data Streams JavaScript helpers. Run with `npm run hardhat-test-js`.
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { network } from "hardhat";

import { MockReportGenerator } from "../../../scripts/data-streams/MockReportGenerator.js";
import { requestNativeFromFaucet } from "../../../scripts/data-streams/DataStreamsLocalSimulatorFork.js";

describe("Data Streams JS helpers (Hardhat 3)", () => {
    it("MockReportGenerator produces a V3 report that verifies on-chain", async () => {
        // This repo compiles without the optimizer, so the simulator exceeds the default initcode size limit.
        const connection = await network.connect({ override: { allowUnlimitedContractSize: true } });
        const { ethers } = connection;

        const localSimulator = await (
            await ethers.getContractFactory("src/data-streams/DataStreamsLocalSimulator.sol:DataStreamsLocalSimulator")
        ).deploy();
        const config = await localSimulator.configuration();

        const initialPrice = ethers.parseEther("1");
        const mockReportGenerator = new MockReportGenerator(connection, initialPrice);
        await mockReportGenerator.updateFees(ethers.parseEther("1"), ethers.parseEther("0.5"));

        const consumer = await (
            await ethers.getContractFactory("src/test/data-streams/ClientReportsVerifier.sol:ClientReportsVerifier")
        ).deploy(config.mockVerifierProxy_);
        await (await localSimulator.requestLinkFromFaucet(await consumer.getAddress(), ethers.parseEther("1"))).wait();

        const { signedReport } = await mockReportGenerator.generateReportV3();
        await (await consumer.verifyReport(signedReport)).wait();

        assert.equal(await consumer.lastDecodedPrice(), initialPrice);
    });

    it("requestNativeFromFaucet sets the native balance", async () => {
        const connection = await network.connect();
        const to = connection.ethers.Wallet.createRandom().address;
        await requestNativeFromFaucet(connection, to, 12345n);
        assert.equal(await connection.ethers.provider.getBalance(to), 12345n);
    });
});
