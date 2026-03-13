/**
 * Mock report payload model for Data Streams report version 2.
 */
class ReportV2 {
    /**
     * @param {object} params Report fields.
     * @param {string} params.feedId Feed identifier as bytes32 hex string.
     * @param {number} params.validFromTimestamp Earliest timestamp where the report is valid.
     * @param {number} params.observationsTimestamp Latest timestamp covered by observations.
     * @param {bigint|number} params.nativeFee Verification fee in native token units.
     * @param {bigint|number} params.linkFee Verification fee in LINK units.
     * @param {number} params.expiresAt Expiration timestamp for on-chain verification.
     * @param {bigint|number} params.benchmarkPrice Median benchmark price.
     */
    constructor({
        feedId,
        validFromTimestamp,
        observationsTimestamp,
        nativeFee,
        linkFee,
        expiresAt,
        benchmarkPrice,
    }) {
        this.feedId = feedId; // (bytes32) The feed ID the report has data for
        this.validFromTimestamp = validFromTimestamp; // (uint32) Earliest timestamp for which price is applicable
        this.observationsTimestamp = observationsTimestamp; // (uint32) Latest timestamp for which price is applicable
        this.nativeFee = nativeFee; // (uint192) Base cost to validate a transaction using the report, denominated in the chain’s native token (WETH/ETH)
        this.linkFee = linkFee; // (uint192) Base cost to validate a transaction using the report, denominated in LINK
        this.expiresAt = expiresAt; // (uint32) Latest timestamp where the report can be verified on-chain
        this.benchmarkPrice = benchmarkPrice; // (int192) DON consensus median price, carried to 8 decimal places
    }
}

/**
 * Mock report payload model for Data Streams report version 3.
 */
class ReportV3 {
    /**
     * @param {object} params Report fields.
     * @param {string} params.feedId Stream identifier as bytes32 hex string.
     * @param {number} params.validFromTimestamp Earliest timestamp where the report is valid.
     * @param {number} params.observationsTimestamp Latest timestamp covered by observations.
     * @param {bigint|number} params.nativeFee Verification fee in native token units.
     * @param {bigint|number} params.linkFee Verification fee in LINK units.
     * @param {number} params.expiresAt Expiration timestamp for on-chain verification.
     * @param {bigint|number} params.price Median price.
     * @param {bigint|number} params.bid Simulated buy-side price impact value.
     * @param {bigint|number} params.ask Simulated sell-side price impact value.
     */
    constructor({
        feedId,
        validFromTimestamp,
        observationsTimestamp,
        nativeFee,
        linkFee,
        expiresAt,
        price,
        bid,
        ask,
    }) {
        this.feedId = feedId; // (bytes32) The stream ID the report has data for
        this.validFromTimestamp = validFromTimestamp; // (uint32) Earliest timestamp for which price is applicable
        this.observationsTimestamp = observationsTimestamp; // (uint32) Latest timestamp for which price is applicable
        this.nativeFee = nativeFee; // (uint192) Base cost to validate a transaction using the report, denominated in the chain’s native token (e.g., WETH/ETH)
        this.linkFee = linkFee; // (uint192) Base cost to validate a transaction using the report, denominated in LINK
        this.expiresAt = expiresAt; // (uint32) Latest timestamp where the report can be verified on-chain
        this.price = price; // (int192) DON consensus median price (8 or 18 decimals)
        this.bid = bid; // (int192) Simulated price impact of a buy order up to the X% depth of liquidity utilisation (8 or 18 decimals)
        this.ask = ask; // (int192) Simulated price impact of a sell order up to the X% depth of liquidity utilisation (8 or 18 decimals)
    }
}

/**
 * Mock report payload model for Data Streams report version 4.
 */
class ReportV4 {
    /**
     * @param {object} params Report fields.
     * @param {string} params.feedId Stream identifier as bytes32 hex string.
     * @param {number} params.validFromTimestamp Earliest timestamp where the report is valid.
     * @param {number} params.observationsTimestamp Latest timestamp covered by observations.
     * @param {bigint|number} params.nativeFee Verification fee in native token units.
     * @param {bigint|number} params.linkFee Verification fee in LINK units.
     * @param {number} params.expiresAt Expiration timestamp for on-chain verification.
     * @param {bigint|number} params.price Median benchmark price.
     * @param {number} params.marketStatus Market status code reported by DON.
     */
    constructor({
        feedId,
        validFromTimestamp,
        observationsTimestamp,
        nativeFee,
        linkFee,
        expiresAt,
        price,
        marketStatus,
    }) {
        this.feedId = feedId; // (bytes32) The stream ID the report has data for
        this.validFromTimestamp = validFromTimestamp; // (uint32) Earliest timestamp for which price is applicable
        this.observationsTimestamp = observationsTimestamp; // (uint32) Latest timestamp for which price is applicable
        this.nativeFee = nativeFee; // (uint192) Base cost to validate a transaction using the report, denominated in the chain’s native token (e.g., WETH/ETH)
        this.linkFee = linkFee; // (uint192) Base cost to validate a transaction using the report, denominated in LINK
        this.expiresAt = expiresAt; // (uint32) Latest timestamp where the report can be verified on-chain
        this.price = price; // (int192) DON consensus median benchmark price (8 or 18 decimals)
        this.marketStatus = marketStatus; // (uint32) The DON's consensus on whether the market is currently open
    }
}

module.exports = {
    ReportV2,
    ReportV3,
    ReportV4
}
