// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {WETH9} from "../shared/WETH9.sol";
import {LinkToken} from "../shared/LinkToken.sol";
import {BurnMintERC677Helper} from "./BurnMintERC677Helper.sol";
import {MockCCIPRouter} from "@chainlink/contracts-ccip/src/v0.8/ccip/test/mocks/MockRouter.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";

contract CCIPLocalSimulator {
    using SafeERC20 for IERC20;

    uint64 constant CHAIN_SELECTOR = 16015286601757825753;

    WETH9 internal immutable i_wrappedNative;
    LinkToken internal immutable i_linkToken;
    BurnMintERC677Helper internal immutable i_ccipBnM;
    BurnMintERC677Helper internal immutable i_ccipLnM;
    MockCCIPRouter internal immutable i_mockRouter;

    address[] internal s_supportedTokens;

    constructor() {
        i_wrappedNative = new WETH9();
        i_linkToken = new LinkToken();
        i_ccipBnM = new BurnMintERC677Helper("CCIP-BnM", "CCIP-BnM");
        i_ccipLnM = new BurnMintERC677Helper("CCIP-LnM", "CCIP-LnM");
        i_mockRouter = new MockCCIPRouter();

        s_supportedTokens.push(address(i_ccipBnM));
        s_supportedTokens.push(address(i_ccipLnM));
    }

    /**
     * @notice Allows user to support any new token, besides CCIP BnM and CCIP LnM, for cross-chain transfers.
     *
     * @param tokenAddress - The address of the token to add to the list of supported tokens.
     */
    function supportNewToken(address tokenAddress) external {
        s_supportedTokens.push(tokenAddress);
    }

    /**
     * @notice Checks whether the provided `chainSelector` is supported by the simulator.
     *
     * @param chainSelector - The unique CCIP Chain Selector.
     *
     * @return supported - Returns true if `chainSelector` is supported by the simulator.
     */
    function isChainSupported(
        uint64 chainSelector
    ) public pure returns (bool supported) {
        supported = chainSelector == CHAIN_SELECTOR;
    }

    /**
     * @notice Gets a list of token addresses that are supported for cross-chain transfers by the simulator.
     *
     * @param chainSelector - The unique CCIP Chain Selector.
     *
     * @return tokens - Returns a list of token addresses that are supported for cross-chain transfers by the simulator.
     */
    function getSupportedTokens(
        uint64 chainSelector
    ) external view returns (address[] memory tokens) {
        if (!isChainSupported(chainSelector)) {
            return new address[](0);
        }

        tokens = s_supportedTokens;
    }

    /**
     * @notice Requests LINK tokens from the faucet. The provided amount of tokens are transferred to provided destination address.
     *
     * @param to - The address to which LINK tokens are to be sent.
     * @param amount - The amount of LINK tokens to send.
     *
     * @return success - Returns `true` if the transfer of tokens was successful, otherwise `false`.
     */
    function requestLinkFromFaucet(
        address to,
        uint256 amount
    ) external returns (bool success) {
        success = i_linkToken.transfer(to, amount);
    }

    /**
     * @notice Returns configuration details for pre-deployed contracts and services needed for local CCIP simulations.
     *
     * @return chainSelector_ - The unique CCIP Chain Selector.
     * @return sourceRouter_  - The source chain Router contract.
     * @return destinationRouter_ - The destination chain Router contract.
     * @return wrappedNative_ - The wrapped native token which can be used for CCIP fees.
     * @return linkToken_ - The LINK token.
     * @return ccipBnM_ - The ccipBnM token.
     * @return ccipLnM_ - The ccipLnM token.
     */
    function configuration()
        public
        view
        returns (
            uint64 chainSelector_,
            IRouterClient sourceRouter_,
            IRouterClient destinationRouter_,
            WETH9 wrappedNative_,
            LinkToken linkToken_,
            BurnMintERC677Helper ccipBnM_,
            BurnMintERC677Helper ccipLnM_
        )
    {
        return (
            CHAIN_SELECTOR,
            IRouterClient(address(i_mockRouter)),
            IRouterClient(address(i_mockRouter)),
            i_wrappedNative,
            i_linkToken,
            i_ccipBnM,
            i_ccipLnM
        );
    }
}
