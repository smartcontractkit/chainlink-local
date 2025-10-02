// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {
    DataStreamsLocalSimulator,
    MockVerifierProxy,
    MockFeeManager,
    LinkToken
} from "@chainlink/local/src/data-streams/DataStreamsLocalSimulator.sol";
import {MockReportGenerator} from "@chainlink/local/src/data-streams/MockReportGenerator.sol";

import {ClientReportsVerifier} from "../../../src/test/data-streams/ClientReportsVerifier.sol";

contract BillingMechanismsTest is Test {
    MockReportGenerator public mockReportGenerator;
    int192 public initialPrice;

    function setUp() public {
        initialPrice = 1 ether;
        mockReportGenerator = new MockReportGenerator(initialPrice);
        mockReportGenerator.updateFees(1 ether, 0.5 ether);
    }

    function test_onChainBillingMechanism() public {
        // Deploy simulator (defaults to on-chain billing for backward compatibility)
        DataStreamsLocalSimulator dataStreamsLocalSimulator = new DataStreamsLocalSimulator();
        (, LinkToken linkToken_,, MockVerifierProxy mockVerifierProxy_, MockFeeManager mockFeeManager_,) =
            dataStreamsLocalSimulator.configuration();

        // Verify fee manager is deployed by default
        assertFalse(address(mockFeeManager_) == address(0), "Fee manager should be deployed by default");
        assertEq(address(mockVerifierProxy_.s_feeManager()), address(mockFeeManager_), "Fee manager should be set on verifier proxy");
        assertTrue(dataStreamsLocalSimulator.feeManagerEnabled(), "Fee manager should be enabled by default");

        // Deploy consumer contract
        ClientReportsVerifier consumer = new ClientReportsVerifier(address(mockVerifierProxy_));

        // Fund consumer with LINK tokens
        dataStreamsLocalSimulator.requestLinkFromFaucet(address(consumer), 1 ether);

        // Generate and verify report
        (bytes memory signedReportV3,) = mockReportGenerator.generateReportV3();
        consumer.verifyReport(signedReportV3);

        // Verify price was decoded correctly
        int192 lastDecodedPrice = consumer.lastDecodedPrice();
        assertEq(lastDecodedPrice, initialPrice, "Price should be decoded correctly with on-chain billing");
    }

    function test_offChainBillingMechanism() public {
        // Deploy simulator and toggle to off-chain billing
        DataStreamsLocalSimulator dataStreamsLocalSimulator = new DataStreamsLocalSimulator();
        
        // Switch to off-chain billing mechanism
        dataStreamsLocalSimulator.enableOffChainBilling();
        
        (, LinkToken linkToken_,, MockVerifierProxy mockVerifierProxy_, MockFeeManager mockFeeManager_,) =
            dataStreamsLocalSimulator.configuration();

        // Verify fee manager is NOT set on verifier proxy
        assertTrue(address(mockFeeManager_) == address(0), "Fee manager should not be set on verifier proxy");
        assertEq(address(mockVerifierProxy_.s_feeManager()), address(0), "Fee manager should not be set on verifier proxy");
        assertFalse(dataStreamsLocalSimulator.feeManagerEnabled(), "Fee manager should be disabled");

        // Deploy a simplified consumer that handles off-chain billing
        OffChainBillingConsumer consumer = new OffChainBillingConsumer(address(mockVerifierProxy_));

        // Generate and verify report (no LINK funding needed for off-chain billing)
        (bytes memory signedReportV3,) = mockReportGenerator.generateReportV3();
        consumer.verifyReport(signedReportV3);

        // Verify price was decoded correctly
        int192 lastDecodedPrice = consumer.lastDecodedPrice();
        assertEq(lastDecodedPrice, initialPrice, "Price should be decoded correctly with off-chain billing");
    }

    function test_backwardCompatibility() public {
        // Test that default constructor enables fee manager (maintaining existing behavior)
        DataStreamsLocalSimulator dataStreamsLocalSimulator = new DataStreamsLocalSimulator();
        (,,,, MockFeeManager mockFeeManager_,) = dataStreamsLocalSimulator.configuration();
        
        assertFalse(address(mockFeeManager_) == address(0), "Default constructor should enable fee manager for backward compatibility");
        assertTrue(dataStreamsLocalSimulator.feeManagerEnabled(), "Fee manager should be enabled by default");
    }

    function test_billingMechanismToggle() public {
        // Test toggling between billing mechanisms
        DataStreamsLocalSimulator dataStreamsLocalSimulator = new DataStreamsLocalSimulator();
        
        // Initially should be on-chain billing
        assertTrue(dataStreamsLocalSimulator.feeManagerEnabled(), "Should start with on-chain billing");
        (,,,, MockFeeManager mockFeeManager1,) = dataStreamsLocalSimulator.configuration();
        assertFalse(address(mockFeeManager1) == address(0), "Fee manager should be set initially");
        
        // Switch to off-chain billing
        dataStreamsLocalSimulator.enableOffChainBilling();
        assertFalse(dataStreamsLocalSimulator.feeManagerEnabled(), "Should be off-chain billing after toggle");
        (,,,, MockFeeManager mockFeeManager2,) = dataStreamsLocalSimulator.configuration();
        assertTrue(address(mockFeeManager2) == address(0), "Fee manager should not be set after disabling");
        
        // Switch back to on-chain billing
        dataStreamsLocalSimulator.enableOnChainBilling();
        assertTrue(dataStreamsLocalSimulator.feeManagerEnabled(), "Should be on-chain billing after re-enabling");
        (,,,, MockFeeManager mockFeeManager3,) = dataStreamsLocalSimulator.configuration();
        assertFalse(address(mockFeeManager3) == address(0), "Fee manager should be set after re-enabling");
    }
}

/**
 * Simplified consumer contract that demonstrates off-chain billing mechanism
 */
contract OffChainBillingConsumer {
    struct ReportV3 {
        bytes32 feedId;
        uint32 validFromTimestamp;
        uint32 observationsTimestamp;
        uint192 nativeFee;
        uint192 linkFee;
        uint32 expiresAt;
        int192 price;
        int192 bid;
        int192 ask;
    }

    MockVerifierProxy public s_verifierProxy;
    int192 public lastDecodedPrice;

    event DecodedPrice(int192 price);

    constructor(address _verifierProxy) {
        s_verifierProxy = MockVerifierProxy(_verifierProxy);
    }

    function verifyReport(bytes memory unverifiedReport) external {
        // Check if fee manager exists (this is the key check for billing mechanism)
        address feeManager = address(s_verifierProxy.s_feeManager());
        
        bytes memory parameterPayload;
        if (feeManager != address(0)) {
            // On-chain billing: would need to handle fees (not implemented in this simple example)
            revert("This consumer only supports off-chain billing mechanism");
        } else {
            // Off-chain billing: no fee handling needed
            parameterPayload = bytes("");
        }

        // Verify the report through the VerifierProxy
        bytes memory verifiedReportData = s_verifierProxy.verify(unverifiedReport, parameterPayload);

        // Decode verified report data
        ReportV3 memory verifiedReport = abi.decode(verifiedReportData, (ReportV3));

        // Log and store price from the verified report
        emit DecodedPrice(verifiedReport.price);
        lastDecodedPrice = verifiedReport.price;
    }
}
