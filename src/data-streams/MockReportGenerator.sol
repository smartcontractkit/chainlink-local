// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ReportVersions} from "./ReportVersions.sol";

contract MockReportGenerator is Test, ReportVersions {
    address internal immutable i_donAddress;
    uint256 internal immutable i_donDigest;

    bytes32 internal immutable i_reportV2MockFeedId =
        hex"0002777777777777777777777777777777777777777777777777777777777777";
    bytes32 internal immutable i_reportV3MockFeedId =
        hex"0003777777777777777777777777777777777777777777777777777777777777";
    bytes32 internal immutable i_reportV4MockFeedId =
        hex"0004777777777777777777777777777777777777777777777777777777777777";

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

    function generateReport(ReportV2 calldata report) external returns (bytes memory signedReport) {
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
}
