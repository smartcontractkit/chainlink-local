// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";

library Common {
    struct Asset {
        address token;
        uint256 amount;
    }
}

interface IVerifierProxy {
    function verify(bytes calldata payload, bytes calldata parameterPayload)
        external
        payable
        returns (bytes memory verifierResponse);

    function verifyBulk(bytes[] calldata payloads, bytes calldata parameterPayload)
        external
        payable
        returns (bytes[] memory verifiedReports);

    function s_feeManager() external view returns (address);
}

interface IFeeManager {
    function getFeeAndReward(address subscriber, bytes memory unverifiedReport, address quoteAddress)
        external
        returns (Common.Asset memory, Common.Asset memory, uint256);

    function i_linkAddress() external view returns (address);

    function i_nativeAddress() external view returns (address);

    function i_rewardManager() external view returns (address);
}

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE FOR DEMONSTRATION PURPOSES.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract ClientReportsVerifier {
    using SafeERC20 for IERC20;

    error NothingToWithdraw();
    error NotOwner(address caller);
    error InvalidReportVersion(uint16 version);

    struct ReportV3 {
        bytes32 feedId; // The stream ID the report has data for.
        uint32 validFromTimestamp; // Earliest timestamp for which price is applicable.
        uint32 observationsTimestamp; // Latest timestamp for which price is applicable.
        uint192 nativeFee; // Base cost to validate a transaction using the report, denominated in the chain’s native token (e.g., WETH/ETH).
        uint192 linkFee; // Base cost to validate a transaction using the report, denominated in LINK.
        uint32 expiresAt; // Latest timestamp where the report can be verified onchain.
        int192 price; // DON consensus median price (8 or 18 decimals).
        int192 bid; // Simulated price impact of a buy order up to the X% depth of liquidity utilisation (8 or 18 decimals).
        int192 ask; // Simulated price impact of a sell order up to the X% depth of liquidity utilisation (8 or 18 decimals).
    }

    struct ReportV4 {
        bytes32 feedId; // The stream ID the report has data for.
        uint32 validFromTimestamp; // Earliest timestamp for which price is applicable.
        uint32 observationsTimestamp; // Latest timestamp for which price is applicable.
        uint192 nativeFee; // Base cost to validate a transaction using the report, denominated in the chain’s native token (e.g., WETH/ETH).
        uint192 linkFee; // Base cost to validate a transaction using the report, denominated in LINK.
        uint32 expiresAt; // Latest timestamp where the report can be verified onchain.
        int192 price; // DON consensus median benchmark price (8 or 18 decimals).
        uint32 marketStatus; // The DON's consensus on whether the market is currently open.
    }

    IVerifierProxy public s_verifierProxy;

    address private s_owner;
    int192 public lastDecodedPrice;

    event DecodedPrice(int192 price);

    constructor(address _verifierProxy) {
        s_owner = msg.sender;
        s_verifierProxy = IVerifierProxy(_verifierProxy);
    }

    modifier onlyOwner() {
        if (msg.sender != s_owner) revert NotOwner(msg.sender);
        _;
    }

    function verifyReport(bytes memory unverifiedReport) external {
        IFeeManager feeManager = IFeeManager(s_verifierProxy.s_feeManager());

        address rewardManager = feeManager.i_rewardManager();

        // Decode unverified report to extract report data
        (, bytes memory reportData) = abi.decode(unverifiedReport, (bytes32[3], bytes));

        // Extract report version from reportData
        uint16 reportVersion = (uint16(uint8(reportData[0])) << 8) | uint16(uint8(reportData[1]));

        // Validate report version
        if (reportVersion != 3 && reportVersion != 4) {
            revert InvalidReportVersion(uint8(reportVersion));
        }

        // Set the fee token address (LINK in this case)
        address feeTokenAddress = feeManager.i_linkAddress();

        // Calculate the fee required for report verification
        (Common.Asset memory fee,,) = feeManager.getFeeAndReward(address(this), reportData, feeTokenAddress);

        // Approve rewardManager to spend this contract's balance in fees
        IERC20(feeTokenAddress).approve(rewardManager, fee.amount);

        // Verify the report through the VerifierProxy
        bytes memory verifiedReportData = s_verifierProxy.verify(unverifiedReport, abi.encode(feeTokenAddress));

        // Decode verified report data into the appropriate Report struct based on reportVersion
        if (reportVersion == 3) {
            // v3 report schema
            ReportV3 memory verifiedReport = abi.decode(verifiedReportData, (ReportV3));

            // Log price from the verified report
            emit DecodedPrice(verifiedReport.price);

            // Store the price from the report
            lastDecodedPrice = verifiedReport.price;
        } else if (reportVersion == 4) {
            // v4 report schema
            ReportV4 memory verifiedReport = abi.decode(verifiedReportData, (ReportV4));

            // Log price from the verified report
            emit DecodedPrice(verifiedReport.price);

            // Store the price from the report
            lastDecodedPrice = verifiedReport.price;
        }
    }

    function withdrawToken(address _beneficiary, address _token) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));

        if (amount == 0) revert NothingToWithdraw();

        IERC20(_token).safeTransfer(_beneficiary, amount);
    }
}
