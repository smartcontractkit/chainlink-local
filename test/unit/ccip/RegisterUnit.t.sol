// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Register} from "../../../src/ccip/Register.sol";
import {CCIPLocalSimulatorFork} from "../../../src/ccip/CCIPLocalSimulatorFork.sol";

/// @dev Register's built-in network details are generated into code; `setNetworkDetails` overrides are stored.
contract RegisterUnitTest is Test {
    uint256 internal constant SEPOLIA = 11155111;

    function _details(uint64 chainSelector) internal pure returns (Register.NetworkDetails memory details) {
        details.chainSelector = chainSelector;
        details.routerAddress = address(0xBEEF);
    }

    function test_builtInDetails() public {
        Register register = new Register();
        Register.NetworkDetails memory sepolia = register.getNetworkDetails(SEPOLIA);
        assertEq(sepolia.chainSelector, 16015286601757825753);
        assertEq(sepolia.routerAddress, 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59);
        assertEq(sepolia.linkAddress, 0x779877A7B0D9E8603169DdbD7836e478b4624789);
    }

    function test_unknownChain_returnsZeroDetails() public {
        Register register = new Register();
        Register.NetworkDetails memory unknown = register.getNetworkDetails(424242424242);
        assertEq(unknown.chainSelector, 0);
        assertEq(unknown.routerAddress, address(0));
    }

    function test_setNetworkDetails_overridesBuiltInAndUnknownChains() public {
        Register register = new Register();
        register.setNetworkDetails(SEPOLIA, _details(7));
        register.setNetworkDetails(424242424242, _details(8));
        assertEq(register.getNetworkDetails(SEPOLIA).chainSelector, 7);
        assertEq(register.getNetworkDetails(SEPOLIA).routerAddress, address(0xBEEF));
        assertEq(register.getNetworkDetails(424242424242).chainSelector, 8);
        // Other chains keep their built-in details.
        assertEq(register.getNetworkDetails(1).chainSelector, 5009297550715157269);
    }

    /// @dev An explicit override to an all-zero struct is honoured (it is not mistaken for "not overridden").
    function test_setNetworkDetails_toZeroDetails() public {
        Register register = new Register();
        Register.NetworkDetails memory zero;
        register.setNetworkDetails(SEPOLIA, zero);
        assertEq(register.getNetworkDetails(SEPOLIA).chainSelector, 0);
    }

    /// @dev Each simulator gets its own Register (placed with vm.etch), so overrides do not leak between simulators.
    function test_simulatorsDoNotShareOverrides() public {
        CCIPLocalSimulatorFork first = new CCIPLocalSimulatorFork();
        CCIPLocalSimulatorFork second = new CCIPLocalSimulatorFork();
        first.setNetworkDetails(SEPOLIA, _details(7));
        assertEq(first.getNetworkDetails(SEPOLIA).chainSelector, 7);
        assertEq(second.getNetworkDetails(SEPOLIA).chainSelector, 16015286601757825753);
    }
}
