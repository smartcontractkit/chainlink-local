// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Register} from "../../../src/ccip/Register.sol";
import {
    RegisterData0,
    RegisterData1,
    RegisterData2,
    RegisterData3,
    RegisterDataShards
} from "../../../src/ccip/RegisterData.sol";
import {CCIPLocalSimulatorFork} from "../../../src/ccip/CCIPLocalSimulatorFork.sol";

/// @dev Register's built-in network details live in generated data shards; `setNetworkDetails` overrides are stored.
contract RegisterUnitTest is Test {
    uint256 internal constant SEPOLIA = 11155111;

    /// @dev Deploys Register and places the generated data shards, mirroring what the simulator does.
    function _etchedRegister() internal returns (Register register) {
        register = new Register();
        RegisterDataShards.etchAll(vm, address(register));
    }

    function _details(uint64 chainSelector) internal pure returns (Register.NetworkDetails memory details) {
        details.chainSelector = chainSelector;
        details.routerAddress = address(0xBEEF);
    }

    /// @dev Decodes chains across shards: Ethereum and Sepolia (first shard), Avalanche (gap-heavy entry),
    ///      and Base (later shard).
    function test_builtInDetails_decodedFromShards() public {
        Register register = _etchedRegister();

        Register.NetworkDetails memory ethereum = register.getNetworkDetails(1);
        assertEq(ethereum.chainSelector, 5009297550715157269);
        assertEq(ethereum.wrappedNativeAddress, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        Register.NetworkDetails memory sepolia = register.getNetworkDetails(SEPOLIA);
        assertEq(sepolia.chainSelector, 16015286601757825753);
        assertEq(sepolia.routerAddress, 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59);
        assertEq(sepolia.linkAddress, 0x779877A7B0D9E8603169DdbD7836e478b4624789);

        Register.NetworkDetails memory avalanche = register.getNetworkDetails(43114);
        assertEq(avalanche.chainSelector, 6433500567565415381);
        assertEq(avalanche.routerAddress, 0xF4c7E640EdA248ef95972845a62bdC74237805dB);
        assertEq(avalanche.ccipBnMAddress, address(0));
        assertEq(avalanche.tokenAdminRegistryAddress, 0xc8df5D618c6a59Cc6A311E96a39450381001464F);

        Register.NetworkDetails memory base = register.getNetworkDetails(8453);
        assertEq(base.chainSelector, 15971525489660198786);
        assertEq(base.linkAddress, 0x88Fb150BDc53A65fe94Dea0c9BA0a6dAf8C6e196);
    }

    function test_unknownChain_returnsZeroDetails() public {
        Register register = _etchedRegister();
        Register.NetworkDetails memory unknown = register.getNetworkDetails(424242424242);
        assertEq(unknown.chainSelector, 0);
        assertEq(unknown.routerAddress, address(0));
    }

    function test_setNetworkDetails_overridesBuiltInAndUnknownChains() public {
        Register register = _etchedRegister();
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
        Register register = _etchedRegister();
        Register.NetworkDetails memory zero;
        register.setNetworkDetails(SEPOLIA, zero);
        assertEq(register.getNetworkDetails(SEPOLIA).chainSelector, 0);
    }

    /// @dev A bare Register (no shards placed) serves overrides only; the simulator places the shards.
    function test_bareRegister_servesOverridesOnly() public {
        Register register = new Register();
        assertEq(register.getNetworkDetails(1).chainSelector, 0);
        register.setNetworkDetails(1, _details(9));
        assertEq(register.getNetworkDetails(1).chainSelector, 9);
    }

    /// @dev Each simulator gets its own Register (placed with vm.etch), so overrides do not leak between simulators.
    function test_simulatorsDoNotShareOverrides() public {
        CCIPLocalSimulatorFork first = new CCIPLocalSimulatorFork();
        CCIPLocalSimulatorFork second = new CCIPLocalSimulatorFork();
        first.setNetworkDetails(SEPOLIA, _details(7));
        assertEq(first.getNetworkDetails(SEPOLIA).chainSelector, 7);
        assertEq(second.getNetworkDetails(SEPOLIA).chainSelector, 16015286601757825753);
    }

    /// @dev Register and its data shards are etched, never deployed, but downstream projects compile the
    ///      artifacts and size-gate them, so every generated contract must stay under the EIP-170 limit.
    function test_generatedContractsStayUnderEip170() public pure {
        assertLt(type(Register).runtimeCode.length, 24_576);
        assertLt(type(RegisterData0).runtimeCode.length, 24_576);
        assertLt(type(RegisterData1).runtimeCode.length, 24_576);
        assertLt(type(RegisterData2).runtimeCode.length, 24_576);
        assertLt(type(RegisterData3).runtimeCode.length, 24_576);
    }
}
