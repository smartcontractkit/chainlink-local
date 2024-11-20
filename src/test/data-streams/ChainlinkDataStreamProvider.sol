// Simplifed version of https://github.com/gmx-io/gmx-synthetics/blob/main/contracts/oracle/ChainlinkDataStreamProvider.sol used for testing purposes
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IChainlinkDataStreamVerifier {
    /**
     * @notice Verifies that the data encoded has been signed
     * correctly by routing to the correct verifier, and bills the user if applicable.
     * @param payload The encoded data to be verified, including the signed
     * report.
     * @param parameterPayload fee metadata for billing. For the current implementation this is just the abi-encoded fee token ERC-20 address
     * @return verifierResponse The encoded report from the verifier.
     */
    function verify(bytes calldata payload, bytes calldata parameterPayload)
        external
        payable
        returns (bytes memory verifierResponse);
}

contract ChainlinkDataStreamProvider {
    bytes32 public constant DATA_STREAM_ID = keccak256(abi.encode("DATA_STREAM_ID"));
    bytes32 public constant CHAINLINK_PAYMENT_TOKEN = keccak256(abi.encode("CHAINLINK_PAYMENT_TOKEN"));

    IChainlinkDataStreamVerifier public immutable verifier;

    mapping(bytes32 => address) public addressValues;
    mapping(bytes32 => bytes32) public bytes32Values;

    // bid: min price, highest buy price
    // ask: max price, lowest sell price
    struct Report {
        bytes32 feedId; // The feed ID the report has data for
        uint32 validFromTimestamp; // Earliest timestamp for which price is applicable
        uint32 observationsTimestamp; // Latest timestamp for which price is applicable
        uint192 nativeFee; // Base cost to validate a transaction using the report, denominated in the chain’s native token (WETH/ETH)
        uint192 linkFee; // Base cost to validate a transaction using the report, denominated in LINK
        uint32 expiresAt; // Latest timestamp where the report can be verified onchain
        int192 price; // DON consensus median price, carried to 8 decimal places
        int192 bid; // Simulated price impact of a buy order up to the X% depth of liquidity utilisation
        int192 ask; // Simulated price impact of a sell order up to the X% depth of liquidity utilisation
    }

    error EmptyChainlinkPaymentToken();
    error EmptyDataStreamFeedId(address token);
    error InvalidDataStreamFeedId(address token, bytes32 reportFeedId, bytes32 expectedFeedId);
    error InvalidDataStreamPrices(address token, int192 bid, int192 ask);
    error InvalidDataStreamBidAsk(address token, int192 bid, int192 ask);

    constructor(address _verifier, address linkTokenAddress) {
        verifier = IChainlinkDataStreamVerifier(_verifier);
        addressValues[CHAINLINK_PAYMENT_TOKEN] = linkTokenAddress;
    }

    function setBytes32(address token, bytes32 feedId) external {
        bytes32Values[dataStreamIdKey(token)] = feedId;
    }

    // @dev key for data stream feed ID
    // @param token the token to get the key for
    // @return key for data stream feed ID
    function dataStreamIdKey(address token) internal pure returns (bytes32) {
        return keccak256(abi.encode(DATA_STREAM_ID, token));
    }

    function getOraclePrice(address token, bytes memory data)
        external
        returns (address token_, int192 bid, int192 ask, uint32 timestamp)
    {
        bytes32 feedId = bytes32Values[dataStreamIdKey(token)];
        if (feedId == bytes32(0)) {
            revert EmptyDataStreamFeedId(token);
        }

        bytes memory payloadParameter = _getPayloadParameter();
        bytes memory verifierResponse = verifier.verify(data, payloadParameter);

        Report memory report = abi.decode(verifierResponse, (Report));

        if (feedId != report.feedId) {
            revert InvalidDataStreamFeedId(token, report.feedId, feedId);
        }

        if (report.bid <= 0 || report.ask <= 0) {
            revert InvalidDataStreamPrices(token, report.bid, report.ask);
        }

        if (report.bid > report.ask) {
            revert InvalidDataStreamBidAsk(token, report.bid, report.ask);
        }

        return (token, report.bid, report.ask, report.observationsTimestamp);
    }

    function _getPayloadParameter() internal view returns (bytes memory) {
        // LINK token address
        address feeToken = addressValues[CHAINLINK_PAYMENT_TOKEN];

        if (feeToken == address(0)) {
            revert EmptyChainlinkPaymentToken();
        }

        return abi.encode(feeToken);
    }
}
