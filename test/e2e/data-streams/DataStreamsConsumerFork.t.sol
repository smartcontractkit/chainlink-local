// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DataStreamsLocalSimulatorFork, Register} from "../../../src/data-streams/DataStreamsLocalSimulatorFork.sol";
import {ReportVersions} from "../../../src/data-streams/ReportVersions.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/interfaces/IERC20.sol";

interface IVerifierProxy {
    function verify(bytes calldata payload, bytes calldata parameterPayload)
        external
        payable
        returns (bytes memory verifierResponse);

    function s_feeManager() external view returns (address);
}

library Common {
    struct Asset {
        address token;
        uint256 amount;
    }
}

interface IFeeManager {
    function getFeeAndReward(address subscriber, bytes memory unverifiedReport, address quoteAddress)
        external
        returns (Common.Asset memory, Common.Asset memory, uint256);

    function i_linkAddress() external view returns (address);

    function i_nativeAddress() external view returns (address);

    function i_rewardManager() external view returns (address);
}

contract DataStreamsConsumerForkTest is Test {
    bytes public UNVERIFIED_INPUT_REPORT =
        hex"0006f9b553e393ced311551efd30d1decedb63d76ad41737462e2cdbbdff1578000000000000000000000000000000000000000000000000000000004b0b4006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000220000000000000000000000000000000000000000000000000000000000000028001010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000120000359843a543ee2fe414dc14c7e7920ef10f4372990b79d6361cdc0dd1ba7820000000000000000000000000000000000000000000000000000000067407f400000000000000000000000000000000000000000000000000000000067407f4000000000000000000000000000000000000000000000000000001b1fa2a2d6400000000000000000000000000000000000000000000000000016e76dd08b2c34000000000000000000000000000000000000000000000000000000006741d0c00000000000000000000000000000000000000000000000b5c654dd994866cb600000000000000000000000000000000000000000000000b5c6042e4f23a92c400000000000000000000000000000000000000000000000b5c7dc7c8e30df80000000000000000000000000000000000000000000000000000000000000000002f68eeb7e489bef244eb83d56e1b8af210a65363e5ad4407f374e5c06f46db98c36b4181b70329535011ba504fb8e09570c10a6de7f1f138cf322237c72cb0d650000000000000000000000000000000000000000000000000000000000000002648579956ffb863e4ea9470a87bb59b26e91ea893f96c2ab933786e531f2701a06d92b4e896a42d40d19a3b5ba1711d5f00bc262084d7afce44a5bbde3014fe5";

    ReportVersions.ReportV3 public EXPECTED_REPORT = ReportVersions.ReportV3({
        feedId: 0x000359843a543ee2fe414dc14c7e7920ef10f4372990b79d6361cdc0dd1ba782,
        validFromTimestamp: 1732280128,
        observationsTimestamp: 1732280128,
        nativeFee: 29822686516800,
        linkFee: 6446908323867700,
        expiresAt: 1732366528,
        price: 3353151968509396700000,
        bid: 3353129257778281000000,
        ask: 3353262200000000000000
    });

    DataStreamsLocalSimulatorFork dataStreamsLocalSimulatorFork;

    uint256 arbitrumSepoliaForkId;
    address alice;

    function setUp() public {
        string memory ARBITRUM_SEPOLIA_RPC_URL = vm.envString("ARBITRUM_SEPOLIA_RPC_URL");
        uint256 BLOCK_NUMBER = 99556570;
        arbitrumSepoliaForkId = vm.createSelectFork(ARBITRUM_SEPOLIA_RPC_URL, BLOCK_NUMBER);

        alice = makeAddr("alice");

        dataStreamsLocalSimulatorFork = new DataStreamsLocalSimulatorFork();
    }

    function preTestHook() public returns (IVerifierProxy, IFeeManager, address, bytes memory) {
        assertEq(vm.activeFork(), arbitrumSepoliaForkId);

        Register.NetworkDetails memory networkDetails = dataStreamsLocalSimulatorFork.getNetworkDetails(block.chainid);
        IVerifierProxy verifierProxy = IVerifierProxy(networkDetails.verifierProxyAddress);
        IFeeManager feeManager = IFeeManager(verifierProxy.s_feeManager());
        address rewardManager = feeManager.i_rewardManager();

        // Decode unverified report to extract report data
        (, bytes memory reportData) = abi.decode(UNVERIFIED_INPUT_REPORT, (bytes32[3], bytes));

        return (verifierProxy, feeManager, rewardManager, reportData);
    }

    function postTestHook(ReportVersions.ReportV3 memory verifiedReport) public {
        assertEq(verifiedReport.feedId, EXPECTED_REPORT.feedId);
        assertEq(verifiedReport.validFromTimestamp, EXPECTED_REPORT.validFromTimestamp);
        assertEq(verifiedReport.observationsTimestamp, EXPECTED_REPORT.observationsTimestamp);
        assertEq(verifiedReport.nativeFee, EXPECTED_REPORT.nativeFee);
        assertEq(verifiedReport.linkFee, EXPECTED_REPORT.linkFee);
        assertEq(verifiedReport.expiresAt, EXPECTED_REPORT.expiresAt);
        assertEq(verifiedReport.price, EXPECTED_REPORT.price);
        assertEq(verifiedReport.bid, EXPECTED_REPORT.bid);
        assertEq(verifiedReport.ask, EXPECTED_REPORT.ask);
    }

    function test_forkPayWithLink() external {
        (IVerifierProxy verifierProxy, IFeeManager feeManager, address rewardManager, bytes memory reportData) =
            preTestHook();

        address feeTokenAddress = feeManager.i_linkAddress();

        (Common.Asset memory fee,,) = feeManager.getFeeAndReward(address(this), reportData, feeTokenAddress);

        uint256 linkBalanceAliceBefore = IERC20(feeTokenAddress).balanceOf(alice);
        dataStreamsLocalSimulatorFork.requestLinkFromFaucet(alice, fee.amount);

        vm.startPrank(alice);

        IERC20(feeTokenAddress).approve(rewardManager, fee.amount);

        bytes memory verifiedReportData = verifierProxy.verify(UNVERIFIED_INPUT_REPORT, abi.encode(feeTokenAddress));
        ReportVersions.ReportV3 memory verifiedReport = abi.decode(verifiedReportData, (ReportVersions.ReportV3));

        vm.stopPrank();

        uint256 linkBalanceAliceAfter = IERC20(feeTokenAddress).balanceOf(alice);
        assertEq(linkBalanceAliceAfter, linkBalanceAliceBefore);

        postTestHook(verifiedReport);
    }

    function test_forkPayWithNative() external {
        (IVerifierProxy verifierProxy, IFeeManager feeManager,, bytes memory reportData) = preTestHook();

        address feeTokenAddress = feeManager.i_nativeAddress();

        (Common.Asset memory fee,,) = feeManager.getFeeAndReward(address(this), reportData, feeTokenAddress);

        uint256 nativeBalanceAliceBefore = address(alice).balance;
        dataStreamsLocalSimulatorFork.requestNativeFromFaucet(alice, fee.amount);

        vm.startPrank(alice);

        bytes memory verifiedReportData =
            verifierProxy.verify{value: fee.amount}(UNVERIFIED_INPUT_REPORT, abi.encode(feeTokenAddress));

        ReportVersions.ReportV3 memory verifiedReport = abi.decode(verifiedReportData, (ReportVersions.ReportV3));

        vm.stopPrank();

        uint256 nativeBalanceAliceAfter = address(alice).balance;
        assertEq(nativeBalanceAliceAfter, nativeBalanceAliceBefore);

        postTestHook(verifiedReport);
    }
}
