// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {WETH9} from "../shared/WETH9.sol";
import {LinkToken} from "../shared/LinkToken.sol";
import {MockVerifier} from "./MockVerifier.sol";
import {MockVerifierProxy} from "./MockVerifierProxy.sol";
import {MockFeeManager} from "./MockFeeManager.sol";
import {MockRewardManager} from "./MockRewardManager.sol";

contract DataStreamsLocalSimulator {
    MockVerifier internal s_mockVerifier;
    MockVerifierProxy internal s_mockVerifierProxy;
    MockFeeManager internal s_mockFeeManager;
    MockRewardManager internal s_mockRewardManager;

    /// @notice The wrapped native token instance
    WETH9 internal immutable i_wrappedNative;

    /// @notice The LINK token instance
    LinkToken internal immutable i_linkToken;

    /// @notice Whether fee manager is enabled (can be toggled after deployment)
    bool public feeManagerEnabled;

    constructor() {
        // Default to on-chain billing for backward compatibility
        feeManagerEnabled = true;
        
        i_wrappedNative = new WETH9();
        i_linkToken = new LinkToken();

        s_mockVerifierProxy = new MockVerifierProxy();
        s_mockVerifier = new MockVerifier(address(s_mockVerifierProxy));
        s_mockVerifierProxy.initializeVerifier(address(s_mockVerifier));

        // Deploy fee manager by default (existing behavior)
        _deployFeeManager();
    }

    /**
     * @notice Enables off-chain billing mechanism by removing fee manager
     * @dev This simulates chains that don't have FeeManager contracts deployed
     */
    function enableOffChainBilling() external {
        if (feeManagerEnabled) {
            feeManagerEnabled = false;
            s_mockVerifierProxy.setFeeManager(MockFeeManager(address(0)));
        }
    }

    /**
     * @notice Enables on-chain billing mechanism by deploying/setting fee manager
     * @dev This simulates chains that have FeeManager contracts deployed
     */
    function enableOnChainBilling() external {
        if (!feeManagerEnabled) {
            feeManagerEnabled = true;
            if (address(s_mockFeeManager) == address(0)) {
                _deployFeeManager();
            }
            s_mockVerifierProxy.setFeeManager(s_mockFeeManager);
        }
    }

    /**
     * @notice Returns the current billing mechanism type
     * @return billingType "on-chain" if fee manager is enabled, "off-chain" if disabled
     */
    function getBillingMechanism() external view returns (string memory billingType) {
        return feeManagerEnabled ? "on-chain" : "off-chain";
    }

    /**
     * @notice Internal function to deploy fee manager and reward manager
     */
    function _deployFeeManager() private {
        s_mockRewardManager = new MockRewardManager(address(i_linkToken));

        s_mockFeeManager = new MockFeeManager(
            address(i_linkToken), address(i_wrappedNative), address(s_mockVerifierProxy), address(s_mockRewardManager)
        );

        s_mockVerifierProxy.setFeeManager(s_mockFeeManager);
        s_mockRewardManager.setFeeManager(address(s_mockFeeManager));
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
        success = i_linkToken.transfer(to, amount);
    }

    /**
     *  @notice Returns configuration details for pre-deployed contracts and services needed for local Data Streams simulations.
     *
     * @return wrappedNative_ - The wrapped native token.
     * @return linkToken_ - The LINK token.
     * @return mockVerifier_ - The mock verifier contract.
     * @return mockVerifierProxy_ - The mock verifier proxy contract.
     * @return mockFeeManager_ - The mock fee manager contract (returns what's currently set on verifier proxy).
     * @return mockRewardManager_ - The mock reward manager contract (address(0) if fee manager is disabled).
     */
    function configuration()
        public
        view
        returns (
            WETH9 wrappedNative_,
            LinkToken linkToken_,
            MockVerifier mockVerifier_,
            MockVerifierProxy mockVerifierProxy_,
            MockFeeManager mockFeeManager_,
            MockRewardManager mockRewardManager_
        )
    {
        // Return the current fee manager from verifier proxy (reflects current billing state)
        MockFeeManager currentFeeManager = MockFeeManager(address(s_mockVerifierProxy.s_feeManager()));
        
        return
            (i_wrappedNative, i_linkToken, s_mockVerifier, s_mockVerifierProxy, currentFeeManager, 
             feeManagerEnabled ? s_mockRewardManager : MockRewardManager(address(0)));
    }
}
