// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {CCIPLocalSimulator, IRouterClient} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {ERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v5.0.2/contracts/token/ERC20/ERC20.sol";
import {OwnerIsCreator} from "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";
import {AccessControl} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v5.0.2/contracts/access/AccessControl.sol";

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

contract MockERC20AccessControl is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor() ERC20("MockERC20Token", "MTK") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function mint(address account, uint256 amount) external {
        require(hasRole(MINTER_ROLE, msg.sender));
        _mint(account, amount);
    }
}

contract CCIPLocalSimulatorUnitTest is Test {
    CCIPLocalSimulator public ccipLocalSimulator;
    IRouterClient public router;

    MockERC20TokenOwner public mockERC20TokenOwner;
    MockERC20TokenGetCCIPAdmin public mockERC20TokenGetCCIPAdmin;
    MockERC20AccessControl public mockERC20AccessControl;

    address alice;
    address bob;
    uint64 chainSelector;

    function setUp() public {
        ccipLocalSimulator = new CCIPLocalSimulator();

        (uint64 chainSelector_, IRouterClient sourceRouter,,,,,) = ccipLocalSimulator.configuration();
        chainSelector = chainSelector_;
        router = sourceRouter;

        alice = makeAddr("alice");
        bob = makeAddr("bob");

        vm.startPrank(alice);
        mockERC20TokenOwner = new MockERC20TokenOwner();
        mockERC20TokenGetCCIPAdmin = new MockERC20TokenGetCCIPAdmin();
        mockERC20AccessControl = new MockERC20AccessControl();
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

    function test_shouldSupportNewTokenIfCalledByAccessControlDefaultAdmin() public {
        address[] memory supportedTokensBefore = ccipLocalSimulator.getSupportedTokens(chainSelector);

        vm.startPrank(alice);
        ccipLocalSimulator.supportNewTokenViaAccessControlDefaultAdmin(address(mockERC20AccessControl));
        vm.stopPrank();

        address[] memory supportedTokensAfter = ccipLocalSimulator.getSupportedTokens(chainSelector);
        assertEq(supportedTokensAfter.length, supportedTokensBefore.length + 1);
        assertEq(supportedTokensAfter[supportedTokensAfter.length - 1], address(mockERC20AccessControl));
    }

    function test_shouldRevertIfSupportNewTokenIsNotCalledByAccessControlDefaultAdmin() public {
        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPLocalSimulator.CCIPLocalSimulator__RequiredRoleNotFound.selector,
                bob,
                mockERC20AccessControl.DEFAULT_ADMIN_ROLE(),
                address(mockERC20AccessControl)
            )
        );
        ccipLocalSimulator.supportNewTokenViaAccessControlDefaultAdmin(address(mockERC20AccessControl));
        vm.stopPrank();
    }

    function test_shouldSendCCIPMessageWithEvmExtraArgsV1() public {
        vm.startPrank(alice);
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(bob),
            data: "",
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 500_000})),
            feeToken: address(0)
        });
        router.ccipSend(chainSelector, message);
        vm.stopPrank();
    }

    function test_shouldSendCCIPMessageWithGenericExtraArgsV2() public {
        vm.startPrank(alice);
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(bob),
            data: "",
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 500_000, allowOutOfOrderExecution: true})),
            feeToken: address(0)
        });
        router.ccipSend(chainSelector, message);
        vm.stopPrank();
    }
}
