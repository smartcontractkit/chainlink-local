// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {ITokenAdminRegistry} from "@chainlink/contracts-ccip/contracts/interfaces/ITokenAdminRegistry.sol";
import {
    RegistryModuleOwnerCustom
} from "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {LockReleaseTokenPool, IERC20} from "@chainlink/contracts-ccip/contracts/pools/LockReleaseTokenPool.sol";
import {ERC20LockBox} from "@chainlink/contracts-ccip/contracts/pools/ERC20LockBox.sol";
import {TokenPool} from "@chainlink/contracts-ccip/contracts/pools/TokenPool.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {RateLimiter} from "@chainlink/contracts-ccip/contracts/libraries/RateLimiter.sol";
import {BurnMintERC20} from "@chainlink/contracts/src/v0.8/shared/token/ERC20/BurnMintERC20.sol";
import {AuthorizedCallers} from "@chainlink/contracts/src/v0.8/shared/access/AuthorizedCallers.sol";

import {EncodeExtraArgsOffchain} from "../../../src/test/ccip/utils/EncodeExtraArgsOffchain.sol";

contract CCTLockReleaseFasterThanFinalityForkTest is Test {
    uint32 internal constant GAS_LIMIT = 0;
    uint16 internal constant BLOCK_CONFIRMATIONS = 1;
    uint256 internal constant AMOUNT_TO_SEND = 1 ether;
    uint256 internal constant DESTINATION_LIQUIDITY = 10 ether;

    CCIPLocalSimulatorFork internal s_forkSimulator;
    EncodeExtraArgsOffchain internal s_encoder;
    uint256 internal s_sourceFork;
    uint256 internal s_destinationFork;

    Register.NetworkDetails internal s_sourceNetwork;
    Register.NetworkDetails internal s_destinationNetwork;

    address internal s_alice;
    address internal s_bob;

    function setUp() public {
        s_sourceFork = vm.createSelectFork(vm.envString("ETHEREUM_SEPOLIA_RPC_URL"));
        s_destinationFork = vm.createFork(vm.envString("ARBITRUM_SEPOLIA_RPC_URL"));

        s_forkSimulator = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(s_forkSimulator));

        s_encoder = new EncodeExtraArgsOffchain();
        vm.makePersistent(address(s_encoder));

        vm.selectFork(s_sourceFork);
        s_sourceNetwork = s_forkSimulator.getNetworkDetails(block.chainid);

        vm.selectFork(s_destinationFork);
        s_destinationNetwork = s_forkSimulator.getNetworkDetails(block.chainid);

        s_alice = makeAddr("alice");
        s_bob = makeAddr("bob");

        vm.selectFork(s_sourceFork);
        vm.deal(s_alice, 10 ether);
    }

    function test_cctLockReleaseFasterThanFinality_fork() external {
        vm.selectFork(s_sourceFork);
        BurnMintERC20 sourceToken = new BurnMintERC20("CCT LockRelease Source", "CCTLR-S", 18, 0, AMOUNT_TO_SEND);
        ERC20LockBox sourceLockBox = new ERC20LockBox(address(sourceToken));
        LockReleaseTokenPool sourcePool = new LockReleaseTokenPool(
            IERC20(address(sourceToken)),
            18,
            address(0),
            s_sourceNetwork.rmnProxyAddress,
            s_sourceNetwork.routerAddress,
            address(sourceLockBox)
        );
        _authorizeCaller(sourceLockBox, address(sourcePool));
        sourceToken.transfer(s_alice, AMOUNT_TO_SEND);

        _registerAndSetPool(s_sourceNetwork, address(sourceToken), address(sourcePool));

        vm.selectFork(s_destinationFork);
        BurnMintERC20 destinationToken =
            new BurnMintERC20("CCT LockRelease Dest", "CCTLR-D", 18, 0, DESTINATION_LIQUIDITY);
        ERC20LockBox destinationLockBox = new ERC20LockBox(address(destinationToken));
        LockReleaseTokenPool destinationPool = new LockReleaseTokenPool(
            IERC20(address(destinationToken)),
            18,
            address(0),
            s_destinationNetwork.rmnProxyAddress,
            s_destinationNetwork.routerAddress,
            address(destinationLockBox)
        );
        _authorizeCaller(destinationLockBox, address(destinationPool));

        _registerAndSetPool(s_destinationNetwork, address(destinationToken), address(destinationPool));
        destinationToken.transfer(address(destinationLockBox), DESTINATION_LIQUIDITY);

        vm.selectFork(s_sourceFork);
        _configureTrustedPool(
            address(sourcePool), s_destinationNetwork.chainSelector, address(destinationPool), address(destinationToken)
        );
        TokenPool(address(sourcePool)).setMinBlockConfirmations(BLOCK_CONFIRMATIONS);

        vm.selectFork(s_destinationFork);
        _configureTrustedPool(
            address(destinationPool), s_sourceNetwork.chainSelector, address(sourcePool), address(sourceToken)
        );

        vm.selectFork(s_sourceFork);
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(sourceToken), amount: AMOUNT_TO_SEND});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(s_bob),
            data: "",
            tokenAmounts: tokenAmounts,
            extraArgs: s_encoder.encodeV3Basic(GAS_LIMIT, BLOCK_CONFIRMATIONS),
            feeToken: address(0)
        });

        vm.startPrank(s_alice);
        sourceToken.approve(s_sourceNetwork.routerAddress, AMOUNT_TO_SEND);
        uint256 fee = IRouterClient(s_sourceNetwork.routerAddress).getFee(s_destinationNetwork.chainSelector, message);
        IRouterClient(s_sourceNetwork.routerAddress).ccipSend{value: fee}(s_destinationNetwork.chainSelector, message);
        vm.stopPrank();

        s_forkSimulator.switchChainAndRouteMessage(s_destinationFork);

        vm.selectFork(s_sourceFork);
        assertEq(sourceToken.balanceOf(s_alice), 0);
        assertEq(sourceToken.totalSupply(), AMOUNT_TO_SEND);
        assertEq(sourceToken.balanceOf(address(sourceLockBox)), AMOUNT_TO_SEND);

        vm.selectFork(s_destinationFork);
        assertEq(destinationToken.balanceOf(s_bob), AMOUNT_TO_SEND);
        assertEq(destinationToken.totalSupply(), DESTINATION_LIQUIDITY);
        assertEq(destinationToken.balanceOf(address(destinationLockBox)), DESTINATION_LIQUIDITY - AMOUNT_TO_SEND);
    }

    function _registerAndSetPool(Register.NetworkDetails memory network, address token, address pool) internal {
        RegistryModuleOwnerCustom(network.registryModuleOwnerCustomAddress).registerAccessControlDefaultAdmin(token);
        ITokenAdminRegistry(network.tokenAdminRegistryAddress).acceptAdminRole(token);
        ITokenAdminRegistry(network.tokenAdminRegistryAddress).setPool(token, pool);
    }

    function _authorizeCaller(ERC20LockBox lockBox, address caller) internal {
        address[] memory addCallers = new address[](1);
        addCallers[0] = caller;
        lockBox.applyAuthorizedCallerUpdates(
            AuthorizedCallers.AuthorizedCallerArgs({addedCallers: addCallers, removedCallers: new address[](0)})
        );
    }

    function _configureTrustedPool(
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteToken
    ) internal {
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePool);

        TokenPool.ChainUpdate[] memory chainUpdates = new TokenPool.ChainUpdate[](1);
        chainUpdates[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encode(remoteToken),
            outboundRateLimiterConfig: _disabledRateLimiter(),
            inboundRateLimiterConfig: _disabledRateLimiter()
        });

        TokenPool(localPool).applyChainUpdates(new uint64[](0), chainUpdates);
    }

    function _disabledRateLimiter() internal pure returns (RateLimiter.Config memory config) {
        config = RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0});
    }
}
