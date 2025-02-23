const { ethers } = require("hardhat");

const { ReportV2, ReportV3, ReportV4 } = require("./ReportVersions");

class MockReportGenerator {
    #abi_encoder;

    constructor(initialPrice) {
        // uint256(keccak256(abi.encodePacked("Mock Data Streams DON")));
        this.i_donDigest = BigInt(ethers.keccak256(ethers.toUtf8Bytes("Mock Data Streams DON")));
        this.i_donAddress = ethers.computeAddress("0x" + this.i_donDigest.toString(16));

        this.i_reportV2MockFeedId = "0x0002777777777777777777777777777777777777777777777777777777777777";
        this.i_reportV3MockFeedId = "0x0003777777777777777777777777777777777777777777777777777777777777";
        this.i_reportV4MockFeedId = "0x0004777777777777777777777777777777777777777777777777777777777777";

        this.updatePrice(initialPrice);

        this.s_expiresPeriod = 86400; // 1 day
        this.s_marketStatus = 2; // 0 (Unknown), 1 (Closed), 2 (Open)
        this.s_nativeFee = 0; // 0 by default
        this.s_linkFee = 0; // 0 by default

        this.#abi_encoder = ethers.AbiCoder.defaultAbiCoder();
    }

    generateReportV2WithData(report) {
        const reportData = this.#abi_encoder.encode(["bytes32", "uint32", "uint32", "uint192", "uint192", "uint32", "int192"], [report.feedId, report.validFromTimestamp, report.observationsTimestamp, report.nativeFee, report.linkFee, report.expiresAt, report.benchmarkPrice]);
        const signedReport = this.#signReport(reportData);
        return signedReport;
    }

    generateReportV3WithData(report) {
        const reportData = this.#abi_encoder.encode(["bytes32", "uint32", "uint32", "uint192", "uint192", "uint32", "int192", "int192", "int192"], [report.feedId, report.validFromTimestamp, report.observationsTimestamp, report.nativeFee, report.linkFee, report.expiresAt, report.price, report.bid, report.ask]);
        const signedReport = this.#signReport(reportData);
        return signedReport;
    }

    generateReportV4WithData(report) {
        const reportData = this.#abi_encoder.encode(["bytes32", "uint32", "uint32", "uint192", "uint192", "uint32", "int192", "uint8"], [report.feedId, report.validFromTimestamp, report.observationsTimestamp, report.nativeFee, report.linkFee, report.expiresAt, report.price, report.marketStatus]);
        const signedReport = this.#signReport(reportData);
        return signedReport;
    }

    async generateReportV2() {
        const latestBlock = await ethers.provider.getBlock("latest");
        const currentTimestamp = latestBlock.timestamp;

        const report = new ReportV2({
            feedId: this.i_reportV2MockFeedId,
            validFromTimestamp: currentTimestamp,
            observationsTimestamp: currentTimestamp,
            nativeFee: this.s_nativeFee,
            linkFee: this.s_linkFee,
            expiresAt: currentTimestamp + this.s_expiresPeriod,
            benchmarkPrice: this.s_price,
        });

        const signedReport = this.generateReportV2WithData(report);

        return { signedReport, report };
    }

    async generateReportV3() {
        const latestBlock = await ethers.provider.getBlock("latest");
        const currentTimestamp = latestBlock.timestamp;

        const report = new ReportV3({
            feedId: this.i_reportV3MockFeedId,
            validFromTimestamp: currentTimestamp,
            observationsTimestamp: currentTimestamp,
            nativeFee: this.s_nativeFee,
            linkFee: this.s_linkFee,
            expiresAt: currentTimestamp + this.s_expiresPeriod,
            price: this.s_price,
            bid: this.s_bid,
            ask: this.s_ask,
        });

        const signedReport = this.generateReportV3WithData(report);

        return { signedReport, report };
    }

    async generateReportV4() {
        const latestBlock = await ethers.provider.getBlock("latest");
        const currentTimestamp = latestBlock.timestamp;

        const report = new ReportV4({
            feedId: this.i_reportV4MockFeedId,
            validFromTimestamp: currentTimestamp,
            observationsTimestamp: currentTimestamp,
            nativeFee: this.s_nativeFee,
            linkFee: this.s_linkFee,
            expiresAt: currentTimestamp + this.s_expiresPeriod,
            price: this.s_price,
            marketStatus: this.s_marketStatus,
        });

        const signedReport = this.generateReportV4WithData(report);

        return { signedReport, report };
    }

    updatePrice(price) {
        let priceAdjusted;
        let zeroOnePercent;
        if (BigInt(price) === price) {
            priceAdjusted = BigInt(price);
            zeroOnePercent = BigInt(1000);
        } else {
            priceAdjusted = price;
            zeroOnePercent = 1000;
        }

        this.s_price = priceAdjusted;
        const delta = priceAdjusted / zeroOnePercent; // 0.1% = 1/1000
        this.s_bid = priceAdjusted - delta;
        this.s_ask = priceAdjusted + delta;
    }

    updatePriceBidAndAsk(price, bid, ask) {
        // bid < price < ask
        if (bid >= price) throw new Error("Bid must be less than price");
        if (ask <= price) throw new Error("Ask must be greater than price");

        this.s_price = price;
        this.s_bid = bid;
        this.s_ask = ask;
    }

    updateExpiresPeriod(period) {
        this.s_expiresPeriod = period;
    }

    updateMarketStatus(status) {
        this.s_marketStatus = status;
    }

    updateFees(nativeFee, linkFee) {
        this.s_nativeFee = nativeFee;
        this.s_linkFee = linkFee;
    }

    getMockDonAddress() {
        return this.i_donAddress;
    }

    #signReport(reportData) {
        const N_2 = "0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0";

        // Create reportContext (bytes32[3])
        const reportContext = [
            `0x${this.i_donDigest.toString(16)}`, // bytes32(i_donDigest)
            `0x0000000000000000000000000000000000000000000000000000000000000000`, // not needed for mocks
            `0x0000000000000000000000000000000000000000000000000000000000000000`, // not needed for mocks
        ];

        const hashedReport = ethers.keccak256(reportData);

        const h = ethers.solidityPackedKeccak256(["bytes32", "bytes32[3]"], [hashedReport, reportContext]);

        const signer = new ethers.SigningKey(`0x${this.i_donDigest.toString(16)}`);
        let signature = signer.sign(h);

        if (BigInt(signature.s) > BigInt(N_2)) {
            const adjustedS = BigInt(N_2) - BigInt(signature.s);
            signature = {
                r: signature.r,
                s: `0x${adjustedS.toString(16)}`,
                v: 27
            }
        }

        const rawRs = [signature.r];
        const rawSs = [signature.s];
        const rawVs = `0x00000000000000000000000000000000000000000000000000000000000000${BigInt(signature.v).toString(16)}`;

        return this.#abi_encoder.encode(["bytes32[3]", "bytes", "bytes32[]", "bytes32[]", "bytes32"], [reportContext, reportData, rawRs, rawSs, rawVs]);
    }
}

module.exports = {
    ReportV2,
    ReportV3,
    ReportV4,
    MockReportGenerator
}