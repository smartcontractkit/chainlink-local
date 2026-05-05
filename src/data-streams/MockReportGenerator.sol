// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ReportVersions} from "./ReportVersions.sol";

contract MockReportGenerator is Test, ReportVersions {
    address internal immutable i_donAddress;
    uint256 internal immutable i_donDigest;

    bytes32 internal immutable i_reportV1MockFeedId =
        hex"0001777777777777777777777777777777777777777777777777777777777777";
    bytes32 internal immutable i_reportV2MockFeedId =
        hex"0002777777777777777777777777777777777777777777777777777777777777";
    bytes32 internal immutable i_reportV3MockFeedId =
        hex"0003777777777777777777777777777777777777777777777777777777777777";
    bytes32 internal immutable i_reportV4MockFeedId =
        hex"0004777777777777777777777777777777777777777777777777777777777777";
    bytes32 internal immutable i_reportV5MockFeedId =
        hex"0005777777777777777777777777777777777777777777777777777777777777";
    bytes32 internal immutable i_reportV6MockFeedId =
        hex"0006777777777777777777777777777777777777777777777777777777777777";
    bytes32 internal immutable i_reportV7MockFeedId =
        hex"0007777777777777777777777777777777777777777777777777777777777777";
    bytes32 internal immutable i_reportV8MockFeedId =
        hex"0008777777777777777777777777777777777777777777777777777777777777";
    bytes32 internal immutable i_reportV9MockFeedId =
        hex"0009777777777777777777777777777777777777777777777777777777777777";
    bytes32 internal immutable i_reportV10MockFeedId =
        hex"000a777777777777777777777777777777777777777777777777777777777777";
    bytes32 internal immutable i_reportV11MockFeedId =
        hex"000b777777777777777777777777777777777777777777777777777777777777";
    bytes32 internal immutable i_reportV12MockFeedId =
        hex"000c777777777777777777777777777777777777777777777777777777777777";
    bytes32 internal immutable i_reportV13MockFeedId =
        hex"000d777777777777777777777777777777777777777777777777777777777777";

    int192 internal s_price;
    int192 internal s_bid;
    int192 internal s_ask;
    uint32 internal s_expiresPeriod;
    uint32 internal s_marketStatus;
    uint192 internal s_nativeFee; // 0 by default
    uint192 internal s_linkFee; // 0 by default

    error MockReportGenerator__InvalidBid();
    error MockReportGenerator__InvalidAsk();
    error MockReportGenerator__CastOverflow();

    constructor(int192 initialPrice) {
        updatePrice(initialPrice);
        s_expiresPeriod = 1 days;
        s_marketStatus = 2; // 0 (Unknown), 1 (Closed), 2 (Open)
        (i_donAddress, i_donDigest) = makeAddrAndKey("Mock Data Streams DON");
    }

    function generateReport(ReportV1 calldata report) external returns (bytes memory signedReport) {
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReportV2(ReportV2 calldata report) external returns (bytes memory signedReport) {
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReport(ReportV3 calldata report) external returns (bytes memory signedReport) {
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReport(ReportV4 calldata report) external returns (bytes memory signedReport) {
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReport(ReportV5 calldata report) external returns (bytes memory signedReport) {
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReport(ReportV6 calldata report) external returns (bytes memory signedReport) {
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReport(ReportV7 calldata report) external returns (bytes memory signedReport) {
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReport(ReportV8 calldata report) external returns (bytes memory signedReport) {
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReport(ReportV9 calldata report) external returns (bytes memory signedReport) {
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReport(ReportV10 calldata report) external returns (bytes memory signedReport) {
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReport(ReportV11 calldata report) external returns (bytes memory signedReport) {
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReport(ReportV12 calldata report) external returns (bytes memory signedReport) {
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReport(ReportV13 calldata report) external returns (bytes memory signedReport) {
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReportV1() external returns (bytes memory signedReport, ReportV1 memory report) {
        report = ReportV1({
            feedId: i_reportV1MockFeedId,
            observationsTimestamp: toUint32(block.timestamp),
            benchmarkPrice: s_price,
            bid: s_bid,
            ask: s_ask,
            currentBlockNum: toUint64(block.number),
            currentBlockHash: blockhash(block.number == 0 ? 0 : block.number - 1),
            validFromBlockNum: toUint64(block.number),
            currentBlockTimestamp: toUint64(block.timestamp)
        });
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReportV2() external returns (bytes memory signedReport, ReportV2 memory report) {
        report = ReportV2({
            feedId: i_reportV2MockFeedId,
            validFromTimestamp: toUint32(block.timestamp),
            observationsTimestamp: toUint32(block.timestamp),
            nativeFee: s_nativeFee,
            linkFee: s_linkFee,
            expiresAt: toUint32(block.timestamp + s_expiresPeriod),
            benchmarkPrice: s_price
        });
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReportV3() external returns (bytes memory signedReport, ReportV3 memory report) {
        report = ReportV3({
            feedId: i_reportV3MockFeedId,
            validFromTimestamp: toUint32(block.timestamp),
            observationsTimestamp: toUint32(block.timestamp),
            nativeFee: s_nativeFee,
            linkFee: s_linkFee,
            expiresAt: toUint32(block.timestamp + s_expiresPeriod),
            price: s_price,
            bid: s_bid,
            ask: s_ask
        });
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReportV4() external returns (bytes memory signedReport, ReportV4 memory report) {
        report = ReportV4({
            feedId: i_reportV4MockFeedId,
            validFromTimestamp: toUint32(block.timestamp),
            observationsTimestamp: toUint32(block.timestamp),
            nativeFee: s_nativeFee,
            linkFee: s_linkFee,
            expiresAt: toUint32(block.timestamp + s_expiresPeriod),
            price: s_price,
            marketStatus: s_marketStatus
        });
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReportV5() external returns (bytes memory signedReport, ReportV5 memory report) {
        report = ReportV5({
            feedId: i_reportV5MockFeedId,
            validFromTimestamp: toUint32(block.timestamp),
            observationsTimestamp: toUint32(block.timestamp),
            nativeFee: s_nativeFee,
            linkFee: s_linkFee,
            expiresAt: toUint32(block.timestamp + s_expiresPeriod),
            rate: s_price,
            timestamp: toUint32(block.timestamp),
            duration: s_expiresPeriod
        });
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReportV6() external returns (bytes memory signedReport, ReportV6 memory report) {
        report = ReportV6({
            feedId: i_reportV6MockFeedId,
            validFromTimestamp: toUint32(block.timestamp),
            observationsTimestamp: toUint32(block.timestamp),
            nativeFee: s_nativeFee,
            linkFee: s_linkFee,
            expiresAt: toUint32(block.timestamp + s_expiresPeriod),
            price: s_price,
            price2: s_price,
            price3: s_price,
            price4: s_price,
            price5: s_price
        });
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReportV7() external returns (bytes memory signedReport, ReportV7 memory report) {
        report = ReportV7({
            feedId: i_reportV7MockFeedId,
            validFromTimestamp: toUint32(block.timestamp),
            observationsTimestamp: toUint32(block.timestamp),
            nativeFee: s_nativeFee,
            linkFee: s_linkFee,
            expiresAt: toUint32(block.timestamp + s_expiresPeriod),
            exchangeRate: s_price
        });
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReportV8() external returns (bytes memory signedReport, ReportV8 memory report) {
        report = ReportV8({
            feedId: i_reportV8MockFeedId,
            validFromTimestamp: toUint32(block.timestamp),
            observationsTimestamp: toUint32(block.timestamp),
            nativeFee: s_nativeFee,
            linkFee: s_linkFee,
            expiresAt: toUint32(block.timestamp + s_expiresPeriod),
            lastUpdateTimestamp: toUint64(block.timestamp),
            midPrice: s_price,
            marketStatus: s_marketStatus
        });
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReportV9() external returns (bytes memory signedReport, ReportV9 memory report) {
        report = ReportV9({
            feedId: i_reportV9MockFeedId,
            validFromTimestamp: toUint32(block.timestamp),
            observationsTimestamp: toUint32(block.timestamp),
            nativeFee: s_nativeFee,
            linkFee: s_linkFee,
            expiresAt: toUint32(block.timestamp + s_expiresPeriod),
            navPerShare: s_price,
            navDate: toUint64(block.timestamp),
            aum: s_price,
            ripcord: 0
        });
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReportV10() external returns (bytes memory signedReport, ReportV10 memory report) {
        report = ReportV10({
            feedId: i_reportV10MockFeedId,
            validFromTimestamp: toUint32(block.timestamp),
            observationsTimestamp: toUint32(block.timestamp),
            nativeFee: s_nativeFee,
            linkFee: s_linkFee,
            expiresAt: toUint32(block.timestamp + s_expiresPeriod),
            lastUpdateTimestamp: toUint64(block.timestamp),
            price: s_price,
            marketStatus: s_marketStatus,
            currentMultiplier: int192(1e18),
            newMultiplier: int192(1e18),
            activationDateTime: toUint32(block.timestamp + s_expiresPeriod),
            tokenizedPrice: s_price
        });
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReportV11() external returns (bytes memory signedReport, ReportV11 memory report) {
        report = ReportV11({
            feedId: i_reportV11MockFeedId,
            validFromTimestamp: toUint32(block.timestamp),
            observationsTimestamp: toUint32(block.timestamp),
            nativeFee: s_nativeFee,
            linkFee: s_linkFee,
            expiresAt: toUint32(block.timestamp + s_expiresPeriod),
            mid: s_price,
            lastSeenTimestampNs: toUint64(block.timestamp) * 1e9,
            bid: s_bid,
            bidVolume: 0,
            ask: s_ask,
            askVolume: 0,
            lastTradedPrice: s_price,
            marketStatus: s_marketStatus
        });
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReportV12() external returns (bytes memory signedReport, ReportV12 memory report) {
        report = ReportV12({
            feedId: i_reportV12MockFeedId,
            validFromTimestamp: toUint32(block.timestamp),
            observationsTimestamp: toUint32(block.timestamp),
            nativeFee: s_nativeFee,
            linkFee: s_linkFee,
            expiresAt: toUint32(block.timestamp + s_expiresPeriod),
            navPerShare: s_price,
            nextNavPerShare: s_price,
            navDate: toUint64(block.timestamp),
            ripcord: 0
        });
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function generateReportV13() external returns (bytes memory signedReport, ReportV13 memory report) {
        report = ReportV13({
            feedId: i_reportV13MockFeedId,
            validFromTimestamp: toUint32(block.timestamp),
            observationsTimestamp: toUint32(block.timestamp),
            nativeFee: s_nativeFee,
            linkFee: s_linkFee,
            expiresAt: toUint32(block.timestamp + s_expiresPeriod),
            bestAsk: s_ask,
            bestBid: s_bid,
            askVolume: 0,
            bidVolume: 0,
            lastTradedPrice: s_price
        });
        bytes memory reportData = abi.encode(report);
        signedReport = signReport(reportData);
    }

    function updatePrice(int192 price) public {
        s_price = price;
        int192 delta = price / 1000; // 0.1% = 1/1000
        s_bid = price - delta;
        s_ask = price + delta;
    }

    function updatePriceBidAndAsk(int192 price, int192 bid, int192 ask) external {
        // bid < price < ask
        if (bid >= price) revert MockReportGenerator__InvalidBid();
        if (ask <= price) revert MockReportGenerator__InvalidAsk();

        s_price = price;
        s_bid = bid;
        s_ask = ask;
    }

    function updateExpiresPeriod(uint32 period) external {
        s_expiresPeriod = period;
    }

    function updateMarketStatus(uint32 status) external {
        s_marketStatus = status;
    }

    function updateFees(uint192 nativeFee, uint192 linkFee) external {
        s_nativeFee = nativeFee;
        s_linkFee = linkFee;
    }

    function getMockDonAddress() external view returns (address) {
        return i_donAddress;
    }

    function signReport(bytes memory reportData) private returns (bytes memory signedReport) {
        bytes32[3] memory reportContext;
        bytes32[] memory rawRs = new bytes32[](1);
        bytes32[] memory rawSs = new bytes32[](1);
        bytes32 rawVs;

        reportContext[0] = bytes32(i_donDigest);
        reportContext[1] = ""; // not needed for mocks
        reportContext[2] = ""; // not needed for mocks

        vm.startPrank(i_donAddress);
        bytes32 hashedReport = keccak256(reportData);
        bytes32 h = keccak256(abi.encodePacked(hashedReport, reportContext));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(i_donDigest, h);
        vm.stopPrank();

        rawRs[0] = r;
        rawSs[0] = s;
        rawVs = bytes32(uint256(v));

        return abi.encode(reportContext, reportData, rawRs, rawSs, rawVs);
    }

    function toUint32(uint256 timestamp) private pure returns (uint32) {
        if (timestamp > type(uint32).max) {
            revert MockReportGenerator__CastOverflow();
        }
        return uint32(timestamp);
    }

    function toUint64(uint256 value) private pure returns (uint64) {
        if (value > type(uint64).max) {
            revert MockReportGenerator__CastOverflow();
        }
        return uint64(value);
    }
}
