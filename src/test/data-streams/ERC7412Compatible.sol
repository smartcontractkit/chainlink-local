// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IERC165} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/interfaces/IERC165.sol";
import {OwnerIsCreator} from "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/interfaces/IERC20.sol";

interface IRewardManager is IERC165 {
    /**
     * @notice Record the fee received for a particular pool
     * @param payments array of structs containing pool id and amount
     * @param payee the user the funds should be retrieved from
     */
    function onFeePaid(FeePayment[] calldata payments, address payee) external;

    /**
     * @notice Claims the rewards in a specific pool
     * @param poolIds array of poolIds to claim rewards for
     */
    function claimRewards(bytes32[] calldata poolIds) external;

    /**
     * @notice Set the RewardRecipients and weights for a specific pool. This should only be called once per pool Id. Else updateRewardRecipients should be used.
     * @param poolId poolId to set RewardRecipients and weights for
     * @param rewardRecipientAndWeights array of each RewardRecipient and associated weight
     */
    function setRewardRecipients(bytes32 poolId, Common.AddressAndWeight[] calldata rewardRecipientAndWeights)
        external;

    /**
     * @notice Updates a subset the reward recipients for a specific poolId. The collective weight of the recipients should add up to the recipients existing weights. Any recipients with a weight of 0 will be removed.
     * @param poolId the poolId to update
     * @param newRewardRecipients array of new reward recipients
     */
    function updateRewardRecipients(bytes32 poolId, Common.AddressAndWeight[] calldata newRewardRecipients) external;

    /**
     * @notice Pays all the recipients for each of the pool ids
     * @param poolId the pool id to pay recipients for
     * @param recipients array of recipients to pay within the pool
     */
    function payRecipients(bytes32 poolId, address[] calldata recipients) external;

    /**
     * @notice Sets the fee manager. This needs to be done post construction to prevent a circular dependency.
     * @param newFeeManager address of the new verifier proxy
     */
    function setFeeManager(address newFeeManager) external;

    /**
     * @notice Gets a list of pool ids which have reward for a specific recipient.
     * @param recipient address of the recipient to get pool ids for
     * @param startIndex the index to start from
     * @param endIndex the index to stop at
     */
    function getAvailableRewardPoolIds(address recipient, uint256 startIndex, uint256 endIndex)
        external
        view
        returns (bytes32[] memory);

    /**
     * @notice The structure to hold a fee payment notice
     * @param poolId the poolId receiving the payment
     * @param amount the amount being paid
     */
    struct FeePayment {
        bytes32 poolId;
        uint192 amount;
    }
}

interface IVerifierFeeManager is IERC165 {
    /**
     * @notice Handles fees for a report from the subscriber and manages rewards
     * @param payload report to process the fee for
     * @param parameterPayload fee payload
     * @param subscriber address of the fee will be applied
     */
    function processFee(bytes calldata payload, bytes calldata parameterPayload, address subscriber) external payable;

    /**
     * @notice Processes the fees for each report in the payload, billing the subscriber and paying the reward manager
     * @param payloads reports to process
     * @param parameterPayload fee payload
     * @param subscriber address of the user to process fee for
     */
    function processFeeBulk(bytes[] calldata payloads, bytes calldata parameterPayload, address subscriber)
        external
        payable;

    /**
     * @notice Sets the fee recipients according to the fee manager
     * @param configDigest digest of the configuration
     * @param rewardRecipientAndWeights the address and weights of all the recipients to receive rewards
     */
    function setFeeRecipients(bytes32 configDigest, Common.AddressAndWeight[] calldata rewardRecipientAndWeights)
        external;
}

/*
 * @title Common
 * @author Michael Fletcher
 * @notice Common functions and structs
 */
library Common {
    // @notice The asset struct to hold the address of an asset and amount
    struct Asset {
        address assetAddress;
        uint256 amount;
    }

    // @notice Struct to hold the address and its associated weight
    struct AddressAndWeight {
        address addr;
        uint64 weight;
    }

    /**
     * @notice Checks if an array of AddressAndWeight has duplicate addresses
     * @param recipients The array of AddressAndWeight to check
     * @return bool True if there are duplicates, false otherwise
     */
    function _hasDuplicateAddresses(Common.AddressAndWeight[] memory recipients) internal pure returns (bool) {
        for (uint256 i = 0; i < recipients.length;) {
            for (uint256 j = i + 1; j < recipients.length;) {
                if (recipients[i].addr == recipients[j].addr) {
                    return true;
                }
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }
}

interface IVerifierProxy {
    function verify(bytes calldata payload, bytes calldata parameterPayload)
        external
        payable
        returns (bytes memory verifierResponse);

    function s_feeManager() external view returns (IVerifierFeeManager);
}

interface IFeeManager {
    function getFeeAndReward(address subscriber, bytes memory report, address quoteAddress)
        external
        returns (Common.Asset memory, Common.Asset memory, uint256);

    function i_linkAddress() external view returns (address);

    function i_nativeAddress() external view returns (address);

    function i_rewardManager() external view returns (address);
}

/**
 * @title ERC-7412 Off-Chain Data Retrieval Contract
 */
interface IERC7412 {
    /**
     * @dev Emitted when an oracle is requested to provide data. Upon receipt of this error, a wallet client
     * should automatically resolve the requested oracle data and call fulfillOracleQuery.
     * @param oracleContract The address of the oracle contract (which is also the fulfillment contract).
     * @param oracleQuery The query to be sent to the off-chain interface.
     */
    error OracleDataRequired(address oracleContract, bytes oracleQuery);

    /**
     * @dev Emitted when the recently posted oracle data requires a fee to be paid. Upon receipt of this error,
     * a wallet client should attach the requested feeAmount to the most recently posted oracle data transaction
     */
    error FeeRequired(uint256 feeAmount);

    /**
     * @dev Returns a human-readable identifier of the oracle contract. This should map to a URL and API
     * key on the client side.
     * @return The oracle identifier.
     */
    function oracleId() external view returns (bytes32);

    /**
     * @dev Upon resolving the oracle query, the client should call this function to post the data to the
     * blockchain.
     * @param signedOffchainData The data that was returned from the off-chain interface, signed by the oracle.
     */
    function fulfillOracleQuery(bytes calldata signedOffchainData) external payable;
}

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract DataStreamsERC7412Compatible is IERC7412, OwnerIsCreator {
    struct BasicReport {
        bytes32 feedId; // The feed ID the report has data for
        uint32 validFromTimestamp; // Earliest timestamp for which price is applicable
        uint32 observationsTimestamp; // Latest timestamp for which price is applicable
        uint192 nativeFee; // Base cost to validate a transaction using the report, denominated in the chain’s native token (WETH/ETH)
        uint192 linkFee; // Base cost to validate a transaction using the report, denominated in LINK
        uint32 expiresAt; // Latest timestamp where the report can be verified on-chain
        int192 price; // DON consensus median price, carried to 8 decimal places
    }

    struct LatestPriceData {
        int192 price; // DON consensus median price, carried to 8 decimal places
        uint32 expiresAt; // Latest timestamp where the report can be verified on-chain
        uint32 cacheTimestamp; // The timestamp when the entry to the s_latestPrice mapping has been made
    }

    /**
     * @notice The Chainlink Verifier Contract
     * This contract verifies the signature from the DON to cryptographically guarantee that the report has not been altered
     * from the time that the DON reached consensus to the point where you use the data in your application.
     */
    IVerifierProxy public verifier;

    string public constant STRING_DATASTREAMS_FEEDLABEL = "feedIDs";
    string public constant STRING_DATASTREAMS_QUERYLABEL = "timestamp";

    mapping(bytes32 => LatestPriceData) public s_latestPrice;

    event PriceUpdate(int192 indexed price, bytes32 indexed feedId);

    /**
     * @dev Value doesn't fit in an uint of `bits` size.
     */
    error SafeCastOverflowedUintDowncast(uint8 bits, uint256 value);
    error FailedToWithdrawEth(address owner, address target, uint256 value);

    constructor(address _verifier) {
        verifier = IVerifierProxy(_verifier);
    }

    receive() external payable {}

    /**
     * @notice Emits an OracleDataRequired error when an oracle is requested to provide data
     * @param feedId - Stream ID which can be found at https://docs.chain.link/data-streams/stream-ids
     *                  For example, Basic ETH/USD price report is 0x00027bbaff688c906a3e20a34fe951715d1018d262a5b66e38eda027a674cd1b
     */
    function generate7412CompatibleCall(bytes32 feedId, uint32 stalenessTolerance) public view returns (int192) {
        LatestPriceData memory latestPrice = s_latestPrice[feedId];
        uint32 considerStaleAfter = latestPrice.cacheTimestamp + stalenessTolerance;

        if (considerStaleAfter > toUint32(block.timestamp) && latestPrice.expiresAt > considerStaleAfter) {
            return latestPrice.price;
        }

        bytes memory oracleQuery =
            abi.encode(STRING_DATASTREAMS_FEEDLABEL, feedId, STRING_DATASTREAMS_QUERYLABEL, block.timestamp, "");

        revert IERC7412.OracleDataRequired(address(this), oracleQuery);
    }

    function oracleId() external pure override returns (bytes32) {
        return "CHAINLINK_DATA_STREAMS";
    }

    function fulfillOracleQuery(bytes calldata signedOffchainData) external payable override {
        (, bytes memory reportData) = abi.decode(signedOffchainData, (bytes32[3], bytes));

        // Handle billing
        IFeeManager feeManager = IFeeManager(address(verifier.s_feeManager()));
        IRewardManager rewardManager = IRewardManager(address(feeManager.i_rewardManager()));

        // Fees can be paid in either LINK (i_linkAddress()) or native coin ERC20-wrapped version (i_nativeAddress())
        address feeTokenAddress = feeManager.i_linkAddress();
        (Common.Asset memory fee,,) = feeManager.getFeeAndReward(address(this), reportData, feeTokenAddress);

        if (IERC20(feeTokenAddress).balanceOf(address(this)) < fee.amount) {
            revert IERC7412.FeeRequired(fee.amount);
        } else {
            IERC20(feeTokenAddress).approve(address(rewardManager), fee.amount);
        }

        // Verify the report
        bytes memory verifiedReportData = verifier.verify(signedOffchainData, abi.encode(feeTokenAddress));

        // Decode verified report data into BasicReport struct
        BasicReport memory verifiedReport = abi.decode(verifiedReportData, (BasicReport));

        s_latestPrice[verifiedReport.feedId] = LatestPriceData({
            price: verifiedReport.price,
            expiresAt: verifiedReport.expiresAt,
            cacheTimestamp: toUint32(block.timestamp)
        });

        // Log price from report
        emit PriceUpdate(verifiedReport.price, verifiedReport.feedId);
    }

    /**
     * OpenZeppelin Contracts (last updated v5.0.0) (utils/math/SafeCast.sol)
     *
     * @dev Returns the downcasted uint32 from uint256, reverting on
     * overflow (when the input is greater than largest uint32).
     *
     * Counterpart to Solidity's `uint32` operator.
     *
     * Requirements:
     *
     * - input must fit into 32 bits
     */
    function toUint32(uint256 value) internal pure returns (uint32) {
        if (value > type(uint32).max) {
            revert SafeCastOverflowedUintDowncast(32, value);
        }
        return uint32(value);
    }

    function withdraw(address beneficiary) public onlyOwner {
        uint256 amount = address(this).balance;
        (bool sent,) = beneficiary.call{value: amount}("");
        if (!sent) revert FailedToWithdrawEth(msg.sender, beneficiary, amount);
    }

    function withdrawToken(address beneficiary, address token) public onlyOwner {
        uint256 amount = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(beneficiary, amount);
    }
}
