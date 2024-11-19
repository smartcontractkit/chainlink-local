// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OwnerIsCreator} from "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";
import {IERC20} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";

// import {IRewardManager} from "@chainlink/contracts/src/v0.8/llo-feeds/interfaces/IRewardManager.sol";
import {IRewardManager} from "./interfaces/IRewardManager.sol";

contract MockRewardManager is IRewardManager {
    using SafeERC20 for IERC20;

    error Unauthorized();

    address public immutable i_linkAddress;
    address public s_feeManagerAddress;

    event FeePaid(IRewardManager.FeePayment[] payments, address payer);

    modifier onlyFeeManager() {
        if (msg.sender != s_feeManagerAddress) revert Unauthorized();
        _;
    }

    constructor(address linkAddress) {
        i_linkAddress = linkAddress;
    }

    function onFeePaid(FeePayment[] calldata payments, address payer) external override onlyFeeManager {
        uint256 totalFeeAmount;
        for (uint256 i; i < payments.length; ++i) {
            unchecked {
                // Tally the total payable fees
                totalFeeAmount += payments[i].amount;
            }
        }

        // Transfer fees to this contract
        IERC20(i_linkAddress).safeTransferFrom(payer, address(this), totalFeeAmount);

        emit FeePaid(payments, payer);
    }

    function claimRewards(bytes32[] memory /*poolIds*/ ) external pure override {
        revert("Not implemented");
    }

    function setFeeManager(address newFeeManager) external override {
        s_feeManagerAddress = newFeeManager;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == this.onFeePaid.selector;
    }
}
