// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
/// @notice Test-only mocks for the JavaScript helper `scripts/CCIPLocalSimulatorFork.js`'s OffRamp lookup and
/// execution paths (log decoding fixtures live in `test/unit/ccip/fixtures/*.abi.json` instead, since they need no
/// on-chain state). These mirror the Solidity-side mocks in `test/unit/ccip/CCIPLocalSimulatorForkRouting.t.sol` /
/// `CCIPLocalSimulatorForkV2Routing.t.sol`, adapted to the exact call shapes the JS helper makes (its ABI fragments
/// are the source of truth for shapes here, since this file exists to test that JS code, not the Solidity mirror).
/// Deployed on a local (non-forked) Hardhat EDR network — never on a real chain.

/// @notice Minimal CCIP Router mock: a configurable list of (sourceChainSelector, offRamp) pairs.
contract JsMockRouter {
    struct Entry {
        uint64 sourceChainSelector;
        address offRamp;
    }

    Entry[] internal s_offRamps;

    function addOffRamp(uint64 sourceChainSelector, address offRamp) external {
        s_offRamps.push(Entry({sourceChainSelector: sourceChainSelector, offRamp: offRamp}));
    }

    function getOffRamps() external view returns (Entry[] memory) {
        return s_offRamps;
    }
}

/// @notice Pre-1.6 `EVM2EVMOffRamp`-shaped mock (1.2.x has no per-token gas override overload; 1.5.x does).
contract JsMockPreV1dot6OffRamp {
    struct StaticConfig {
        address commitStore;
        uint64 chainSelector;
        uint64 sourceChainSelector;
        address onRamp;
        address prevOffRamp;
        address rmnProxy;
        address tokenAdminRegistry;
    }

    struct EVMTokenAmount {
        address token;
        uint256 amount;
    }

    struct EVM2EVMMessage {
        uint64 sourceChainSelector;
        address sender;
        address receiver;
        uint64 sequenceNumber;
        uint256 gasLimit;
        bool strict;
        uint64 nonce;
        address feeToken;
        uint256 feeTokenAmount;
        bytes data;
        EVMTokenAmount[] tokenAmounts;
        bytes[] sourceTokenData;
        bytes32 messageId;
    }

    string public typeAndVersion;
    StaticConfig internal s_staticConfig;
    bytes internal s_revertData;

    uint256 public callsWithoutOverridesCount;
    uint256 public callsWithOverridesCount;
    uint32[] internal s_lastTokenGasOverrides;

    constructor(string memory typeAndVersion_, uint64 chainSelector_, uint64 sourceChainSelector_, address onRamp_) {
        typeAndVersion = typeAndVersion_;
        s_staticConfig = StaticConfig({
            commitStore: address(0x1),
            chainSelector: chainSelector_,
            sourceChainSelector: sourceChainSelector_,
            onRamp: onRamp_,
            prevOffRamp: address(0),
            rmnProxy: address(0x2),
            tokenAdminRegistry: address(0x3)
        });
    }

    function getStaticConfig() external view returns (StaticConfig memory) {
        return s_staticConfig;
    }

    /// @dev When set, both overloads below revert with this raw data instead of succeeding.
    function setRevertData(bytes calldata data) external {
        s_revertData = data;
    }

    function executeSingleMessage(EVM2EVMMessage memory, bytes[] calldata) external {
        if (s_revertData.length > 0) _revertRaw();
        callsWithoutOverridesCount++;
    }

    function executeSingleMessage(EVM2EVMMessage memory, bytes[] calldata, uint32[] calldata tokenGasOverrides)
        external
    {
        if (s_revertData.length > 0) _revertRaw();
        callsWithOverridesCount++;
        s_lastTokenGasOverrides = tokenGasOverrides;
    }

    function lastTokenGasOverrides() external view returns (uint32[] memory) {
        return s_lastTokenGasOverrides;
    }

    function _revertRaw() internal view {
        bytes memory data = s_revertData;
        assembly {
            revert(add(data, 32), mload(data))
        }
    }
}

/// @notice 1.6-shaped OffRamp mock.
contract JsMockV1dot6OffRamp {
    struct SourceChainConfig {
        address router;
        bool isEnabled;
        uint64 minSeqNr;
        bool isRMNVerificationDisabled;
        bytes onRamp;
    }

    struct StaticConfig {
        uint64 chainSelector;
        uint16 gasForCallExactCheck;
        address rmnRemote;
        address tokenAdminRegistry;
        address nonceManager;
    }

    struct RampMessageHeader {
        bytes32 messageId;
        uint64 sourceChainSelector;
        uint64 destChainSelector;
        uint64 sequenceNumber;
        uint64 nonce;
    }

    struct Any2EVMTokenTransfer {
        bytes sourcePoolAddress;
        address destTokenAddress;
        uint32 destGasAmount;
        bytes extraData;
        uint256 amount;
    }

    struct Any2EVMRampMessage {
        RampMessageHeader header;
        bytes sender;
        bytes data;
        address receiver;
        uint256 gasLimit;
        Any2EVMTokenTransfer[] tokenAmounts;
    }

    uint64 internal immutable i_sourceChainSelector;
    address internal immutable i_onRamp;
    bytes internal s_revertData;

    string public typeAndVersion = "OffRamp 1.6.0";
    uint256 public callCount;
    uint32[] internal s_lastTokenGasOverrides;
    bytes public lastSender;

    constructor(uint64 sourceChainSelector_, address onRamp_, uint64 localChainSelector_) {
        i_sourceChainSelector = sourceChainSelector_;
        i_onRamp = onRamp_;
        s_staticConfig.chainSelector = localChainSelector_;
    }

    StaticConfig internal s_staticConfig;

    function getStaticConfig() external view returns (StaticConfig memory) {
        return s_staticConfig;
    }

    function getSourceChainConfig(uint64 sourceChainSelector) external view returns (SourceChainConfig memory cfg) {
        if (sourceChainSelector != i_sourceChainSelector) return cfg;
        cfg.router = address(0xBEEF);
        cfg.isEnabled = true;
        cfg.minSeqNr = 1;
        cfg.onRamp = abi.encode(i_onRamp);
    }

    function setRevertData(bytes calldata data) external {
        s_revertData = data;
    }

    function executeSingleMessage(
        Any2EVMRampMessage memory message,
        bytes[] calldata,
        uint32[] calldata tokenGasOverrides
    ) external {
        if (s_revertData.length > 0) _revertRaw();
        callCount++;
        s_lastTokenGasOverrides = tokenGasOverrides;
        lastSender = message.sender;
    }

    function lastTokenGasOverrides() external view returns (uint32[] memory) {
        return s_lastTokenGasOverrides;
    }

    function _revertRaw() internal view {
        bytes memory data = s_revertData;
        assembly {
            revert(add(data, 32), mload(data))
        }
    }
}

/// @notice CCIP 2.0-shaped OffRamp mock: configurable CCVs-for-message answer and execution outcome.
contract JsMockV2OffRamp {
    struct SourceChainConfig {
        address router;
        bool isEnabled;
        bytes[] onRamps;
        address[] defaultCCVs;
        address[] laneMandatedCCVs;
    }

    event ExecutionStateChanged(
        uint64 indexed sourceChainSelector,
        uint64 indexed messageNumber,
        bytes32 indexed messageId,
        uint8 state,
        bytes returnData
    );

    string public typeAndVersion = "OffRamp 2.0.0";

    uint64 internal immutable i_sourceChainSelector;
    bytes[] internal s_onRamps;

    address[] internal s_requiredCCVs;
    address[] internal s_optionalCCVs;
    uint8 internal s_threshold;
    bool internal s_getCCVsReverts;
    bytes internal s_getCCVsRevertData;

    // 2 = SUCCESS, 1 = FAILURE (mirrors `Internal.MessageExecutionState`).
    uint8 internal s_resultState = 2;
    bytes internal s_resultReturnData;
    bool internal s_executeReverts;
    bytes internal s_executeRevertData;

    address[] internal s_lastCcvs;
    bytes[] internal s_lastVerifierResults;
    bool public executeCalled;

    constructor(uint64 sourceChainSelector_, address[] memory onRamps_) {
        i_sourceChainSelector = sourceChainSelector_;
        for (uint256 i; i < onRamps_.length; ++i) {
            s_onRamps.push(abi.encode(onRamps_[i]));
        }
    }

    function getSourceChainConfig(uint64 sourceChainSelector) external view returns (SourceChainConfig memory cfg) {
        if (sourceChainSelector != i_sourceChainSelector) return cfg;
        cfg.router = address(0xBEEF);
        cfg.isEnabled = true;
        cfg.onRamps = s_onRamps;
        cfg.defaultCCVs = new address[](0);
        cfg.laneMandatedCCVs = new address[](0);
    }

    function setCCVsForMessage(address[] memory required_, address[] memory optional_, uint8 threshold_) external {
        s_requiredCCVs = required_;
        s_optionalCCVs = optional_;
        s_threshold = threshold_;
    }

    function setGetCCVsReverts(bytes calldata data) external {
        s_getCCVsReverts = true;
        s_getCCVsRevertData = data;
    }

    function getCCVsForMessage(bytes calldata)
        external
        view
        returns (address[] memory requiredCCVs, address[] memory optionalCCVs, uint8 threshold)
    {
        if (s_getCCVsReverts) _revertRaw(s_getCCVsRevertData);
        return (s_requiredCCVs, s_optionalCCVs, s_threshold);
    }

    /// @param resultState 2 = SUCCESS, 1 = FAILURE.
    function setExecutionResult(uint8 resultState, bytes calldata returnData) external {
        s_resultState = resultState;
        s_resultReturnData = returnData;
    }

    function setExecuteReverts(bytes calldata data) external {
        s_executeReverts = true;
        s_executeRevertData = data;
    }

    function lastCcvs() external view returns (address[] memory) {
        return s_lastCcvs;
    }

    function lastVerifierResults() external view returns (bytes[] memory) {
        return s_lastVerifierResults;
    }

    function execute(bytes calldata encodedMessage, address[] calldata ccvs, bytes[] calldata verifierResults, uint32)
        external
    {
        if (s_executeReverts) _revertRaw(s_executeRevertData);
        executeCalled = true;
        s_lastCcvs = ccvs;
        delete s_lastVerifierResults;
        for (uint256 i; i < verifierResults.length; ++i) {
            s_lastVerifierResults.push(verifierResults[i]);
        }
        bytes32 messageId = keccak256(encodedMessage);
        emit ExecutionStateChanged(i_sourceChainSelector, 1, messageId, s_resultState, s_resultReturnData);
    }

    function getExecutionState(bytes32) external view returns (uint8) {
        return s_resultState;
    }

    function _revertRaw(bytes memory data) internal pure {
        assembly {
            revert(add(data, 32), mload(data))
        }
    }
}

/// @notice Owner-configurable versioned verifier resolver (the production CCV shape on 2.0 lanes).
contract JsMockVersionedResolver {
    struct InboundImplementationArgs {
        bytes4 version;
        address verifier;
    }

    address public immutable owner;
    mapping(bytes4 version => address verifier) public inboundImplementation;

    constructor(address owner_) {
        owner = owner_;
    }

    function applyInboundImplementationUpdates(InboundImplementationArgs[] calldata implementations) external {
        require(msg.sender == owner, "only owner");
        for (uint256 i; i < implementations.length; ++i) {
            inboundImplementation[implementations[i].version] = implementations[i].verifier;
        }
    }
}

/// @notice Future/unknown OffRamp version: must be skipped by the lookup, never guessed at.
contract JsMockUnknownOffRamp {
    function typeAndVersion() external pure returns (string memory) {
        return "OffRamp 9.0.0";
    }
}
