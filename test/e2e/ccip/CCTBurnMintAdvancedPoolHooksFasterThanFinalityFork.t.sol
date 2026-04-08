// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {ITokenAdminRegistry} from "@chainlink/contracts-ccip/contracts/interfaces/ITokenAdminRegistry.sol";
import {IBurnMintERC20} from "@chainlink/contracts-ccip/contracts/interfaces/IBurnMintERC20.sol";
import {RegistryModuleOwnerCustom} from "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {BurnMintTokenPool} from "@chainlink/contracts-ccip/contracts/pools/BurnMintTokenPool.sol";
import {AdvancedPoolHooks} from "@chainlink/contracts-ccip/contracts/pools/AdvancedPoolHooks.sol";
import {TokenPool} from "@chainlink/contracts-ccip/contracts/pools/TokenPool.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {RateLimiter} from "@chainlink/contracts-ccip/contracts/libraries/RateLimiter.sol";
import {BurnMintERC20} from "@chainlink/contracts/src/v0.8/shared/token/ERC20/BurnMintERC20.sol";
import {AuthorizedCallers} from "@chainlink/contracts/src/v0.8/shared/access/AuthorizedCallers.sol";

import {EncodeExtraArgsOffchain} from "../../../src/test/ccip/utils/EncodeExtraArgsOffchain.sol";

contract CCTBurnMintAdvancedPoolHooksFasterThanFinalityForkTest is Test {
    uint32 internal constant GAS_LIMIT = 0;
    uint16 internal constant BLOCK_CONFIRMATIONS = 1;

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

    function test_cctBurnMintAdvancedPoolHooksFasterThanFinality_fork() external {
        uint256 amountToSend = 1 ether;

        vm.selectFork(s_sourceFork);
        address[] memory sourceAllowList = new address[](1);
        sourceAllowList[0] = s_alice;
        AdvancedPoolHooks sourceHook = new AdvancedPoolHooks(sourceAllowList, 0, address(0), new address[](0));

        BurnMintERC20 sourceToken = new BurnMintERC20("CCT Hook Source", "CCTH-S", 18, 0, amountToSend);
        BurnMintTokenPool sourcePool = new BurnMintTokenPool(
            IBurnMintERC20(address(sourceToken)),
            18,
            address(sourceHook),
            s_sourceNetwork.rmnProxyAddress,
            s_sourceNetwork.routerAddress
        );
        sourceToken.grantMintAndBurnRoles(address(sourcePool));
        _authorizeHookCaller(sourceHook, address(sourcePool));
        sourceToken.transfer(s_alice, amountToSend);

        _registerAndSetPool(s_sourceNetwork, address(sourceToken), address(sourcePool));

        vm.selectFork(s_destinationFork);
        address[] memory destinationAllowList = new address[](1);
        destinationAllowList[0] = s_bob;
        AdvancedPoolHooks destinationHook =
            new AdvancedPoolHooks(destinationAllowList, 0, address(0), new address[](0));

        BurnMintERC20 destinationToken = new BurnMintERC20("CCT Hook Dest", "CCTH-D", 18, 0, 0);
        BurnMintTokenPool destinationPool = new BurnMintTokenPool(
            IBurnMintERC20(address(destinationToken)),
            18,
            address(destinationHook),
            s_destinationNetwork.rmnProxyAddress,
            s_destinationNetwork.routerAddress
        );
        destinationToken.grantMintAndBurnRoles(address(destinationPool));
        _authorizeHookCaller(destinationHook, address(destinationPool));

        _registerAndSetPool(s_destinationNetwork, address(destinationToken), address(destinationPool));

        vm.selectFork(s_sourceFork);
        _configureTrustedPool(
            address(sourcePool),
            s_destinationNetwork.chainSelector,
            address(destinationPool),
            address(destinationToken)
        );
        TokenPool(address(sourcePool)).setMinBlockConfirmations(BLOCK_CONFIRMATIONS);

        vm.selectFork(s_destinationFork);
        _configureTrustedPool(
            address(destinationPool),
            s_sourceNetwork.chainSelector,
            address(sourcePool),
            address(sourceToken)
        );

        vm.selectFork(s_sourceFork);
        assertEq(address(TokenPool(address(sourcePool)).getAdvancedPoolHooks()), address(sourceHook));
        assertTrue(sourceHook.getAllowListEnabled());
        address[] memory sourceAllowListRead = sourceHook.getAllowList();
        assertEq(sourceAllowListRead.length, 1);
        assertEq(sourceAllowListRead[0], s_alice);

        vm.selectFork(s_destinationFork);
        assertEq(address(TokenPool(address(destinationPool)).getAdvancedPoolHooks()), address(destinationHook));

        vm.selectFork(s_sourceFork);
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(sourceToken), amount: amountToSend});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(s_bob),
            data: "",
            tokenAmounts: tokenAmounts,
            extraArgs: s_encoder.encodeV3Basic(GAS_LIMIT, BLOCK_CONFIRMATIONS),
            feeToken: address(0)
        });

        vm.startPrank(s_alice);
        sourceToken.approve(s_sourceNetwork.routerAddress, amountToSend);
        uint256 fee = IRouterClient(s_sourceNetwork.routerAddress).getFee(s_destinationNetwork.chainSelector, message);
        IRouterClient(s_sourceNetwork.routerAddress).ccipSend{value: fee}(s_destinationNetwork.chainSelector, message);
        vm.stopPrank();

        s_forkSimulator.switchChainAndRouteMessage(s_destinationFork);

        vm.selectFork(s_sourceFork);
        assertEq(sourceToken.balanceOf(s_alice), 0);

        vm.selectFork(s_destinationFork);
        assertEq(destinationToken.balanceOf(s_bob), amountToSend);
    }

    function _registerAndSetPool(Register.NetworkDetails memory network, address token, address pool) internal {
        RegistryModuleOwnerCustom(network.registryModuleOwnerCustomAddress).registerAccessControlDefaultAdmin(token);
        ITokenAdminRegistry(network.tokenAdminRegistryAddress).acceptAdminRole(token);
        ITokenAdminRegistry(network.tokenAdminRegistryAddress).setPool(token, pool);
    }

    function _authorizeHookCaller(AdvancedPoolHooks hook, address caller) internal {
        address[] memory addCallers = new address[](1);
        addCallers[0] = caller;
        hook.applyAuthorizedCallerUpdates(
            AuthorizedCallers.AuthorizedCallerArgs({addedCallers: addCallers, removedCallers: new address[](0)})
        );
    }

    function _configureTrustedPool(address localPool, uint64 remoteChainSelector, address remotePool, address remoteToken)
        internal
    {
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
