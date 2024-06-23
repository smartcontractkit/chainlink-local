import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { ethers } from "hardhat";
import { expect } from "chai";

describe("BasicDataConsumerV3", function () {

    async function deploy() {
        const decimals = 8;
        const initialAnswer = 100000000000;

        const mockV3AggregatorFactory = await ethers.getContractFactory("MockV3Aggregator");
        const mockV3Aggregator = await mockV3AggregatorFactory.deploy(decimals, initialAnswer);

        const basicDataConsumerV3Factory = await ethers.getContractFactory("BasicDataConsumerV3");
        const basicDataConsumerV3 = await basicDataConsumerV3Factory.deploy(mockV3Aggregator.target);

        return { initialAnswer, basicDataConsumerV3 };
    }

    it("should return answer from mock aggregator", async function () {
        const { initialAnswer, basicDataConsumerV3 } = await loadFixture(deploy);

        const answer = await basicDataConsumerV3.getChainlinkDataFeedLatestAnswer();

        expect(answer).to.deep.equal(initialAnswer);
    });
});

