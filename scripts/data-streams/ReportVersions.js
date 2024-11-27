class ReportV2 {
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

class ReportV3 {
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

class ReportV4 {
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