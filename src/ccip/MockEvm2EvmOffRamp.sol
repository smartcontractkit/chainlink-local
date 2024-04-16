// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {Internal} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Internal.sol";
import {IRouter} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouter.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {IPool} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/pools/IPool.sol";
import {IPriceRegistry} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IPriceRegistry.sol";
import {CallWithExactGas} from "@chainlink/contracts-ccip/src/v0.8/shared/call/CallWithExactGas.sol";
import {EnumerableMapAddresses} from "@chainlink/contracts-ccip/src/v0.8/shared/enumerable/EnumerableMapAddresses.sol";
import {RateLimiter} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/RateLimiter.sol";
import {USDPriceWith18Decimals} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/USDPriceWith18Decimals.sol";
import {AggregateRateLimiter} from "@chainlink/contracts-ccip/src/v0.8/ccip/AggregateRateLimiter.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {Address} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/utils/Address.sol";
import {ERC165Checker} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/utils/introspection/ERC165Checker.sol";

contract MockEvm2EvmOffRamp is AggregateRateLimiter {
    using EnumerableMapAddresses for EnumerableMapAddresses.AddressToAddressMap;
    using USDPriceWith18Decimals for uint224;
    using Address for address;
    using ERC165Checker for address;

    struct DynamicConfig {
        uint32 permissionLessExecutionThresholdSeconds; // ─╮ Waiting time before manual execution is enabled
        address router; // ─────────────────────────────────╯ Router address
        address priceRegistry; // ──────────╮ Price registry address
        uint16 maxNumberOfTokensPerMsg; //  │ Maximum number of ERC20 token transfers that can be included per message
        uint32 maxDataBytes; //             │ Maximum payload data size in bytes
        uint32 maxPoolReleaseOrMintGas; // ─╯ Maximum amount of gas passed on to token pool when calling releaseOrMint
    }

    uint64 internal immutable i_sourceChainSelector;

    address internal s_ccipLocalSimulator;
    DynamicConfig internal s_dynamicConfig;

    /// @dev source token => token pool
    EnumerableMapAddresses.AddressToAddressMap private s_poolsBySourceToken;

    error CanOnlySimulatorCall();
    error ReceiverError(bytes error);
    error TokenHandlingError(bytes error);
    error UnsupportedToken(IERC20 token);

    constructor(
        address ccipLocalSimulator,
        DynamicConfig memory dynamicConfig,
        RateLimiter.Config memory config,
        uint64 sourceChainSelector,
        address[] memory sourceTokens,
        address[] memory pools
    ) AggregateRateLimiter(config) {
        s_ccipLocalSimulator = ccipLocalSimulator;
        s_dynamicConfig = dynamicConfig;
        i_sourceChainSelector = sourceChainSelector;

        for (uint256 i = 0; i < sourceTokens.length; ++i) {
            s_poolsBySourceToken.set(
                address(sourceTokens[i]),
                address(pools[i])
            );
            // s_poolsByDestToken.set(address(pools[i].getToken()), address(pools[i]));
            // emit PoolAdded(address(sourceTokens[i]), address(pools[i]));
        }
    }

    function executeSingleMessage(
        Internal.EVM2EVMMessage memory message,
        bytes[] memory offchainTokenData
    ) external {
        if (msg.sender != s_ccipLocalSimulator) revert CanOnlySimulatorCall();

        Client.EVMTokenAmount[]
            memory destTokenAmounts = new Client.EVMTokenAmount[](0);
        if (message.tokenAmounts.length > 0) {
            destTokenAmounts = _releaseOrMintTokens(
                message.tokenAmounts,
                abi.encode(message.sender),
                message.receiver,
                message.sourceTokenData,
                offchainTokenData
            );
        }
        if (
            !message.receiver.isContract() ||
            !message.receiver.supportsInterface(
                type(IAny2EVMMessageReceiver).interfaceId
            )
        ) return;

        (bool success, bytes memory returnData, ) = IRouter(
            s_dynamicConfig.router
        ).routeMessage(
                Internal._toAny2EVMMessage(message, destTokenAmounts),
                Internal.GAS_FOR_CALL_EXACT_CHECK,
                message.gasLimit,
                message.receiver
            );
        // If CCIP receiver execution is not successful, revert the call including token transfers
        if (!success) revert ReceiverError(returnData);
    }

    /// @notice Uses pools to release or mint a number of different tokens to a receiver address.
    /// @param sourceTokenAmounts List of tokens and amount values to be released/minted.
    /// @param originalSender The message sender.
    /// @param receiver The address that will receive the tokens.
    /// @param sourceTokenData Array of token data returned by token pools on the source chain.
    /// @param offchainTokenData Array of token data fetched offchain by the DON.
    /// @dev This function wrappes the token pool call in a try catch block to gracefully handle
    /// any non-rate limiting errors that may occur. If we encounter a rate limiting related error
    /// we bubble it up. If we encounter a non-rate limiting error we wrap it in a TokenHandlingError.
    function _releaseOrMintTokens(
        Client.EVMTokenAmount[] memory sourceTokenAmounts,
        bytes memory originalSender,
        address receiver,
        bytes[] memory sourceTokenData,
        bytes[] memory offchainTokenData
    ) internal returns (Client.EVMTokenAmount[] memory) {
        Client.EVMTokenAmount[]
            memory destTokenAmounts = new Client.EVMTokenAmount[](
                sourceTokenAmounts.length
            );
        for (uint256 i = 0; i < sourceTokenAmounts.length; ++i) {
            IPool pool = getPoolBySourceToken(
                IERC20(sourceTokenAmounts[i].token)
            );
            uint256 sourceTokenAmount = sourceTokenAmounts[i].amount;

            // Call the pool with exact gas to increase resistance against malicious tokens or token pools.
            // _callWithExactGas also protects against return data bombs by capping the return data size
            // at MAX_RET_BYTES.
            (bool success, bytes memory returnData, ) = CallWithExactGas
                ._callWithExactGasSafeReturnData(
                    abi.encodeWithSelector(
                        pool.releaseOrMint.selector,
                        originalSender,
                        receiver,
                        sourceTokenAmount,
                        i_sourceChainSelector,
                        abi.encode(sourceTokenData[i], offchainTokenData[i])
                    ),
                    address(pool),
                    s_dynamicConfig.maxPoolReleaseOrMintGas,
                    Internal.GAS_FOR_CALL_EXACT_CHECK,
                    Internal.MAX_RET_BYTES
                );

            // wrap and rethrow the error so we can catch it lower in the stack
            if (!success) revert TokenHandlingError(returnData);

            destTokenAmounts[i].token = address(pool.getToken());
            destTokenAmounts[i].amount = sourceTokenAmount;
        }
        _rateLimitValue(
            destTokenAmounts,
            IPriceRegistry(s_dynamicConfig.priceRegistry)
        );
        return destTokenAmounts;
    }

    /// @notice Get a token pool by its source token
    /// @param sourceToken token
    /// @return Token Pool
    function getPoolBySourceToken(
        IERC20 sourceToken
    ) public view returns (IPool) {
        (bool success, address pool) = s_poolsBySourceToken.tryGet(
            address(sourceToken)
        );
        if (!success) revert UnsupportedToken(sourceToken);
        return IPool(pool);
    }
}
