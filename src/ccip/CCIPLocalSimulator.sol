// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {WETH9} from "../shared/WETH9.sol";
import {LinkToken} from "../shared/LinkToken.sol";
import {BurnMintERC677Helper} from "./BurnMintERC677Helper.sol";
import {MockCCIPRouter} from "@chainlink/contracts-ccip/src/v0.8/ccip/test/mocks/MockRouter.sol";
import {Router} from "@chainlink/contracts-ccip/src/v0.8/ccip/Router.sol";
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

    function supportNewToken(address tokenAddress) external {
        s_supportedTokens.push(tokenAddress);
    }

    function isChainSupported(
        uint64 chainSelector
    ) public pure returns (bool supported) {
        supported = chainSelector == CHAIN_SELECTOR;
    }

    function getSupportedTokens(
        uint64 chainSelector
    ) external view returns (address[] memory tokens) {
        if (!isChainSupported(chainSelector)) {
            return new address[](0);
        }

        tokens = s_supportedTokens;
    }

    function requestLinkFromFaucet(
        address to,
        uint256 amount
    ) external returns (bool success) {
        success = i_linkToken.transfer(to, amount);
    }

    function DOCUMENTATION()
        public
        view
        returns (
            uint64 chainSelector_,
            Router sourceRouter_,
            Router destinationRouter_,
            WETH9 wrappedNative_,
            LinkToken linkToken_,
            BurnMintERC677Helper ccipBnM_,
            BurnMintERC677Helper ccipLnM_
        )
    {
        return (
            CHAIN_SELECTOR,
            Router(address(i_mockRouter)),
            Router(address(i_mockRouter)),
            i_wrappedNative,
            i_linkToken,
            i_ccipBnM,
            i_ccipLnM
        );
    }
}
