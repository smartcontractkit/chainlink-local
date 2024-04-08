// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Test, Vm} from "forge-std/Test.sol";
import {Register} from "./Register.sol";
import {Internal, Router} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {EVM2EVMOffRamp} from "@chainlink/contracts-ccip/src/v0.8/ccip/offRamp/EVM2EVMOffRamp.sol";

// @notice Works with Foundry only
contract CCIPLocalSimulatorFork is Test {
    event CCIPSendRequested(Internal.EVM2EVMMessage message);

    Register immutable i_register;

    constructor() {
        vm.recordLogs();
        i_register = new Register();
        vm.makePersistent(address(i_register));
    }

    function switchChainAndRouteMessage(uint256 forkId) external {
        Internal.EVM2EVMMessage memory message;
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 length = entries.length;
        for (uint256 i; i < length; ++i) {
            if (entries[i].topics[0] == CCIPSendRequested.selector) {
                message = abi.decode(entries[i].data, (Internal.EVM2EVMMessage));
                break;
            }
        }

        vm.selectFork(forkId);
        assertEq(vm.activeFork(), forkId);

        Router.OffRamp[] memory offRamps =
            Router(i_register.getNetworkDetails(block.chainid).routerAddress).getOffRamps();
        length = offRamps.length;

        for (uint256 i; i < length; ++i) {
            if (offRamps[i].sourceChainSelector == message.sourceChainSelector) {
                vm.startPrank(offRamps[i].offRamp);
                uint256 numberOfTokens = message.tokenAmounts.length;
                bytes[] memory offchainTokenData = new bytes[](numberOfTokens);
                EVM2EVMOffRamp(offRamps[i].offRamp).executeSingleMessage(message, offchainTokenData);
                vm.stopPrank();
                break;
            }
        }
    }

    function getNetworkDetails(uint256 chainId) external view returns (Register.NetworkDetails memory) {
        return i_register.getNetworkDetails(chainId);
    }

    function setNetworkDetails(uint256 chainId, Register.NetworkDetails memory networkDetails) external {
        i_register.setNetworkDetails(chainId, networkDetails);
    }
}
