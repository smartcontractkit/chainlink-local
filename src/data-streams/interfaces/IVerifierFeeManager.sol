// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC165} from "@openzeppelin/contracts@4.8.3/interfaces/IERC165.sol";

interface IVerifierFeeManager is IERC165 {
    function processFee(bytes calldata payload, bytes calldata parameterPayload, address subscriber) external payable;
    function processFeeBulk(bytes[] calldata payloads, bytes calldata parameterPayload, address subscriber)
        external
        payable;
}
