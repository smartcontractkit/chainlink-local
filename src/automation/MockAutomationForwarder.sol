// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

uint256 constant PERFORM_GAS_CUSHION = 5_000;

/**
 * @title MockAutomationForwarder is a relayer that sits between the simulator and the customer's target contract
 * @dev The purpose of the forwarder is to give customers a consistent address to authorize against,
 * which stays consistent between migrations.
 */
contract MockAutomationForwarder {
    /**
     * @notice forward is called by the registry and forwards the call to the target
     * @param gasAmount is the amount of gas to use in the call
     * @param data is the 4 bytes function selector + arbitrary function data
     * @return success indicating whether the target call succeeded or failed
     */
    function forward(address target, uint256 gasAmount, bytes memory data)
        external
        returns (bool success, uint256 gasUsed)
    {
        gasUsed = gasleft();
        assembly {
            let g := gas()
            // Compute g -= PERFORM_GAS_CUSHION and check for underflow
            if lt(g, PERFORM_GAS_CUSHION) { revert(0, 0) }
            g := sub(g, PERFORM_GAS_CUSHION)
            // if g - g//64 <= gasAmount, revert
            // (we subtract g//64 because of EIP-150)
            if iszero(gt(sub(g, div(g, 64)), gasAmount)) { revert(0, 0) }
            // solidity calls check that a contract actually exists at the destination, so we do the same
            if iszero(extcodesize(target)) { revert(0, 0) }
            // call with exact gas
            success := call(gasAmount, target, 0, add(data, 0x20), mload(data), 0, 0)
        }
        gasUsed = gasUsed - gasleft();
        return (success, gasUsed);
    }
}
