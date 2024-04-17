// // SPDX-License-Identifier: BUSL-1.1
// pragma solidity ^0.8.19;

// import {WETH9} from "../shared/WETH9.sol";
// import {LinkToken} from "../shared/LinkToken.sol";
// import {BurnMintERC677Helper} from "./BurnMintERC677Helper.sol";
// import {Router} from "@chainlink/contracts-ccip/src/v0.8/ccip/Router.sol";
// import {ARMProxy} from "@chainlink/contracts-ccip/src/v0.8/ccip/ARMProxy.sol";
// import {ARM} from "@chainlink/contracts-ccip/src/v0.8/ccip/ARM.sol";
// import {EVM2EVMOnRamp, Internal, RateLimiter} from "@chainlink/contracts-ccip/src/v0.8/ccip/onRamp/EVM2EVMOnRamp.sol";
// import {PriceRegistry} from "@chainlink/contracts-ccip/src/v0.8/ccip/PriceRegistry.sol";
// import {BurnMintTokenPool} from "@chainlink/contracts-ccip/src/v0.8/ccip/pools/BurnMintTokenPool.sol";
// import {LockReleaseTokenPool} from "@chainlink/contracts-ccip/src/v0.8/ccip/pools/LockReleaseTokenPool.sol";
// import {TokenPool} from "@chainlink/contracts-ccip/src/v0.8/ccip/pools/TokenPool.sol";
// import {IBurnMintERC20} from "@chainlink/contracts-ccip/src/v0.8/shared/token/ERC20/IBurnMintERC20.sol";
// import {MockEvm2EvmOffRamp} from "./MockEvm2EvmOffRamp.sol";
// import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
// import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
// import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
// import {SafeERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
// import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
// import {CallWithExactGas} from "@chainlink/contracts-ccip/src/v0.8/shared/call/CallWithExactGas.sol";

// contract CCIPLocalSimulatorV0 {
//     using SafeERC20 for IERC20;

//     WETH9 immutable wrappedNative;
//     LinkToken immutable linkToken;
//     Router immutable router;
//     ARMProxy immutable armProxy;
//     ARM immutable arm;
//     EVM2EVMOnRamp immutable evm2EvmOnRamp;
//     PriceRegistry immutable priceRegistry;
//     BurnMintTokenPool immutable ccipBnMTokenPool;
//     LockReleaseTokenPool immutable ccipLnMTokenPool;
//     BurnMintERC677Helper immutable ccipBnM;
//     BurnMintERC677Helper immutable ccipLnM;
//     MockEvm2EvmOffRamp immutable mockEvm2EvmOffRamp;

//     uint64 constant CHAIN_SELECTOR = 777000000000000000;

//     error CCIPLocalSimulator_InvalidExtraArgsTag();
//     error CCIPLocalSimulator_InvalidAddress(bytes);
//     error CCIPLocalSimulator__OnlyOffRamp();

//     event MessageExecuted(
//         bytes32 messageId,
//         uint64 sourceChainSelector,
//         address offRamp,
//         bytes32 calldataHash
//     );

//     constructor() {
//         wrappedNative = new WETH9();
//         linkToken = new LinkToken();
//         ARM.Voter[] memory voters = new ARM.Voter[](1);
//         voters[0] = ARM.Voter(
//             address(this), // blessVoteAddr
//             address(7), // curseVoteAddr
//             address(777), // curseUnvoteAddr
//             1, // blessWeight
//             1 // curseWeight
//         );

//         arm = new ARM(
//             ARM.Config(
//                 voters,
//                 1, // blessWeightThreshold
//                 1 //curseWeightThreshold
//             )
//         );
//         armProxy = new ARMProxy(address(arm));

//         router = new Router(address(wrappedNative), address(armProxy));

//         address[] memory priceUpdaters = new address[](1);
//         priceUpdaters[0] = address(this);
//         address[] memory feeTokens = new address[](2);
//         feeTokens[0] = address(linkToken);
//         feeTokens[1] = address(wrappedNative);

//         priceRegistry = new PriceRegistry(
//             priceUpdaters,
//             feeTokens,
//             3600 // stalenessThreshold
//         );

//         EVM2EVMOnRamp.StaticConfig memory staticConfig = EVM2EVMOnRamp
//             .StaticConfig(
//                 address(linkToken),
//                 CHAIN_SELECTOR, // chainSelector
//                 CHAIN_SELECTOR, // destChainSelector
//                 200000, // defaultTxGasLimit
//                 100000000000000000000000000, // maxNopFeesJuels
//                 address(0), // prevOnRamp
//                 address(armProxy)
//             );

//         EVM2EVMOnRamp.DynamicConfig memory dynamicConfig = EVM2EVMOnRamp
//             .DynamicConfig(
//                 address(router), // router
//                 1, // maxNumberOfTokensPerMsg
//                 350000, // destGasOverhead
//                 16, // destGasPerPayloadByte
//                 33596, // destDataAvailabilityOverheadGas
//                 16, // destGasPerDataAvailabilityByte
//                 6840, // destDataAvailabilityMultiplierBps
//                 address(priceRegistry),
//                 30000, // maxDataBytes
//                 3000000 // maxPerMsgGasLimit
//             );

//         ccipBnM = new BurnMintERC677Helper("CCIP-BnM", "CCIP-BnM");
//         ccipLnM = new BurnMintERC677Helper("CCIP-LnM", "CCIP-LnM");

//         address[] memory allowlist = new address[](1);
//         allowlist[0] = address(this);

//         ccipBnMTokenPool = new BurnMintTokenPool(
//             IBurnMintERC20(address(ccipBnM)),
//             allowlist,
//             address(armProxy)
//         );
//         ccipBnM.grantMintAndBurnRoles(address(ccipBnMTokenPool));

//         ccipLnMTokenPool = new LockReleaseTokenPool(
//             IBurnMintERC20(address(ccipLnM)),
//             allowlist,
//             address(armProxy),
//             false // acceptLiquidity
//         );
//         ccipLnM.grantMintAndBurnRoles(address(ccipLnMTokenPool));

//         Internal.PoolUpdate[] memory tokensAndPools = new Internal.PoolUpdate[](
//             2
//         );
//         tokensAndPools[0] = Internal.PoolUpdate(
//             address(ccipBnM),
//             address(ccipBnMTokenPool)
//         );
//         tokensAndPools[1] = Internal.PoolUpdate(
//             address(ccipLnM),
//             address(ccipLnMTokenPool)
//         );
//         RateLimiter.Config memory rateLimiterConfig = RateLimiter.Config(
//             false, // isEnabled
//             0, // capacity
//             0 // rate
//         );
//         EVM2EVMOnRamp.FeeTokenConfigArgs[]
//             memory feeTokenConfigs = new EVM2EVMOnRamp.FeeTokenConfigArgs[](3);
//         feeTokenConfigs[0] = EVM2EVMOnRamp.FeeTokenConfigArgs(
//             address(linkToken), // token
//             0, // networkFeeUSDCents
//             0, // gasMultiplierWeiPerEth
//             0, // premiumMultiplierWeiPerEth
//             true // enabled
//         );
//         feeTokenConfigs[1] = EVM2EVMOnRamp.FeeTokenConfigArgs(
//             address(wrappedNative), // token
//             0, // networkFeeUSDCents
//             0, // gasMultiplierWeiPerEth
//             0, // premiumMultiplierWeiPerEth
//             true // enabled
//         );
//         feeTokenConfigs[2] = EVM2EVMOnRamp.FeeTokenConfigArgs(
//             address(0), // token
//             0, // networkFeeUSDCents
//             0, // gasMultiplierWeiPerEth
//             0, // premiumMultiplierWeiPerEth
//             true // enabled
//         );

//         EVM2EVMOnRamp.TokenTransferFeeConfigArgs[]
//             memory tokenTransferFeeConfigArgs = new EVM2EVMOnRamp.TokenTransferFeeConfigArgs[](
//                 2
//             );
//         tokenTransferFeeConfigArgs[0] = EVM2EVMOnRamp
//             .TokenTransferFeeConfigArgs(
//                 address(ccipBnM), // token
//                 0, // minFeeUSDCents
//                 0, // maxFeeUSDCents
//                 0, // deciBps
//                 0, // destGasOverhead
//                 0 // destBytesOverhead
//             );
//         tokenTransferFeeConfigArgs[1] = EVM2EVMOnRamp
//             .TokenTransferFeeConfigArgs(
//                 address(ccipLnM), // token
//                 0, // minFeeUSDCents
//                 0, // maxFeeUSDCents
//                 0, // deciBps
//                 0, // destGasOverhead
//                 0 // destBytesOverhead
//             );

//         EVM2EVMOnRamp.NopAndWeight[]
//             memory nopsAndWeights = new EVM2EVMOnRamp.NopAndWeight[](1);
//         nopsAndWeights[0] = EVM2EVMOnRamp.NopAndWeight(
//             address(this), // nop
//             0 // weight
//         );

//         evm2EvmOnRamp = new EVM2EVMOnRamp(
//             staticConfig,
//             dynamicConfig,
//             tokensAndPools,
//             rateLimiterConfig,
//             feeTokenConfigs,
//             tokenTransferFeeConfigArgs,
//             nopsAndWeights
//         );

//         address[] memory sourceTokens = new address[](2);
//         sourceTokens[0] = address(ccipBnM);
//         sourceTokens[1] = address(ccipLnM);

//         address[] memory pools = new address[](2);
//         pools[0] = address(ccipBnMTokenPool);
//         pools[1] = address(ccipLnMTokenPool);

//         mockEvm2EvmOffRamp = new MockEvm2EvmOffRamp(
//             address(this), // ccipLocalSimulator
//             MockEvm2EvmOffRamp.DynamicConfig(
//                 604800, // permissionLessExecutionThresholdSeconds (1 week)
//                 address(this), // router
//                 address(priceRegistry), // priceRegistry
//                 1, // maxNumberOfTokensPerMsg
//                 30000, // maxDataBytes
//                 3000000 // maxPoolReleaseOrMintGas
//             ),
//             rateLimiterConfig, // rateLimiterConfig
//             CHAIN_SELECTOR, // sourceChainSelector,
//             sourceTokens, // sourceTokens
//             pools // pools
//         );

//         Router.OnRamp[] memory onRampUpdates = new Router.OnRamp[](1);
//         onRampUpdates[0] = Router.OnRamp(
//             CHAIN_SELECTOR,
//             address(evm2EvmOnRamp)
//         );

//         Router.OffRamp[] memory offRampAdds = new Router.OffRamp[](1);
//         offRampAdds[0] = Router.OffRamp(
//             CHAIN_SELECTOR,
//             address(mockEvm2EvmOffRamp)
//         );

//         router.applyRampUpdates(
//             onRampUpdates,
//             new Router.OffRamp[](0), // offRampRemoves
//             offRampAdds
//         );

//         Internal.TokenPriceUpdate[]
//             memory tokenPriceUpdates = new Internal.TokenPriceUpdate[](5);
//         tokenPriceUpdates[0] = Internal.TokenPriceUpdate(
//             address(wrappedNative), // sourceToken
//             1 // usdPerToken
//         );
//         tokenPriceUpdates[1] = Internal.TokenPriceUpdate(address(0), 1);
//         tokenPriceUpdates[2] = Internal.TokenPriceUpdate(address(linkToken), 1);
//         tokenPriceUpdates[3] = Internal.TokenPriceUpdate(address(ccipBnM), 1);
//         tokenPriceUpdates[4] = Internal.TokenPriceUpdate(address(ccipBnM), 1);
//         Internal.GasPriceUpdate[]
//             memory gasPriceUpdates = new Internal.GasPriceUpdate[](1);
//         gasPriceUpdates[0] = Internal.GasPriceUpdate(CHAIN_SELECTOR, 0);
//         priceRegistry.updatePrices(
//             Internal.PriceUpdates(tokenPriceUpdates, gasPriceUpdates)
//         );

//         TokenPool.RampUpdate[] memory onRamps = new TokenPool.RampUpdate[](1);
//         onRamps[0] = TokenPool.RampUpdate(
//             address(evm2EvmOnRamp), // ramp
//             true, // allowed
//             rateLimiterConfig // rateLimiterConfig
//         );
//         TokenPool.RampUpdate[] memory offRamps = new TokenPool.RampUpdate[](1);
//         offRamps[0] = TokenPool.RampUpdate(
//             address(mockEvm2EvmOffRamp), // ramp
//             true, // allowed
//             rateLimiterConfig // rateLimiterConfig
//         );

//         ccipBnMTokenPool.applyRampUpdates(onRamps, offRamps);
//         ccipLnMTokenPool.applyRampUpdates(onRamps, offRamps);
//     }

//     function ccipSend(
//         uint64 destinationChainSelector,
//         Client.EVM2AnyMessage calldata message
//     ) external returns (bytes32 messageId) {
//         for (uint256 i = 0; i < message.tokenAmounts.length; ++i) {
//             IERC20 token = IERC20(message.tokenAmounts[i].token);
//             uint256 amount = message.tokenAmounts[i].amount;
//             token.safeTransferFrom(msg.sender, address(this), amount);
//             token.approve(address(router), amount);
//         }

//         messageId = IRouterClient(router).ccipSend(
//             destinationChainSelector,
//             message
//         );

//         if (message.receiver.length != 32) {
//             revert CCIPLocalSimulator_InvalidAddress(message.receiver);
//         }
//         uint256 decodedReceiver = abi.decode(message.receiver, (uint256));
//         if (decodedReceiver > type(uint160).max || decodedReceiver < 10) {
//             revert CCIPLocalSimulator_InvalidAddress(message.receiver);
//         }

//         bytes[] memory sourceTokenData;
//         uint256 numberOfTokens = message.tokenAmounts.length;
//         if (numberOfTokens > 0) {
//             sourceTokenData = new bytes[](numberOfTokens);
//             for (uint256 i = 0; i < numberOfTokens; ++i) {
//                 sourceTokenData[i] = "";
//             }
//         }

//         Internal.EVM2EVMMessage memory evm2EvmMessage = Internal.EVM2EVMMessage(
//                 CHAIN_SELECTOR, // sourceChainSelector
//                 msg.sender, //sender
//                 address(uint160(decodedReceiver)), // receiver
//                 evm2EvmOnRamp.getExpectedNextSequenceNumber(), //sequenceNumber
//                 _fromBytes(message.extraArgs).gasLimit, // gasLimit
//                 false, // strict; DEPRECATED
//                 evm2EvmOnRamp.getSenderNonce(msg.sender), // nonce
//                 message.feeToken == address(0)
//                     ? address(wrappedNative)
//                     : address(linkToken), // feeToken
//                 evm2EvmOnRamp.getFee(destinationChainSelector, message), // feeTokenAmount
//                 message.data, // arbitrary data payload supplied by the message sender
//                 message.tokenAmounts, //  array of tokens and amounts to transfer
//                 sourceTokenData, // sourceTokenData
//                 messageId
//             );
//         bytes[] memory offchainTokenData = new bytes[](numberOfTokens);

//         mockEvm2EvmOffRamp.executeSingleMessage(
//             evm2EvmMessage,
//             offchainTokenData
//         );
//     }

//     function isChainSupported(
//         uint64 chainSelector
//     ) external view returns (bool supported) {
//         supported = router.isChainSupported(chainSelector);
//     }

//     function getSupportedTokens(
//         uint64 chainSelector
//     ) external view returns (address[] memory tokens) {
//         tokens = router.getSupportedTokens(chainSelector);
//     }

//     function getFee(
//         uint64 destinationChainSelector,
//         Client.EVM2AnyMessage memory message
//     ) external view returns (uint256 fee) {
//         fee = router.getFee(destinationChainSelector, message);
//     }

//     function routeMessage(
//         Client.Any2EVMMessage calldata message,
//         uint16 gasForCallExactCheck,
//         uint256 gasLimit,
//         address receiver
//     ) external returns (bool success, bytes memory retData, uint256 gasUsed) {
//         if (msg.sender != address(mockEvm2EvmOffRamp))
//             revert CCIPLocalSimulator__OnlyOffRamp();

//         // We encode here instead of the offRamps to constrain specifically what functions
//         // can be called from the router.
//         bytes memory data = abi.encodeWithSelector(
//             IAny2EVMMessageReceiver.ccipReceive.selector,
//             message
//         );

//         (success, retData, gasUsed) = CallWithExactGas
//             ._callWithExactGasSafeReturnData(
//                 data,
//                 receiver,
//                 gasLimit,
//                 gasForCallExactCheck,
//                 Internal.MAX_RET_BYTES
//             );

//         emit MessageExecuted(
//             message.messageId,
//             message.sourceChainSelector,
//             msg.sender,
//             keccak256(data)
//         );
//         return (success, retData, gasUsed);
//     }

//     function configuration()
//         public
//         view
//         returns (
//             uint64 chainSelector_,
//             Router sourceRouter_,
//             Router destinationRouter_,
//             WETH9 wrappedNative_,
//             LinkToken linkToken_,
//             BurnMintERC677Helper ccipBnM_,
//             BurnMintERC677Helper ccipLnM_
//         )
//     {
//         return (
//             CHAIN_SELECTOR,
//             Router(address(this)),
//             Router(address(this)),
//             wrappedNative,
//             linkToken,
//             ccipBnM,
//             ccipLnM
//         );
//     }

//     function requestLinkFromFaucet(
//         address to,
//         uint256 amount
//     ) external returns (bool success) {
//         success = linkToken.transfer(to, amount);
//     }

//     /// @dev Convert the extra args bytes into a struct
//     /// @param extraArgs The extra args bytes
//     /// @return The extra args struct
//     function _fromBytes(
//         bytes calldata extraArgs
//     ) internal pure returns (Client.EVMExtraArgsV1 memory) {
//         if (extraArgs.length == 0) {
//             // 200000 = defaultTxGasLimit
//             return Client.EVMExtraArgsV1({gasLimit: 200000});
//         }
//         if (bytes4(extraArgs) != Client.EVM_EXTRA_ARGS_V1_TAG) {
//             revert CCIPLocalSimulator_InvalidExtraArgsTag();
//         }
//         // EVMExtraArgsV1 originally included a second boolean (strict) field which we have deprecated entirely.
//         // Clients may still send that version but it will be ignored.
//         return abi.decode(extraArgs[4:], (Client.EVMExtraArgsV1));
//     }
// }
