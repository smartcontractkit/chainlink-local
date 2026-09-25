// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title ICCVNoOpVerifierFork
/// @notice Minimal mirror of the CCIP 2.0 verifier interfaces (`ICrossChainVerifierV1` and
///         `ICrossChainVerifierResolver`, OnRamp/OffRamp 2.0.0). Types are declared locally, in the
///         same way `CCIPLocalSimulatorFork` declares the pre-1.6 and 1.6 fork surfaces, so the test
///         double stays bound to the on-chain wire format rather than to a pinned dependency version.
interface ICCVNoOpVerifierFork {
    /// @notice CCIP 2.0 message token transfer entry (`MessageV1Codec.TokenTransferV1`).
    struct TokenTransferV1 {
        uint256 amount;
        bytes sourcePoolAddress;
        bytes sourceTokenAddress;
        bytes destTokenAddress;
        bytes tokenReceiver;
        bytes extraData;
    }

    /// @notice CCIP 2.0 chain-agnostic message (`MessageV1Codec.MessageV1`), static fields first.
    struct MessageV1 {
        uint64 sourceChainSelector;
        uint64 destChainSelector;
        uint64 messageNumber;
        uint32 executionGasLimit;
        uint32 ccipReceiveGasLimit;
        bytes4 finality;
        bytes32 ccvAndExecutorHash;
        bytes onRampAddress;
        bytes offRampAddress;
        bytes sender;
        bytes receiver;
        bytes destBlob;
        TokenTransferV1[] tokenTransfer;
        bytes data;
    }

    struct EVMTokenAmount {
        address token;
        uint256 amount;
    }

    /// @notice Router client message (`Client.EVM2AnyMessage`).
    struct EVM2AnyMessage {
        bytes receiver;
        bytes data;
        EVMTokenAmount[] tokenAmounts;
        address feeToken;
        bytes extraArgs;
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function verifyMessage(MessageV1 memory message, bytes32 messageId, bytes memory verifierResults) external;

    function getFee(
        uint64 destChainSelector,
        EVM2AnyMessage memory message,
        bytes memory extraArgs,
        bytes4 requestedFinalityConfig
    ) external view returns (uint16 feeUSDCents, uint32 gasForVerification, uint32 payloadSizeBytes);

    function forwardToVerifier(
        MessageV1 calldata message,
        bytes32 messageId,
        address feeToken,
        uint256 feeTokenAmount,
        bytes calldata verifierArgs
    ) external returns (bytes memory verifierData);

    function getStorageLocations() external view returns (string[] memory storageLocations);

    function getInboundImplementation(bytes calldata verifierResults) external view returns (address verifierAddress);

    function getOutboundImplementation(uint64 destChainSelector, bytes memory extraArgs)
        external
        view
        returns (address verifierAddress);
}

/// @title CCVNoOpVerifier
/// @notice No-op CCV used by fork tests of CCIP 2.0 lanes. It accepts any message without performing
///         verification and resolves to itself for both inbound and outbound traffic, so a mocked
///         lane default CCV lets the permissionless execution path run end to end with all other
///         validation (quorum walk, token release/mint, receiver call) untouched.
/// @dev THIS CONTRACT PROVIDES NO VERIFICATION AND MUST ONLY BE USED ON LOCAL FORKS.
contract CCVNoOpVerifier is ICCVNoOpVerifierFork {
    bytes4 internal constant IERC165_INTERFACE_ID = 0x01ffc9a7;

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(ICCVNoOpVerifierFork).interfaceId || interfaceId == IERC165_INTERFACE_ID;
    }

    function verifyMessage(MessageV1 memory, bytes32, bytes memory) external override {}

    function getFee(uint64, EVM2AnyMessage memory, bytes memory, bytes4)
        external
        pure
        override
        returns (uint16 feeUSDCents, uint32 gasForVerification, uint32 payloadSizeBytes)
    {
        return (0, 0, 0);
    }

    function forwardToVerifier(MessageV1 calldata, bytes32, address, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes memory verifierData)
    {
        return "";
    }

    function getStorageLocations() external pure override returns (string[] memory storageLocations) {
        storageLocations = new string[](1);
        storageLocations[0] = "mock://ccv";
        return storageLocations;
    }

    function getInboundImplementation(bytes calldata) external view override returns (address verifierAddress) {
        return address(this);
    }

    function getOutboundImplementation(uint64, bytes memory) external view override returns (address verifierAddress) {
        return address(this);
    }
}
