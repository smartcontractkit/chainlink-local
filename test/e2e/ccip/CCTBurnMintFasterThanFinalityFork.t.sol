// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {ITokenAdminRegistry} from "@chainlink/contracts-ccip/contracts/interfaces/ITokenAdminRegistry.sol";
import {IBurnMintERC20} from "@chainlink/contracts-ccip/contracts/interfaces/IBurnMintERC20.sol";
import {BurnMintTokenPool} from "@chainlink/contracts-ccip/contracts/pools/BurnMintTokenPool.sol";
import {TokenPool} from "@chainlink/contracts-ccip/contracts/pools/TokenPool.sol";
import {RegistryModuleOwnerCustom} from "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {RateLimiter} from "@chainlink/contracts-ccip/contracts/libraries/RateLimiter.sol";
import {BurnMintERC20} from "@chainlink/contracts/src/v0.8/shared/token/ERC20/BurnMintERC20.sol";

import {EncodeExtraArgsOffchain} from "../../../src/test/ccip/utils/EncodeExtraArgsOffchain.sol";

contract CCTBurnMintFasterThanFinalityForkTest is Test {
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

    function test_cctBurnMintFasterThanFinality_fork() external {
        uint256 amountToSend = 1 ether;

        vm.selectFork(s_sourceFork);
        BurnMintERC20 sourceToken = new BurnMintERC20("CCT BurnMint Source", "CCTBM-S", 18, 0, amountToSend);
        BurnMintTokenPool sourcePool = new BurnMintTokenPool(
            IBurnMintERC20(address(sourceToken)),
            18,
            address(0),
            s_sourceNetwork.rmnProxyAddress,
            s_sourceNetwork.routerAddress
        );
        sourceToken.grantMintAndBurnRoles(address(sourcePool));
        sourceToken.transfer(s_alice, amountToSend);

        _registerAndSetPool(s_sourceNetwork, address(sourceToken), address(sourcePool));

        vm.selectFork(s_destinationFork);
        BurnMintERC20 destinationToken = new BurnMintERC20("CCT BurnMint Dest", "CCTBM-D", 18, 0, 0);
        BurnMintTokenPool destinationPool = new BurnMintTokenPool(
            IBurnMintERC20(address(destinationToken)),
            18,
            address(0),
            s_destinationNetwork.rmnProxyAddress,
            s_destinationNetwork.routerAddress
        );
        destinationToken.grantMintAndBurnRoles(address(destinationPool));

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
        uint256 sourceSupplyBefore = sourceToken.totalSupply();
        uint256 sourceBalanceBefore = sourceToken.balanceOf(s_alice);

        vm.selectFork(s_destinationFork);
        uint256 destinationSupplyBefore = destinationToken.totalSupply();
        uint256 destinationBalanceBefore = destinationToken.balanceOf(s_bob);

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
        assertEq(sourceToken.balanceOf(s_alice), sourceBalanceBefore - amountToSend);
        assertEq(sourceToken.totalSupply(), sourceSupplyBefore - amountToSend);

        vm.selectFork(s_destinationFork);
        assertEq(destinationToken.balanceOf(s_bob), destinationBalanceBefore + amountToSend);
        assertEq(destinationToken.totalSupply(), destinationSupplyBefore + amountToSend);
    }

    function _registerAndSetPool(Register.NetworkDetails memory network, address token, address pool) internal {
        RegistryModuleOwnerCustom(network.registryModuleOwnerCustomAddress).registerAccessControlDefaultAdmin(token);
        ITokenAdminRegistry(network.tokenAdminRegistryAddress).acceptAdminRole(token);
        ITokenAdminRegistry(network.tokenAdminRegistryAddress).setPool(token, pool);
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
