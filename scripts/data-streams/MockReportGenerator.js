const { ethers } = require("hardhat");

const {
    ReportV1,
    ReportV2,
    ReportV3,
    ReportV4,
    ReportV5,
    ReportV6,
    ReportV7,
    ReportV8,
    ReportV9,
    ReportV10,
    ReportV11,
    ReportV12,
    ReportV13,
} = require("./ReportVersions");

/**
 * Utility that builds deterministic mock Data Streams signed reports for local testing.
 */
class MockReportGenerator {
    #abi_encoder;

    /**
     * @param {bigint|number} initialPrice Initial benchmark price used for generated reports.
     */
    constructor(initialPrice) {
        // uint256(keccak256(abi.encodePacked("Mock Data Streams DON")));
        this.i_donDigest = BigInt(ethers.keccak256(ethers.toUtf8Bytes("Mock Data Streams DON")));
        this.i_donAddress = ethers.computeAddress("0x" + this.i_donDigest.toString(16));

        this.i_reportV1MockFeedId = "0x0001777777777777777777777777777777777777777777777777777777777777";
        this.i_reportV2MockFeedId = "0x0002777777777777777777777777777777777777777777777777777777777777";
        this.i_reportV3MockFeedId = "0x0003777777777777777777777777777777777777777777777777777777777777";
        this.i_reportV4MockFeedId = "0x0004777777777777777777777777777777777777777777777777777777777777";
        this.i_reportV5MockFeedId = "0x0005777777777777777777777777777777777777777777777777777777777777";
        this.i_reportV6MockFeedId = "0x0006777777777777777777777777777777777777777777777777777777777777";
        this.i_reportV7MockFeedId = "0x0007777777777777777777777777777777777777777777777777777777777777";
        this.i_reportV8MockFeedId = "0x0008777777777777777777777777777777777777777777777777777777777777";
        this.i_reportV9MockFeedId = "0x0009777777777777777777777777777777777777777777777777777777777777";
        this.i_reportV10MockFeedId = "0x000a777777777777777777777777777777777777777777777777777777777777";
        this.i_reportV11MockFeedId = "0x000b777777777777777777777777777777777777777777777777777777777777";
        this.i_reportV12MockFeedId = "0x000c777777777777777777777777777777777777777777777777777777777777";
        this.i_reportV13MockFeedId = "0x000d777777777777777777777777777777777777777777777777777777777777";

        this.updatePrice(initialPrice);

        this.s_expiresPeriod = 86400; // 1 day
        this.s_marketStatus = 2; // 0 (Unknown), 1 (Closed), 2 (Open)
        this.s_nativeFee = 0; // 0 by default
        this.s_linkFee = 0; // 0 by default

        this.#abi_encoder = ethers.AbiCoder.defaultAbiCoder();
    }

    /**
     * Encodes and signs a version 1 report payload.
     *
     * @param {ReportV1} report Report object to encode.
     * @returns {string} ABI-encoded signed report blob.
     */
    generateReportV1WithData(report) {
        const reportData = this.#abi_encoder.encode(
            ["bytes32", "uint32", "int192", "int192", "int192", "uint64", "bytes32", "uint64", "uint64"],
            [report.feedId, report.observationsTimestamp, report.benchmarkPrice, report.bid, report.ask, report.currentBlockNum, report.currentBlockHash, report.validFromBlockNum, report.currentBlockTimestamp]
        );
        const signedReport = this.#signReport(reportData);
        return signedReport;
    }

    /**
     * Encodes and signs a version 2 report payload.
     *
     * @param {ReportV2} report Report object to encode.
     * @returns {string} ABI-encoded signed report blob.
     */
    generateReportV2WithData(report) {
        const reportData = this.#abi_encoder.encode(["bytes32", "uint32", "uint32", "uint192", "uint192", "uint32", "int192"], [report.feedId, report.validFromTimestamp, report.observationsTimestamp, report.nativeFee, report.linkFee, report.expiresAt, report.benchmarkPrice]);
        const signedReport = this.#signReport(reportData);
        return signedReport;
    }

    /**
     * Encodes and signs a version 3 report payload.
     *
     * @param {ReportV3} report Report object to encode.
     * @returns {string} ABI-encoded signed report blob.
     */
    generateReportV3WithData(report) {
        const reportData = this.#abi_encoder.encode(["bytes32", "uint32", "uint32", "uint192", "uint192", "uint32", "int192", "int192", "int192"], [report.feedId, report.validFromTimestamp, report.observationsTimestamp, report.nativeFee, report.linkFee, report.expiresAt, report.price, report.bid, report.ask]);
        const signedReport = this.#signReport(reportData);
        return signedReport;
    }

    /**
     * Encodes and signs a version 4 report payload.
     *
     * @param {ReportV4} report Report object to encode.
     * @returns {string} ABI-encoded signed report blob.
     */
    generateReportV4WithData(report) {
        const reportData = this.#abi_encoder.encode(["bytes32", "uint32", "uint32", "uint192", "uint192", "uint32", "int192", "uint32"], [report.feedId, report.validFromTimestamp, report.observationsTimestamp, report.nativeFee, report.linkFee, report.expiresAt, report.price, report.marketStatus]);
        const signedReport = this.#signReport(reportData);
        return signedReport;
    }

    /**
     * Encodes and signs a version 5 report payload.
     *
     * @param {ReportV5} report Report object to encode.
     * @returns {string} ABI-encoded signed report blob.
     */
    generateReportV5WithData(report) {
        const reportData = this.#abi_encoder.encode(
            ["bytes32", "uint32", "uint32", "uint192", "uint192", "uint32", "int192", "uint32", "uint32"],
            [report.feedId, report.validFromTimestamp, report.observationsTimestamp, report.nativeFee, report.linkFee, report.expiresAt, report.rate, report.timestamp, report.duration]
        );
        const signedReport = this.#signReport(reportData);
        return signedReport;
    }

    /**
     * Encodes and signs a version 6 report payload.
     *
     * @param {ReportV6} report Report object to encode.
     * @returns {string} ABI-encoded signed report blob.
     */
    generateReportV6WithData(report) {
        const reportData = this.#abi_encoder.encode(
            ["bytes32", "uint32", "uint32", "uint192", "uint192", "uint32", "int192", "int192", "int192", "int192", "int192"],
            [report.feedId, report.validFromTimestamp, report.observationsTimestamp, report.nativeFee, report.linkFee, report.expiresAt, report.price, report.price2, report.price3, report.price4, report.price5]
        );
        const signedReport = this.#signReport(reportData);
        return signedReport;
    }

    /**
     * Encodes and signs a version 7 report payload.
     *
     * @param {ReportV7} report Report object to encode.
     * @returns {string} ABI-encoded signed report blob.
     */
    generateReportV7WithData(report) {
        const reportData = this.#abi_encoder.encode(
            ["bytes32", "uint32", "uint32", "uint192", "uint192", "uint32", "int192"],
            [report.feedId, report.validFromTimestamp, report.observationsTimestamp, report.nativeFee, report.linkFee, report.expiresAt, report.exchangeRate]
        );
        const signedReport = this.#signReport(reportData);
        return signedReport;
    }

    /**
     * Encodes and signs a version 8 report payload.
     *
     * @param {ReportV8} report Report object to encode.
     * @returns {string} ABI-encoded signed report blob.
     */
    generateReportV8WithData(report) {
        const reportData = this.#abi_encoder.encode(
            ["bytes32", "uint32", "uint32", "uint192", "uint192", "uint32", "uint64", "int192", "uint32"],
            [report.feedId, report.validFromTimestamp, report.observationsTimestamp, report.nativeFee, report.linkFee, report.expiresAt, report.lastUpdateTimestamp, report.midPrice, report.marketStatus]
        );
        const signedReport = this.#signReport(reportData);
        return signedReport;
    }

    /**
     * Encodes and signs a version 9 report payload.
     *
     * @param {ReportV9} report Report object to encode.
     * @returns {string} ABI-encoded signed report blob.
     */
    generateReportV9WithData(report) {
        const reportData = this.#abi_encoder.encode(
            ["bytes32", "uint32", "uint32", "uint192", "uint192", "uint32", "int192", "uint64", "int192", "uint32"],
            [report.feedId, report.validFromTimestamp, report.observationsTimestamp, report.nativeFee, report.linkFee, report.expiresAt, report.navPerShare, report.navDate, report.aum, report.ripcord]
        );
        const signedReport = this.#signReport(reportData);
        return signedReport;
    }

    /**
     * Encodes and signs a version 10 report payload.
     *
     * @param {ReportV10} report Report object to encode.
     * @returns {string} ABI-encoded signed report blob.
     */
    generateReportV10WithData(report) {
        const reportData = this.#abi_encoder.encode(
            ["bytes32", "uint32", "uint32", "uint192", "uint192", "uint32", "uint64", "int192", "uint32", "int192", "int192", "uint32", "int192"],
            [report.feedId, report.validFromTimestamp, report.observationsTimestamp, report.nativeFee, report.linkFee, report.expiresAt, report.lastUpdateTimestamp, report.price, report.marketStatus, report.currentMultiplier, report.newMultiplier, report.activationDateTime, report.tokenizedPrice]
        );
        const signedReport = this.#signReport(reportData);
        return signedReport;
    }

    /**
     * Encodes and signs a version 11 report payload.
     *
     * @param {ReportV11} report Report object to encode.
     * @returns {string} ABI-encoded signed report blob.
     */
    generateReportV11WithData(report) {
        const reportData = this.#abi_encoder.encode(
            ["bytes32", "uint32", "uint32", "uint192", "uint192", "uint32", "int192", "uint64", "int192", "int192", "int192", "int192", "int192", "uint32"],
            [report.feedId, report.validFromTimestamp, report.observationsTimestamp, report.nativeFee, report.linkFee, report.expiresAt, report.mid, report.lastSeenTimestampNs, report.bid, report.bidVolume, report.ask, report.askVolume, report.lastTradedPrice, report.marketStatus]
        );
        const signedReport = this.#signReport(reportData);
        return signedReport;
    }

    /**
     * Encodes and signs a version 12 report payload.
     *
     * @param {ReportV12} report Report object to encode.
     * @returns {string} ABI-encoded signed report blob.
     */
    generateReportV12WithData(report) {
        const reportData = this.#abi_encoder.encode(
            ["bytes32", "uint32", "uint32", "uint192", "uint192", "uint32", "int192", "int192", "uint64", "uint32"],
            [report.feedId, report.validFromTimestamp, report.observationsTimestamp, report.nativeFee, report.linkFee, report.expiresAt, report.navPerShare, report.nextNavPerShare, report.navDate, report.ripcord]
        );
        const signedReport = this.#signReport(reportData);
        return signedReport;
    }

    /**
     * Encodes and signs a version 13 report payload.
     *
     * @param {ReportV13} report Report object to encode.
     * @returns {string} ABI-encoded signed report blob.
     */
    generateReportV13WithData(report) {
        const reportData = this.#abi_encoder.encode(
            ["bytes32", "uint32", "uint32", "uint192", "uint192", "uint32", "int192", "int192", "uint64", "uint64", "int192"],
            [report.feedId, report.validFromTimestamp, report.observationsTimestamp, report.nativeFee, report.linkFee, report.expiresAt, report.bestAsk, report.bestBid, report.askVolume, report.bidVolume, report.lastTradedPrice]
        );
        const signedReport = this.#signReport(reportData);
        return signedReport;
    }

    /**
     * Builds and signs a default version 1 report from current generator state.
     *
     * @returns {Promise<{signedReport: string, report: ReportV1}>} Signed payload and decoded report model.
     */
    async generateReportV1() {
        const latestBlock = await ethers.provider.getBlock("latest");
        const currentTimestamp = latestBlock.timestamp;
        const currentBlockNum = latestBlock.number;
        const previousBlockHash = currentBlockNum === 0
            ? "0x0000000000000000000000000000000000000000000000000000000000000000"
            : (await ethers.provider.getBlock(currentBlockNum - 1)).hash;

        const report = new ReportV1({
            feedId: this.i_reportV1MockFeedId,
            observationsTimestamp: currentTimestamp,
            benchmarkPrice: this.s_price,
            bid: this.s_bid,
            ask: this.s_ask,
            currentBlockNum: currentBlockNum,
            currentBlockHash: previousBlockHash,
            validFromBlockNum: currentBlockNum,
            currentBlockTimestamp: currentTimestamp,
        });

        const signedReport = this.generateReportV1WithData(report);

        return { signedReport, report };
    }

    /**
     * Builds and signs a default version 2 report from current generator state.
     *
     * @returns {Promise<{signedReport: string, report: ReportV2}>} Signed payload and decoded report model.
     */
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

    /**
     * Builds and signs a default version 3 report from current generator state.
     *
     * @returns {Promise<{signedReport: string, report: ReportV3}>} Signed payload and decoded report model.
     */
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

    /**
     * Builds and signs a default version 4 report from current generator state.
     *
     * @returns {Promise<{signedReport: string, report: ReportV4}>} Signed payload and decoded report model.
     */
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

    /**
     * Builds and signs a default version 5 report from current generator state.
     *
     * @returns {Promise<{signedReport: string, report: ReportV5}>} Signed payload and decoded report model.
     */
    async generateReportV5() {
        const latestBlock = await ethers.provider.getBlock("latest");
        const currentTimestamp = latestBlock.timestamp;

        const report = new ReportV5({
            feedId: this.i_reportV5MockFeedId,
            validFromTimestamp: currentTimestamp,
            observationsTimestamp: currentTimestamp,
            nativeFee: this.s_nativeFee,
            linkFee: this.s_linkFee,
            expiresAt: currentTimestamp + this.s_expiresPeriod,
            rate: this.s_price,
            timestamp: currentTimestamp,
            duration: this.s_expiresPeriod,
        });

        const signedReport = this.generateReportV5WithData(report);

        return { signedReport, report };
    }

    /**
     * Builds and signs a default version 6 report from current generator state.
     *
     * @returns {Promise<{signedReport: string, report: ReportV6}>} Signed payload and decoded report model.
     */
    async generateReportV6() {
        const latestBlock = await ethers.provider.getBlock("latest");
        const currentTimestamp = latestBlock.timestamp;

        const report = new ReportV6({
            feedId: this.i_reportV6MockFeedId,
            validFromTimestamp: currentTimestamp,
            observationsTimestamp: currentTimestamp,
            nativeFee: this.s_nativeFee,
            linkFee: this.s_linkFee,
            expiresAt: currentTimestamp + this.s_expiresPeriod,
            price: this.s_price,
            price2: this.s_price,
            price3: this.s_price,
            price4: this.s_price,
            price5: this.s_price,
        });

        const signedReport = this.generateReportV6WithData(report);

        return { signedReport, report };
    }

    /**
     * Builds and signs a default version 7 report from current generator state.
     *
     * @returns {Promise<{signedReport: string, report: ReportV7}>} Signed payload and decoded report model.
     */
    async generateReportV7() {
        const latestBlock = await ethers.provider.getBlock("latest");
        const currentTimestamp = latestBlock.timestamp;

        const report = new ReportV7({
            feedId: this.i_reportV7MockFeedId,
            validFromTimestamp: currentTimestamp,
            observationsTimestamp: currentTimestamp,
            nativeFee: this.s_nativeFee,
            linkFee: this.s_linkFee,
            expiresAt: currentTimestamp + this.s_expiresPeriod,
            exchangeRate: this.s_price,
        });

        const signedReport = this.generateReportV7WithData(report);

        return { signedReport, report };
    }

    /**
     * Builds and signs a default version 8 report from current generator state.
     *
     * @returns {Promise<{signedReport: string, report: ReportV8}>} Signed payload and decoded report model.
     */
    async generateReportV8() {
        const latestBlock = await ethers.provider.getBlock("latest");
        const currentTimestamp = latestBlock.timestamp;

        const report = new ReportV8({
            feedId: this.i_reportV8MockFeedId,
            validFromTimestamp: currentTimestamp,
            observationsTimestamp: currentTimestamp,
            nativeFee: this.s_nativeFee,
            linkFee: this.s_linkFee,
            expiresAt: currentTimestamp + this.s_expiresPeriod,
            lastUpdateTimestamp: currentTimestamp,
            midPrice: this.s_price,
            marketStatus: this.s_marketStatus,
        });

        const signedReport = this.generateReportV8WithData(report);

        return { signedReport, report };
    }

    /**
     * Builds and signs a default version 9 report from current generator state.
     *
     * @returns {Promise<{signedReport: string, report: ReportV9}>} Signed payload and decoded report model.
     */
    async generateReportV9() {
        const latestBlock = await ethers.provider.getBlock("latest");
        const currentTimestamp = latestBlock.timestamp;

        const report = new ReportV9({
            feedId: this.i_reportV9MockFeedId,
            validFromTimestamp: currentTimestamp,
            observationsTimestamp: currentTimestamp,
            nativeFee: this.s_nativeFee,
            linkFee: this.s_linkFee,
            expiresAt: currentTimestamp + this.s_expiresPeriod,
            navPerShare: this.s_price,
            navDate: currentTimestamp,
            aum: this.s_price,
            ripcord: 0,
        });

        const signedReport = this.generateReportV9WithData(report);

        return { signedReport, report };
    }

    /**
     * Builds and signs a default version 10 report from current generator state.
     *
     * @returns {Promise<{signedReport: string, report: ReportV10}>} Signed payload and decoded report model.
     */
    async generateReportV10() {
        const latestBlock = await ethers.provider.getBlock("latest");
        const currentTimestamp = latestBlock.timestamp;

        const report = new ReportV10({
            feedId: this.i_reportV10MockFeedId,
            validFromTimestamp: currentTimestamp,
            observationsTimestamp: currentTimestamp,
            nativeFee: this.s_nativeFee,
            linkFee: this.s_linkFee,
            expiresAt: currentTimestamp + this.s_expiresPeriod,
            lastUpdateTimestamp: currentTimestamp,
            price: this.s_price,
            marketStatus: this.s_marketStatus,
            currentMultiplier: 10n ** 18n,
            newMultiplier: 10n ** 18n,
            activationDateTime: currentTimestamp + this.s_expiresPeriod,
            tokenizedPrice: this.s_price,
        });

        const signedReport = this.generateReportV10WithData(report);

        return { signedReport, report };
    }

    /**
     * Builds and signs a default version 11 report from current generator state.
     *
     * @returns {Promise<{signedReport: string, report: ReportV11}>} Signed payload and decoded report model.
     */
    async generateReportV11() {
        const latestBlock = await ethers.provider.getBlock("latest");
        const currentTimestamp = latestBlock.timestamp;

        const report = new ReportV11({
            feedId: this.i_reportV11MockFeedId,
            validFromTimestamp: currentTimestamp,
            observationsTimestamp: currentTimestamp,
            nativeFee: this.s_nativeFee,
            linkFee: this.s_linkFee,
            expiresAt: currentTimestamp + this.s_expiresPeriod,
            mid: this.s_price,
            lastSeenTimestampNs: BigInt(currentTimestamp) * 10n ** 9n,
            bid: this.s_bid,
            bidVolume: 0,
            ask: this.s_ask,
            askVolume: 0,
            lastTradedPrice: this.s_price,
            marketStatus: this.s_marketStatus,
        });

        const signedReport = this.generateReportV11WithData(report);

        return { signedReport, report };
    }

    /**
     * Builds and signs a default version 12 report from current generator state.
     *
     * @returns {Promise<{signedReport: string, report: ReportV12}>} Signed payload and decoded report model.
     */
    async generateReportV12() {
        const latestBlock = await ethers.provider.getBlock("latest");
        const currentTimestamp = latestBlock.timestamp;

        const report = new ReportV12({
            feedId: this.i_reportV12MockFeedId,
            validFromTimestamp: currentTimestamp,
            observationsTimestamp: currentTimestamp,
            nativeFee: this.s_nativeFee,
            linkFee: this.s_linkFee,
            expiresAt: currentTimestamp + this.s_expiresPeriod,
            navPerShare: this.s_price,
            nextNavPerShare: this.s_price,
            navDate: currentTimestamp,
            ripcord: 0,
        });

        const signedReport = this.generateReportV12WithData(report);

        return { signedReport, report };
    }

    /**
     * Builds and signs a default version 13 report from current generator state.
     *
     * @returns {Promise<{signedReport: string, report: ReportV13}>} Signed payload and decoded report model.
     */
    async generateReportV13() {
        const latestBlock = await ethers.provider.getBlock("latest");
        const currentTimestamp = latestBlock.timestamp;

        const report = new ReportV13({
            feedId: this.i_reportV13MockFeedId,
            validFromTimestamp: currentTimestamp,
            observationsTimestamp: currentTimestamp,
            nativeFee: this.s_nativeFee,
            linkFee: this.s_linkFee,
            expiresAt: currentTimestamp + this.s_expiresPeriod,
            bestAsk: this.s_ask,
            bestBid: this.s_bid,
            askVolume: 0,
            bidVolume: 0,
            lastTradedPrice: this.s_price,
        });

        const signedReport = this.generateReportV13WithData(report);

        return { signedReport, report };
    }

    /**
     * Updates benchmark price and derives bid/ask around it using +/-0.1%.
     *
     * @param {bigint|number} price New benchmark price.
     * @returns {void}
     */
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

    /**
     * Updates benchmark price and explicit bid/ask values.
     *
     * @param {bigint|number} price Benchmark price.
     * @param {bigint|number} bid Bid value; must be lower than price.
     * @param {bigint|number} ask Ask value; must be higher than price.
     * @returns {void}
     */
    updatePriceBidAndAsk(price, bid, ask) {
        // bid < price < ask
        if (bid >= price) throw new Error("Bid must be less than price");
        if (ask <= price) throw new Error("Ask must be greater than price");

        this.s_price = price;
        this.s_bid = bid;
        this.s_ask = ask;
    }

    /**
     * @param {number} period Report expiry period in seconds.
     * @returns {void}
     */
    updateExpiresPeriod(period) {
        this.s_expiresPeriod = period;
    }

    /**
     * @param {number} status Market status code.
     * @returns {void}
     */
    updateMarketStatus(status) {
        this.s_marketStatus = status;
    }

    /**
     * @param {bigint|number} nativeFee Verification fee in native token units.
     * @param {bigint|number} linkFee Verification fee in LINK units.
     * @returns {void}
     */
    updateFees(nativeFee, linkFee) {
        this.s_nativeFee = nativeFee;
        this.s_linkFee = linkFee;
    }

    /**
     * Returns the mock DON signer address derived from the fixed DON digest.
     *
     * @returns {string} EVM address.
     */
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
    ReportV1,
    ReportV2,
    ReportV3,
    ReportV4,
    ReportV5,
    ReportV6,
    ReportV7,
    ReportV8,
    ReportV9,
    ReportV10,
    ReportV11,
    ReportV12,
    ReportV13,
    MockReportGenerator
}