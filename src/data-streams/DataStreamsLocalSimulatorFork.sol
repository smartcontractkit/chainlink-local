// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, Vm} from "forge-std/Test.sol";
import {Register} from "./Register.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/interfaces/IERC20.sol";

contract DataStreamsLocalSimulatorFork is Test {
    /// @notice The immutable register instance
    Register immutable i_register;

    /// @notice The address of the LINK faucet
    address constant LINK_FAUCET = 0x4281eCF07378Ee595C564a59048801330f3084eE;

    /**
     * @notice Constructor to initialize the contract
     */
    constructor() {
        i_register = new Register();
    }

    /**
     * @notice Returns the default values for currently Data Streams supported networks. If network is not present or some of the values are changed, user can manually add new network details using the `setNetworkDetails` function.
     *
     * @param chainId - The blockchain network chain ID. For example 11155111 for Ethereum Sepolia.
     *
     * @return networkDetails - The tuple containing:
     *          verifierProxyAddress - The address of the Verifier Proxy smart contract.
     *          linkAddress - The address of the LINK token.
     */
    function getNetworkDetails(uint256 chainId) external view returns (Register.NetworkDetails memory) {
        return i_register.getNetworkDetails(chainId);
    }

    /**
     * @notice If network details are not present or some of the values are changed, user can manually add new network details using the `setNetworkDetails` function.
     *
     * @param chainId - The blockchain network chain ID. For example 11155111 for Ethereum Sepolia.
     * @param networkDetails - The tuple containing:
     *          verifierProxyAddress - The address of the Verifier Proxy smart contract.
     *          linkAddress - The address of the LINK token.
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
     * @notice Requests native coints from the faucet.
     *
     * @param to - The address to which native coins are to be sent.
     * @param amount - The amount of native coins to send.
     */
    function requestNativeFromFaucet(address to, uint256 amount) external {
        vm.deal(to, amount);
    }
}
