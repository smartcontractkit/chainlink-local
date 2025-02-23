// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OwnerIsCreator} from "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";
import {IERC20} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWERC20} from "@chainlink/contracts/src/v0.8/shared/interfaces/IWERC20.sol";
import {Math} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/utils/math/Math.sol";

// import {IRewardManager} from "@chainlink/contracts/src/v0.8/llo-feeds/interfaces/IRewardManager.sol";
// import {IVerifierFeeManager} from "@chainlink/contracts/src/v0.8/llo-feeds/interfaces/IVerifierFeeManager.sol";
import {IRewardManager} from "./interfaces/IRewardManager.sol";
import {IVerifierFeeManager} from "./interfaces/IVerifierFeeManager.sol";

library Common {
    // @notice The asset struct to hold the address of an asset and amount
    struct Asset {
        address assetAddress;
        uint256 amount;
    }
}

contract MockFeeManager is IVerifierFeeManager, OwnerIsCreator {
    using SafeERC20 for IERC20;

    error Unauthorized();
    error InvalidAddress();
    error InvalidQuote();
    error ExpiredReport();
    error InvalidDiscount();
    error InvalidSurcharge();
    error InvalidDeposit();

    /// @notice the total discount that can be applied to a fee, 1e18 = 100% discount
    uint64 private constant PERCENTAGE_SCALAR = 1e18;

    address public immutable i_linkAddress;
    address public immutable i_nativeAddress;
    address public immutable i_proxyAddress;
    IRewardManager public immutable i_rewardManager;

    uint256 public s_nativeSurcharge;
    mapping(address => uint256) public s_mockDiscounts;

    modifier onlyProxy() {
        if (msg.sender != i_proxyAddress) revert Unauthorized();
        _;
    }

    constructor(address linkAddress, address nativeAddress, address proxyAddress, address rewardManager) {
        i_linkAddress = linkAddress;
        i_nativeAddress = nativeAddress;
        i_proxyAddress = proxyAddress;
        i_rewardManager = IRewardManager(rewardManager);

        IERC20(i_linkAddress).approve(address(i_rewardManager), type(uint256).max);
    }

    function processFee(bytes calldata payload, bytes calldata parameterPayload, address subscriber)
        external
        payable
        override
        onlyProxy
    {
        _processFee(payload, parameterPayload, subscriber);
    }

    function processFeeBulk(bytes[] calldata payloads, bytes calldata parameterPayload, address subscriber)
        external
        payable
        override
        onlyProxy
    {
        for (uint256 i = 0; i < payloads.length; i++) {
            _processFee(payloads[i], parameterPayload, subscriber);
        }
    }

    function getFeeAndReward(address subscriber, bytes memory report, address quoteAddress)
        public
        view
        returns (Common.Asset memory, Common.Asset memory, uint256)
    {
        Common.Asset memory fee;
        Common.Asset memory reward;

        //verify the quote payload is a supported token
        if (quoteAddress != i_nativeAddress && quoteAddress != i_linkAddress) {
            revert InvalidQuote();
        }

        //decode the report depending on the version
        uint256 linkQuantity;
        uint256 nativeQuantity;
        uint256 expiresAt;
        (,,, nativeQuantity, linkQuantity, expiresAt) =
            abi.decode(report, (bytes32, uint32, uint32, uint192, uint192, uint32));

        //read the timestamp bytes from the report data and verify it has not expired
        if (expiresAt < block.timestamp) {
            revert ExpiredReport();
        }

        uint256 discount = s_mockDiscounts[subscriber];

        //the reward is always set in LINK
        reward.assetAddress = i_linkAddress;
        reward.amount = Math.ceilDiv(linkQuantity * (PERCENTAGE_SCALAR - discount), PERCENTAGE_SCALAR);

        //calculate either the LINK fee or native fee if it's within the report
        if (quoteAddress == i_linkAddress) {
            fee.assetAddress = i_linkAddress;
            fee.amount = reward.amount;
        } else {
            uint256 surchargedFee =
                Math.ceilDiv(nativeQuantity * (PERCENTAGE_SCALAR + s_nativeSurcharge), PERCENTAGE_SCALAR);

            fee.assetAddress = i_nativeAddress;
            fee.amount = Math.ceilDiv(surchargedFee * (PERCENTAGE_SCALAR - discount), PERCENTAGE_SCALAR);
        }

        return (fee, reward, discount);
    }

    function _processFee(bytes calldata payload, bytes calldata parameterPayload, address subscriber) internal {
        if (subscriber == address(this)) revert InvalidAddress();
        address quote = abi.decode(parameterPayload, (address));

        (, bytes memory report) = abi.decode(payload, (bytes32[3], bytes));

        (Common.Asset memory fee, /*Common.Asset memory reward*/, /*uint256 appliedDiscount*/ ) =
            getFeeAndReward(subscriber, report, quote);

        if (fee.assetAddress == i_linkAddress) {
            IRewardManager.FeePayment[] memory payments = new IRewardManager.FeePayment[](1);
            payments[0] = IRewardManager.FeePayment({poolId: bytes32(0), amount: uint192(fee.amount)});
            i_rewardManager.onFeePaid(payments, subscriber);
        } else {
            if (msg.value != 0) {
                if (fee.amount > msg.value) revert InvalidDeposit();

                IWERC20(i_nativeAddress).deposit{value: fee.amount}();

                uint256 change;
                unchecked {
                    change = msg.value - fee.amount;
                }

                if (change > 0) {
                    payable(subscriber).transfer(change);
                }
            } else {
                IERC20(i_nativeAddress).safeTransferFrom(subscriber, address(this), fee.amount);
            }
        }
    }

    function setNativeSurcharge(uint64 surcharge) external {
        if (surcharge > PERCENTAGE_SCALAR) revert InvalidSurcharge();

        s_nativeSurcharge = surcharge;
    }

    function setMockDiscount(address subscriber, uint256 discount) external {
        if (discount > PERCENTAGE_SCALAR) revert InvalidDiscount();

        s_mockDiscounts[subscriber] = discount;
    }

    function getMockDiscount(address subscriber) external view returns (uint256) {
        return s_mockDiscounts[subscriber];
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == this.processFee.selector || interfaceId == this.processFeeBulk.selector;
    }
}
