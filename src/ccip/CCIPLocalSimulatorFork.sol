// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test, Vm, console2} from "forge-std/Test.sol";
import {Register} from "./Register.sol";
import {Internal} from "@chainlink/contracts-ccip/contracts/libraries/Internal.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IERC20} from "../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

/// @title IRouterFork Interface
interface IRouterFork {
    /**
     * @notice Structure representing an offRamp configuration
     *
     * @param sourceChainSelector - The chain selector for the source chain
     * @param offRamp - The address of the offRamp contract
     */
    struct OffRamp {
        uint64 sourceChainSelector;
        address offRamp;
    }

    /**
     * @notice Return the configured onramp for specific a destination chain.
     *  @param destChainSelector The destination chain Id to get the onRamp for.
     * @return The address of the onRamp.
     */
    function getOnRamp(uint64 destChainSelector) external view returns (address);

    /**
     * @notice Gets the list of offRamps
     *
     * @return offRamps - Array of OffRamp structs
     */
    function getOffRamps() external view returns (OffRamp[] memory);
}

/// @title IEVM2EVMOffRampFork Interface
interface IEVM2EVMOffRampFork {
    /**
     * @notice Executes a single CCIP message on the offRamp
     *
     * @param message - The CCIP message to be executed
     * @param offchainTokenData - Additional offchain token data
     */
    function executeSingleMessage(
        Internal.Any2EVMRampMessage memory message,
        bytes[] calldata offchainTokenData,
        uint32[] calldata tokenGasOverrides
    ) external;
}

interface InternalPreV1dot6 {
    struct EVM2EVMMessage {
        uint64 sourceChainSelector; // ────────╮ the chain selector of the source chain, note: not chainId
        address sender; // ────────────────────╯ sender address on the source chain
        address receiver; // ──────────────────╮ receiver address on the destination chain
        uint64 sequenceNumber; // ─────────────╯ sequence number, not unique across lanes
        uint256 gasLimit; //                     user supplied maximum gas amount available for dest chain execution
        bool strict; // ───────────────────────╮ DEPRECATED
        uint64 nonce; //                       │ nonce for this lane for this sender, not unique across senders/lanes
        address feeToken; // ──────────────────╯ fee token
        uint256 feeTokenAmount; //               fee token amount
        bytes data; //                           arbitrary data payload supplied by the message sender
        Client.EVMTokenAmount[] tokenAmounts; // array of tokens and amounts to transfer
        bytes[] sourceTokenData; //              array of token data, one per token
        bytes32 messageId; //                    a hash of the message data
    }
}

interface IEVM2EVMOffRampPreV1dot6Fork {
    function executeSingleMessage(
        InternalPreV1dot6.EVM2EVMMessage memory message,
        bytes[] memory offchainTokenData,
        uint32[] memory tokenGasOverrides
    ) external;
}

/// @title CCIPLocalSimulatorFork
/// @notice Works with Foundry only
contract CCIPLocalSimulatorFork is Test {
    /**
     * @notice Events emitted when a CCIP send request is made
     */
    event CCIPSendRequested(InternalPreV1dot6.EVM2EVMMessage message);
    event CCIPMessageSent(
        uint64 indexed destChainSelector, uint64 indexed sequenceNumber, Internal.EVM2AnyRampMessage message
    );

    error InvalidExtraArgsTag();

    uint32 public constant DEFAULT_GAS_LIMIT = 200_000;

    /// @notice The immutable register instance
    Register immutable i_register;

    /// @notice The address of the LINK faucet
    address constant LINK_FAUCET = 0x4281eCF07378Ee595C564a59048801330f3084eE;

    /// @notice Mapping to track processed messages
    mapping(bytes32 messageId => bool isProcessed) internal s_processedMessages;

    /**
     * @notice Constructor to initialize the contract
     */
    constructor() {
        vm.recordLogs();
        i_register = new Register();
        vm.makePersistent(address(i_register));
    }

    /**
     * @notice  To be called after the sending of the cross-chain message (`ccipSend`).
     *          Goes through the list of past logs and looks for the `CCIPSendRequested` and `CCIPMessageSent` events.
     *          Switches to a destination network fork. Routes the sent cross-chain message on the destination network.
     *          If you sent more than one message, it will try to route all of them to `forkId`.
     *
     * @param forkId - The ID of the destination network fork. This is the returned value of `createFork()` or `createSelectFork()`
     */
    function switchChainAndRouteMessage(uint256 forkId) external {
        uint256 sourceForkId = vm.activeFork();
        address sourceRouterAddress = i_register.getNetworkDetails(block.chainid).routerAddress;

        uint256[] memory forkIds = new uint256[](1);
        forkIds[0] = forkId;

        _routeCapturedMessages(forkIds, sourceForkId, sourceRouterAddress);
    }

    /**
     * @notice  To be called after the sending of the cross-chain message (`ccipSend`).
     *          Override variant of the `switchChainAndRouteMessage(uint256 forkId)` function in case of multiple destination forks.
     *          Goes through the list of past logs and looks for the `CCIPSendRequested` and `CCIPMessageSent` events.
     *          Loops through provided `forkIds` and tries to route the message to correct destination.
     *          If you haven't provide correct `forkId`, the message will get lost.
     *          If you sent more than one message, it will try to route all of them to correct destinations.
     *
     * @param forkIds - The IDs of the destination network forks. These are the returned values of `createFork()` or `createSelectFork()`
     */
    function switchChainAndRouteMessage(uint256[] memory forkIds) external {
        uint256 sourceForkId = vm.activeFork();
        address sourceRouterAddress = i_register.getNetworkDetails(block.chainid).routerAddress;

        _routeCapturedMessages(forkIds, sourceForkId, sourceRouterAddress);
    }

    /**
     * @notice Returns the default values for currently CCIP supported networks. If network is not present or some of the values are changed, user can manually add new network details using the `setNetworkDetails` function.
     *
     * @param chainId - The blockchain network chain ID. For example 11155111 for Ethereum Sepolia. Not CCIP chain selector.
     *
     * @return networkDetails - The tuple containing:
     *          chainSelector - The unique CCIP Chain Selector.
     *          routerAddress - The address of the CCIP Router contract.
     *          linkAddress - The address of the LINK token.
     *          wrappedNativeAddress - The address of the wrapped native token that can be used for CCIP fees.
     *          ccipBnMAddress - The address of the CCIP BnM token.
     *          ccipLnMAddress - The address of the CCIP LnM token.
     */
    function getNetworkDetails(uint256 chainId) external view returns (Register.NetworkDetails memory) {
        return i_register.getNetworkDetails(chainId);
    }

    /**
     * @notice If network details are not present or some of the values are changed, user can manually add new network details using the `setNetworkDetails` function.
     *
     * @param chainId - The blockchain network chain ID. For example 11155111 for Ethereum Sepolia. Not CCIP chain selector.
     * @param networkDetails - The tuple containing:
     *          chainSelector - The unique CCIP Chain Selector.
     *          routerAddress - The address of the CCIP Router contract.
     *          linkAddress - The address of the LINK token.
     *          wrappedNativeAddress - The address of the wrapped native token that can be used for CCIP fees.
     *          ccipBnMAddress - The address of the CCIP BnM token.
     *          ccipLnMAddress - The address of the CCIP LnM token.
     */
    function setNetworkDetails(uint256 chainId, Register.NetworkDetails memory networkDetails) external {
        i_register.setNetworkDetails(chainId, networkDetails);
    }

    /**
     * @notice Requests LINK tokens from the faucet. The provided amount of tokens are transferred to provided destination address.
     *
     * @param to - The address to which LINK tokens are to be sent.
     * @param amount - The amount of LINK tokens to send.
     *
     * @return success - Returns `true` if the transfer of tokens was successful, otherwise `false`.
     */
    function requestLinkFromFaucet(address to, uint256 amount) external returns (bool success) {
        address linkAddress = i_register.getNetworkDetails(block.chainid).linkAddress;

        vm.startPrank(LINK_FAUCET);
        success = IERC20(linkAddress).transfer(to, amount);
        vm.stopPrank();
    }

    /**
     * @notice Internal function to route captured messages to their respective destination forks.
     *
     * @param forkIds - The IDs of the destination network forks. These are the returned values of `createFork()` or `createSelectFork()`, not chainIds.
     * @param sourceForkId - The ID of the source network fork. This is the returned value of `createFork()` or `createSelectFork()`, not chainId.
     * @param sourceRouterAddress - The address of the Router on the source chain.
     */
    function _routeCapturedMessages(uint256[] memory forkIds, uint256 sourceForkId, address sourceRouterAddress)
        internal
    {
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 logsLength = entries.length;

        for (uint256 i; i < logsLength; ++i) {
            // Try Routing pre v1.6 message
            if (entries[i].topics[0] == CCIPSendRequested.selector) {
                InternalPreV1dot6.EVM2EVMMessage memory message =
                    abi.decode(entries[i].data, (InternalPreV1dot6.EVM2EVMMessage));

                if (!s_processedMessages[message.messageId]) {
                    for (uint256 j; j < forkIds.length; ++j) {
                        vm.selectFork(forkIds[j]);
                        uint64 destinationChainSelector = i_register.getNetworkDetails(block.chainid).chainSelector;

                        vm.selectFork(sourceForkId);
                        address onRampContract = IRouterFork(sourceRouterAddress).getOnRamp(destinationChainSelector);

                        // Deliver message
                        if (entries[i].emitter == onRampContract) {
                            vm.selectFork(forkIds[j]);

                            IRouterFork.OffRamp[] memory offRamps =
                                IRouterFork(i_register.getNetworkDetails(block.chainid).routerAddress).getOffRamps();
                            uint256 offRampsLength = offRamps.length;

                            for (uint256 k = offRampsLength; k > 0; --k) {
                                if (offRamps[k - 1].sourceChainSelector == message.sourceChainSelector) {
                                    vm.startPrank(offRamps[k - 1].offRamp);
                                    uint256 numberOfTokens = message.tokenAmounts.length;
                                    bytes[] memory offchainTokenData = new bytes[](numberOfTokens);
                                    uint32[] memory tokenGasOverrides = new uint32[](numberOfTokens);
                                    for (uint256 l; l < numberOfTokens; ++l) {
                                        tokenGasOverrides[l] = uint32(message.gasLimit);
                                    }
                                    try IEVM2EVMOffRampPreV1dot6Fork(offRamps[k - 1].offRamp).executeSingleMessage(
                                        message, offchainTokenData, tokenGasOverrides
                                    ) {
                                        vm.stopPrank();
                                        s_processedMessages[message.messageId] = true;
                                    } catch (bytes memory err) {
                                        vm.stopPrank();
                                        // Solidity does not support yet catching custom errors, so this is the best we can do for now
                                        console2.logBytes(err);
                                    }
                                    break;
                                }
                            }
                        }
                    }
                }
            }

            // Try Routing post v1.6 message
            if (entries[i].topics[0] == CCIPMessageSent.selector) {
                Internal.EVM2AnyRampMessage memory message = abi.decode(entries[i].data, (Internal.EVM2AnyRampMessage));

                if (!s_processedMessages[message.header.messageId]) {
                    s_processedMessages[message.header.messageId] = true;

                    for (uint256 j; j < forkIds.length; ++j) {
                        vm.selectFork(forkIds[j]);
                        uint64 destinationChainSelector = i_register.getNetworkDetails(block.chainid).chainSelector;

                        vm.selectFork(sourceForkId);
                        address onRampContract = IRouterFork(sourceRouterAddress).getOnRamp(destinationChainSelector);

                        // Deliver message
                        if (entries[i].emitter == onRampContract) {
                            vm.selectFork(forkIds[j]);

                            IRouterFork.OffRamp[] memory offRamps =
                                IRouterFork(i_register.getNetworkDetails(block.chainid).routerAddress).getOffRamps();
                            uint256 offRampsLength = offRamps.length;

                            for (uint256 k = offRampsLength; k > 0; --k) {
                                if (offRamps[k - 1].sourceChainSelector == message.header.sourceChainSelector) {
                                    vm.startPrank(offRamps[k - 1].offRamp);
                                    uint256 gasLimit = _fromBytes(message.extraArgs).gasLimit;
                                    uint256 numberOfTokens = message.tokenAmounts.length;
                                    Internal.Any2EVMTokenTransfer[] memory tokenAmounts =
                                        new Internal.Any2EVMTokenTransfer[](numberOfTokens);
                                    for (uint256 l; l < numberOfTokens; ++l) {
                                        tokenAmounts[l] = Internal.Any2EVMTokenTransfer({
                                            sourcePoolAddress: abi.encodePacked(message.tokenAmounts[l].sourcePoolAddress),
                                            destTokenAddress: address(
                                                uint160(bytes20(message.tokenAmounts[l].destTokenAddress))
                                            ),
                                            destGasAmount: abi.decode(message.tokenAmounts[l].destExecData, (uint32)),
                                            extraData: message.tokenAmounts[l].extraData,
                                            amount: message.tokenAmounts[l].amount
                                        });
                                    }
                                    Internal.Any2EVMRampMessage memory any2EVMRampMessage = Internal.Any2EVMRampMessage({
                                        header: message.header,
                                        sender: abi.encodePacked(message.sender),
                                        data: message.data,
                                        receiver: address(uint160(bytes20(message.receiver))),
                                        gasLimit: gasLimit,
                                        tokenAmounts: tokenAmounts
                                    });
                                    bytes[] memory offchainTokenData = new bytes[](numberOfTokens);
                                    uint32[] memory tokenGasOverrides = new uint32[](numberOfTokens);
                                    for (uint256 l; l < numberOfTokens; ++l) {
                                        tokenGasOverrides[l] = uint32(gasLimit);
                                    }
                                    try IEVM2EVMOffRampFork(offRamps[k - 1].offRamp).executeSingleMessage(
                                        any2EVMRampMessage, offchainTokenData, tokenGasOverrides
                                    ) {
                                        vm.stopPrank();
                                    } catch (bytes memory err) {
                                        vm.stopPrank();
                                        // Solidity does not support yet catching custom errors, so this is the best we can do for now
                                        console2.logBytes(err);
                                    }
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /**
     * @notice Internal helper function to decode extraArgs bytes to GenericExtraArgsV2 struct.
     *         Supports decoding of both GenericExtraArgsV2 and EVMExtraArgsV1 structs.
     *
     * @param extraArgs - The bytes representing the extra arguments.
     *
     * @return genericExtraArgs - The decoded GenericExtraArgsV2 struct.
     */
    function _fromBytes(bytes memory extraArgs) internal pure returns (Client.GenericExtraArgsV2 memory) {
        if (extraArgs.length == 0) {
            return Client.GenericExtraArgsV2({gasLimit: DEFAULT_GAS_LIMIT, allowOutOfOrderExecution: false});
        }

        bytes4 extraArgsTag = bytes4(extraArgs);
        bytes memory gasLimit = new bytes(extraArgs.length - 4);
        for (uint256 i = 4; i < extraArgs.length; ++i) {
            gasLimit[i - 4] = extraArgs[i];
        }

        if (extraArgsTag == Client.GENERIC_EXTRA_ARGS_V2_TAG) {
            return abi.decode(gasLimit, (Client.GenericExtraArgsV2));
        } else if (extraArgsTag == Client.EVM_EXTRA_ARGS_V1_TAG) {
            return
                Client.GenericExtraArgsV2({gasLimit: abi.decode(gasLimit, (uint256)), allowOutOfOrderExecution: false});
        }

        revert InvalidExtraArgsTag();
    }
}
