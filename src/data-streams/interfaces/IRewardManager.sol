// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC165} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/interfaces/IERC165.sol";

interface IRewardManager is IERC165 {
    function onFeePaid(FeePayment[] calldata payments, address payee) external;
    function claimRewards(bytes32[] calldata poolIds) external;
    function setFeeManager(address newFeeManager) external;

    struct FeePayment {
        bytes32 poolId;
        uint192 amount;
    }
}
