/**
 * Mock report payload model for Data Streams report version 1.
 */
class ReportV1 {
    /**
     * @param {object} params Report fields.
     * @param {string} params.feedId Stream identifier as bytes32 hex string.
     * @param {number} params.observationsTimestamp Observation timestamp in seconds.
     * @param {bigint|number} params.benchmarkPrice DON consensus median benchmark price.
     * @param {bigint|number} params.bid Bid-side price estimate.
     * @param {bigint|number} params.ask Ask-side price estimate.
     * @param {bigint|number} params.currentBlockNum Current block number used by the report.
     * @param {string} params.currentBlockHash Current block hash as bytes32 hex string.
     * @param {bigint|number} params.validFromBlockNum Earliest block number from which the report is valid.
     * @param {bigint|number} params.currentBlockTimestamp Current block timestamp in seconds.
     */
    constructor({
        feedId,
        observationsTimestamp,
        benchmarkPrice,
        bid,
        ask,
        currentBlockNum,
        currentBlockHash,
        validFromBlockNum,
        currentBlockTimestamp,
    }) {
        this.feedId = feedId; // (bytes32) The stream ID the report has data for
        this.observationsTimestamp = observationsTimestamp; // (uint32) Observation timestamp in seconds
        this.benchmarkPrice = benchmarkPrice; // (int192) DON consensus median benchmark price
        this.bid = bid; // (int192) Bid-side price estimate
        this.ask = ask; // (int192) Ask-side price estimate
        this.currentBlockNum = currentBlockNum; // (uint64) Current block number used by the report
        this.currentBlockHash = currentBlockHash; // (bytes32) Current block hash used by the report
        this.validFromBlockNum = validFromBlockNum; // (uint64) Earliest block number from which the report is valid
        this.currentBlockTimestamp = currentBlockTimestamp; // (uint64) Current block timestamp in seconds
    }
}

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

/**
 * Mock report payload model for Data Streams report version 5.
 */
class ReportV5 {
    /**
     * @param {object} params Report fields.
     * @param {string} params.feedId Stream identifier as bytes32 hex string.
     * @param {number} params.validFromTimestamp Earliest timestamp where the report is valid.
     * @param {number} params.observationsTimestamp Latest timestamp covered by observations.
     * @param {bigint|number} params.nativeFee Verification fee in native token units.
     * @param {bigint|number} params.linkFee Verification fee in LINK units.
     * @param {number} params.expiresAt Expiration timestamp for on-chain verification.
     * @param {bigint|number} params.rate Reported rate value.
     * @param {number} params.timestamp Rate timestamp in seconds.
     * @param {number} params.duration Duration window in seconds.
     */
    constructor({
        feedId,
        validFromTimestamp,
        observationsTimestamp,
        nativeFee,
        linkFee,
        expiresAt,
        rate,
        timestamp,
        duration,
    }) {
        this.feedId = feedId; // (bytes32) The stream ID the report has data for
        this.validFromTimestamp = validFromTimestamp; // (uint32) Earliest timestamp for which the report is applicable
        this.observationsTimestamp = observationsTimestamp; // (uint32) Latest timestamp for which the report is applicable
        this.nativeFee = nativeFee; // (uint192) Base cost to validate a transaction using the report, denominated in the chain's native token (e.g., WETH/ETH)
        this.linkFee = linkFee; // (uint192) Base cost to validate a transaction using the report, denominated in LINK
        this.expiresAt = expiresAt; // (uint32) Latest timestamp where the report can be verified on-chain
        this.rate = rate; // (int192) Reported rate value
        this.timestamp = timestamp; // (uint32) Rate timestamp in seconds
        this.duration = duration; // (uint32) Duration window in seconds
    }
}

/**
 * Mock report payload model for Data Streams report version 6.
 */
class ReportV6 {
    /**
     * @param {object} params Report fields.
     * @param {string} params.feedId Stream identifier as bytes32 hex string.
     * @param {number} params.validFromTimestamp Earliest timestamp where the report is valid.
     * @param {number} params.observationsTimestamp Latest timestamp covered by observations.
     * @param {bigint|number} params.nativeFee Verification fee in native token units.
     * @param {bigint|number} params.linkFee Verification fee in LINK units.
     * @param {number} params.expiresAt Expiration timestamp for on-chain verification.
     * @param {bigint|number} params.price Primary price value.
     * @param {bigint|number} params.price2 Secondary price value.
     * @param {bigint|number} params.price3 Third price value.
     * @param {bigint|number} params.price4 Fourth price value.
     * @param {bigint|number} params.price5 Fifth price value.
     */
    constructor({
        feedId,
        validFromTimestamp,
        observationsTimestamp,
        nativeFee,
        linkFee,
        expiresAt,
        price,
        price2,
        price3,
        price4,
        price5,
    }) {
        this.feedId = feedId; // (bytes32) The stream ID the report has data for
        this.validFromTimestamp = validFromTimestamp; // (uint32) Earliest timestamp for which the report is applicable
        this.observationsTimestamp = observationsTimestamp; // (uint32) Latest timestamp for which the report is applicable
        this.nativeFee = nativeFee; // (uint192) Base cost to validate a transaction using the report, denominated in the chain's native token (e.g., WETH/ETH)
        this.linkFee = linkFee; // (uint192) Base cost to validate a transaction using the report, denominated in LINK
        this.expiresAt = expiresAt; // (uint32) Latest timestamp where the report can be verified on-chain
        this.price = price; // (int192) Primary price value
        this.price2 = price2; // (int192) Secondary price value
        this.price3 = price3; // (int192) Third price value
        this.price4 = price4; // (int192) Fourth price value
        this.price5 = price5; // (int192) Fifth price value
    }
}

/**
 * Mock report payload model for Data Streams report version 7.
 */
class ReportV7 {
    /**
     * @param {object} params Report fields.
     * @param {string} params.feedId Stream identifier as bytes32 hex string.
     * @param {number} params.validFromTimestamp Earliest timestamp where the report is valid.
     * @param {number} params.observationsTimestamp Latest timestamp covered by observations.
     * @param {bigint|number} params.nativeFee Verification fee in native token units.
     * @param {bigint|number} params.linkFee Verification fee in LINK units.
     * @param {number} params.expiresAt Expiration timestamp for on-chain verification.
     * @param {bigint|number} params.exchangeRate Redemption / exchange-rate value.
     */
    constructor({
        feedId,
        validFromTimestamp,
        observationsTimestamp,
        nativeFee,
        linkFee,
        expiresAt,
        exchangeRate,
    }) {
        this.feedId = feedId; // (bytes32) The stream ID the report has data for
        this.validFromTimestamp = validFromTimestamp; // (uint32) Earliest timestamp for which the report is applicable
        this.observationsTimestamp = observationsTimestamp; // (uint32) Latest timestamp for which the report is applicable
        this.nativeFee = nativeFee; // (uint192) Base cost to validate a transaction using the report, denominated in the chain's native token (e.g., WETH/ETH)
        this.linkFee = linkFee; // (uint192) Base cost to validate a transaction using the report, denominated in LINK
        this.expiresAt = expiresAt; // (uint32) Latest timestamp where the report can be verified on-chain
        this.exchangeRate = exchangeRate; // (int192) Redemption / exchange-rate value (8 or 18 decimals)
    }
}

/**
 * Mock report payload model for Data Streams report version 8.
 */
class ReportV8 {
    /**
     * @param {object} params Report fields.
     * @param {string} params.feedId Stream identifier as bytes32 hex string.
     * @param {number} params.validFromTimestamp Earliest timestamp where the report is valid.
     * @param {number} params.observationsTimestamp Latest timestamp covered by observations.
     * @param {bigint|number} params.nativeFee Verification fee in native token units.
     * @param {bigint|number} params.linkFee Verification fee in LINK units.
     * @param {number} params.expiresAt Expiration timestamp for on-chain verification.
     * @param {bigint|number} params.lastUpdateTimestamp Timestamp of the last source-side update.
     * @param {bigint|number} params.midPrice DON consensus mid price.
     * @param {number} params.marketStatus Market status code reported by DON.
     */
    constructor({
        feedId,
        validFromTimestamp,
        observationsTimestamp,
        nativeFee,
        linkFee,
        expiresAt,
        lastUpdateTimestamp,
        midPrice,
        marketStatus,
    }) {
        this.feedId = feedId; // (bytes32) The stream ID the report has data for
        this.validFromTimestamp = validFromTimestamp; // (uint32) Earliest timestamp for which the report is applicable
        this.observationsTimestamp = observationsTimestamp; // (uint32) Latest timestamp for which the report is applicable
        this.nativeFee = nativeFee; // (uint192) Base cost to validate a transaction using the report, denominated in the chain's native token (e.g., WETH/ETH)
        this.linkFee = linkFee; // (uint192) Base cost to validate a transaction using the report, denominated in LINK
        this.expiresAt = expiresAt; // (uint32) Latest timestamp where the report can be verified on-chain
        this.lastUpdateTimestamp = lastUpdateTimestamp; // (uint64) Timestamp of the last source-side update
        this.midPrice = midPrice; // (int192) DON consensus mid price (8 or 18 decimals)
        this.marketStatus = marketStatus; // (uint32) The DON's consensus on whether the market is currently open
    }
}

/**
 * Mock report payload model for Data Streams report version 9.
 */
class ReportV9 {
    /**
     * @param {object} params Report fields.
     * @param {string} params.feedId Stream identifier as bytes32 hex string.
     * @param {number} params.validFromTimestamp Earliest timestamp where the report is valid.
     * @param {number} params.observationsTimestamp Latest timestamp covered by observations.
     * @param {bigint|number} params.nativeFee Verification fee in native token units.
     * @param {bigint|number} params.linkFee Verification fee in LINK units.
     * @param {number} params.expiresAt Expiration timestamp for on-chain verification.
     * @param {bigint|number} params.navPerShare Net asset value per share.
     * @param {bigint|number} params.navDate NAV date / timestamp.
     * @param {bigint|number} params.aum Assets under management value.
     * @param {number} params.ripcord Issuer / source risk flag.
     */
    constructor({
        feedId,
        validFromTimestamp,
        observationsTimestamp,
        nativeFee,
        linkFee,
        expiresAt,
        navPerShare,
        navDate,
        aum,
        ripcord,
    }) {
        this.feedId = feedId; // (bytes32) The stream ID the report has data for
        this.validFromTimestamp = validFromTimestamp; // (uint32) Earliest timestamp for which the report is applicable
        this.observationsTimestamp = observationsTimestamp; // (uint32) Latest timestamp for which the report is applicable
        this.nativeFee = nativeFee; // (uint192) Base cost to validate a transaction using the report, denominated in the chain's native token (e.g., WETH/ETH)
        this.linkFee = linkFee; // (uint192) Base cost to validate a transaction using the report, denominated in LINK
        this.expiresAt = expiresAt; // (uint32) Latest timestamp where the report can be verified on-chain
        this.navPerShare = navPerShare; // (int192) Net asset value per share
        this.navDate = navDate; // (uint64) NAV date / timestamp
        this.aum = aum; // (int192) Assets under management value
        this.ripcord = ripcord; // (uint32) Issuer / source risk flag
    }
}

/**
 * Mock report payload model for Data Streams report version 10.
 */
class ReportV10 {
    /**
     * @param {object} params Report fields.
     * @param {string} params.feedId Stream identifier as bytes32 hex string.
     * @param {number} params.validFromTimestamp Earliest timestamp where the report is valid.
     * @param {number} params.observationsTimestamp Latest timestamp covered by observations.
     * @param {bigint|number} params.nativeFee Verification fee in native token units.
     * @param {bigint|number} params.linkFee Verification fee in LINK units.
     * @param {number} params.expiresAt Expiration timestamp for on-chain verification.
     * @param {bigint|number} params.lastUpdateTimestamp Timestamp of the last source-side update.
     * @param {bigint|number} params.price Underlying asset price.
     * @param {number} params.marketStatus Market status code reported by DON.
     * @param {bigint|number} params.currentMultiplier Current underlying-share multiplier.
     * @param {bigint|number} params.newMultiplier Future multiplier applied after a corporate action.
     * @param {number} params.activationDateTime Corporate-action activation timestamp.
     * @param {bigint|number} params.tokenizedPrice Tokenized-asset price when available.
     */
    constructor({
        feedId,
        validFromTimestamp,
        observationsTimestamp,
        nativeFee,
        linkFee,
        expiresAt,
        lastUpdateTimestamp,
        price,
        marketStatus,
        currentMultiplier,
        newMultiplier,
        activationDateTime,
        tokenizedPrice,
    }) {
        this.feedId = feedId; // (bytes32) The stream ID the report has data for
        this.validFromTimestamp = validFromTimestamp; // (uint32) Earliest timestamp for which the report is applicable
        this.observationsTimestamp = observationsTimestamp; // (uint32) Latest timestamp for which the report is applicable
        this.nativeFee = nativeFee; // (uint192) Base cost to validate a transaction using the report, denominated in the chain's native token (e.g., WETH/ETH)
        this.linkFee = linkFee; // (uint192) Base cost to validate a transaction using the report, denominated in LINK
        this.expiresAt = expiresAt; // (uint32) Latest timestamp where the report can be verified on-chain
        this.lastUpdateTimestamp = lastUpdateTimestamp; // (uint64) Timestamp of the last source-side update
        this.price = price; // (int192) Underlying asset price (8 or 18 decimals)
        this.marketStatus = marketStatus; // (uint32) The DON's consensus on whether the market is currently open
        this.currentMultiplier = currentMultiplier; // (int192) Current underlying-share multiplier
        this.newMultiplier = newMultiplier; // (int192) Future multiplier applied after a corporate action
        this.activationDateTime = activationDateTime; // (uint32) Corporate-action activation timestamp
        this.tokenizedPrice = tokenizedPrice; // (int192) Tokenized-asset price when available
    }
}

/**
 * Mock report payload model for Data Streams report version 11.
 */
class ReportV11 {
    /**
     * @param {object} params Report fields.
     * @param {string} params.feedId Stream identifier as bytes32 hex string.
     * @param {number} params.validFromTimestamp Earliest timestamp where the report is valid.
     * @param {number} params.observationsTimestamp Latest timestamp covered by observations.
     * @param {bigint|number} params.nativeFee Verification fee in native token units.
     * @param {bigint|number} params.linkFee Verification fee in LINK units.
     * @param {number} params.expiresAt Expiration timestamp for on-chain verification.
     * @param {bigint|number} params.mid Liquidity-weighted mid price.
     * @param {bigint|number} params.lastSeenTimestampNs Last-seen source timestamp in nanoseconds.
     * @param {bigint|number} params.bid Consensus bid price.
     * @param {bigint|number} params.bidVolume Resting bid-side volume / depth.
     * @param {bigint|number} params.ask Consensus ask price.
     * @param {bigint|number} params.askVolume Resting ask-side volume / depth.
     * @param {bigint|number} params.lastTradedPrice Most recent traded price.
     * @param {number} params.marketStatus Market status code reported by DON.
     */
    constructor({
        feedId,
        validFromTimestamp,
        observationsTimestamp,
        nativeFee,
        linkFee,
        expiresAt,
        mid,
        lastSeenTimestampNs,
        bid,
        bidVolume,
        ask,
        askVolume,
        lastTradedPrice,
        marketStatus,
    }) {
        this.feedId = feedId; // (bytes32) The stream ID the report has data for
        this.validFromTimestamp = validFromTimestamp; // (uint32) Earliest timestamp for which the report is applicable
        this.observationsTimestamp = observationsTimestamp; // (uint32) Latest timestamp for which the report is applicable
        this.nativeFee = nativeFee; // (uint192) Base cost to validate a transaction using the report, denominated in the chain's native token (e.g., WETH/ETH)
        this.linkFee = linkFee; // (uint192) Base cost to validate a transaction using the report, denominated in LINK
        this.expiresAt = expiresAt; // (uint32) Latest timestamp where the report can be verified on-chain
        this.mid = mid; // (int192) Liquidity-weighted mid price (8 or 18 decimals)
        this.lastSeenTimestampNs = lastSeenTimestampNs; // (uint64) Last-seen timestamp from the source, in nanoseconds
        this.bid = bid; // (int192) Consensus bid price (8 or 18 decimals)
        this.bidVolume = bidVolume; // (int192) Resting bid-side volume / depth
        this.ask = ask; // (int192) Consensus ask price (8 or 18 decimals)
        this.askVolume = askVolume; // (int192) Resting ask-side volume / depth
        this.lastTradedPrice = lastTradedPrice; // (int192) Most recent traded price (8 or 18 decimals)
        this.marketStatus = marketStatus; // (uint32) The DON's consensus on whether the market is currently open
    }
}

/**
 * Mock report payload model for Data Streams report version 12.
 */
class ReportV12 {
    /**
     * @param {object} params Report fields.
     * @param {string} params.feedId Stream identifier as bytes32 hex string.
     * @param {number} params.validFromTimestamp Earliest timestamp where the report is valid.
     * @param {number} params.observationsTimestamp Latest timestamp covered by observations.
     * @param {bigint|number} params.nativeFee Verification fee in native token units.
     * @param {bigint|number} params.linkFee Verification fee in LINK units.
     * @param {number} params.expiresAt Expiration timestamp for on-chain verification.
     * @param {bigint|number} params.navPerShare Current NAV per share.
     * @param {bigint|number} params.nextNavPerShare Next NAV per share.
     * @param {bigint|number} params.navDate NAV date / timestamp.
     * @param {number} params.ripcord Issuer / source risk flag.
     */
    constructor({
        feedId,
        validFromTimestamp,
        observationsTimestamp,
        nativeFee,
        linkFee,
        expiresAt,
        navPerShare,
        nextNavPerShare,
        navDate,
        ripcord,
    }) {
        this.feedId = feedId; // (bytes32) The stream ID the report has data for
        this.validFromTimestamp = validFromTimestamp; // (uint32) Earliest timestamp for which the report is applicable
        this.observationsTimestamp = observationsTimestamp; // (uint32) Latest timestamp for which the report is applicable
        this.nativeFee = nativeFee; // (uint192) Base cost to validate a transaction using the report, denominated in the chain's native token (e.g., WETH/ETH)
        this.linkFee = linkFee; // (uint192) Base cost to validate a transaction using the report, denominated in LINK
        this.expiresAt = expiresAt; // (uint32) Latest timestamp where the report can be verified on-chain
        this.navPerShare = navPerShare; // (int192) Current NAV per share
        this.nextNavPerShare = nextNavPerShare; // (int192) Next NAV per share
        this.navDate = navDate; // (uint64) NAV date / timestamp
        this.ripcord = ripcord; // (uint32) Issuer / source risk flag
    }
}

/**
 * Mock report payload model for Data Streams report version 13.
 */
class ReportV13 {
    /**
     * @param {object} params Report fields.
     * @param {string} params.feedId Stream identifier as bytes32 hex string.
     * @param {number} params.validFromTimestamp Earliest timestamp where the report is valid.
     * @param {number} params.observationsTimestamp Latest timestamp covered by observations.
     * @param {bigint|number} params.nativeFee Verification fee in native token units.
     * @param {bigint|number} params.linkFee Verification fee in LINK units.
     * @param {number} params.expiresAt Expiration timestamp for on-chain verification.
     * @param {bigint|number} params.bestAsk Best ask price.
     * @param {bigint|number} params.bestBid Best bid price.
     * @param {bigint|number} params.askVolume Best ask volume.
     * @param {bigint|number} params.bidVolume Best bid volume.
     * @param {bigint|number} params.lastTradedPrice Most recent traded price.
     */
    constructor({
        feedId,
        validFromTimestamp,
        observationsTimestamp,
        nativeFee,
        linkFee,
        expiresAt,
        bestAsk,
        bestBid,
        askVolume,
        bidVolume,
        lastTradedPrice,
    }) {
        this.feedId = feedId; // (bytes32) The stream ID the report has data for
        this.validFromTimestamp = validFromTimestamp; // (uint32) Earliest timestamp for which the report is applicable
        this.observationsTimestamp = observationsTimestamp; // (uint32) Latest timestamp for which the report is applicable
        this.nativeFee = nativeFee; // (uint192) Base cost to validate a transaction using the report, denominated in the chain's native token (e.g., WETH/ETH)
        this.linkFee = linkFee; // (uint192) Base cost to validate a transaction using the report, denominated in LINK
        this.expiresAt = expiresAt; // (uint32) Latest timestamp where the report can be verified on-chain
        this.bestAsk = bestAsk; // (int192) Best ask price
        this.bestBid = bestBid; // (int192) Best bid price
        this.askVolume = askVolume; // (uint64) Best ask volume
        this.bidVolume = bidVolume; // (uint64) Best bid volume
        this.lastTradedPrice = lastTradedPrice; // (int192) Most recent traded price
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
}