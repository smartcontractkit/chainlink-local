// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console2} from "forge-std/Test.sol";
import {CCIPLocalSimulator} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";

import {ERC20} from
    "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v5.0.2/contracts/token/ERC20/ERC20.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";

contract MockERC20TokenOwner is ERC20, OwnerIsCreator {
    constructor() ERC20("MockERC20Token", "MTK") {}

    function mint(address account, uint256 amount) public onlyOwner {
        _mint(account, amount);
    }
}

contract MockERC20TokenGetCCIPAdmin is ERC20 {
    address immutable i_CCIPAdmin;

    constructor() ERC20("MockERC20Token", "MTK") {
        i_CCIPAdmin = msg.sender;
    }

    function mint(address account, uint256 amount) public {
        require(msg.sender == i_CCIPAdmin, "Only CCIP Admin can mint");
        _mint(account, amount);
    }

    function getCCIPAdmin() public view returns (address) {
        return (i_CCIPAdmin);
    }
}

contract CCIPLocalSimulatorUnitTest is Test {
    CCIPLocalSimulator public ccipLocalSimulator;

    MockERC20TokenOwner public mockERC20TokenOwner;
    MockERC20TokenGetCCIPAdmin public mockERC20TokenGetCCIPAdmin;

    address alice;
    address bob;
    uint64 chainSelector;

    function setUp() public {
        ccipLocalSimulator = new CCIPLocalSimulator();

        (uint64 chainSelector_,,,,,,) = ccipLocalSimulator.configuration();
        chainSelector = chainSelector_;

        alice = makeAddr("alice");
        bob = makeAddr("bob");

        vm.startPrank(alice);
        mockERC20TokenOwner = new MockERC20TokenOwner();
        mockERC20TokenGetCCIPAdmin = new MockERC20TokenGetCCIPAdmin();
        vm.stopPrank();

        assertEq(mockERC20TokenOwner.owner(), alice);
        assertEq(mockERC20TokenGetCCIPAdmin.getCCIPAdmin(), alice);
    }

    function test_shouldSupportNewTokenIfCalledByOwner() public {
        address[] memory supportedTokensBefore = ccipLocalSimulator.getSupportedTokens(chainSelector);

        vm.startPrank(alice);
        ccipLocalSimulator.supportNewTokenViaOwner(address(mockERC20TokenOwner));
        vm.stopPrank();

        address[] memory supportedTokensAfter = ccipLocalSimulator.getSupportedTokens(chainSelector);
        assertEq(supportedTokensAfter.length, supportedTokensBefore.length + 1);
        assertEq(supportedTokensAfter[supportedTokensAfter.length - 1], address(mockERC20TokenOwner));
    }

    function test_shouldRevertIfSupportNewTokenIsNotCalledByOwner() public {
        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(CCIPLocalSimulator.CCIPLocalSimulator__MsgSenderIsNotTokenOwner.selector)
        );
        ccipLocalSimulator.supportNewTokenViaOwner(address(mockERC20TokenOwner));
        vm.stopPrank();
    }

    function test_shouldSupportNewTokenIfCalledByCCIPAdmin() public {
        address[] memory supportedTokensBefore = ccipLocalSimulator.getSupportedTokens(chainSelector);

        vm.startPrank(alice);
        ccipLocalSimulator.supportNewTokenViaGetCCIPAdmin(address(mockERC20TokenGetCCIPAdmin));
        vm.stopPrank();

        address[] memory supportedTokensAfter = ccipLocalSimulator.getSupportedTokens(chainSelector);
        assertEq(supportedTokensAfter.length, supportedTokensBefore.length + 1);
        assertEq(supportedTokensAfter[supportedTokensAfter.length - 1], address(mockERC20TokenGetCCIPAdmin));
    }

    function test_shouldRevertIfSupportNewTokenIsNotCalledByCCIPAdmin() public {
        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(CCIPLocalSimulator.CCIPLocalSimulator__MsgSenderIsNotTokenOwner.selector)
        );
        ccipLocalSimulator.supportNewTokenViaGetCCIPAdmin(address(mockERC20TokenGetCCIPAdmin));
        vm.stopPrank();
    }
}
