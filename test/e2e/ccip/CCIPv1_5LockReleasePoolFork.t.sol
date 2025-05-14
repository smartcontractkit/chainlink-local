// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, Vm} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "../../../src/ccip/CCIPLocalSimulatorFork.sol";
import {LockReleaseTokenPool, TokenPool} from "@chainlink/contracts-ccip/contracts/pools/LockReleaseTokenPool.sol";
import {RegistryModuleOwnerCustom} from
    "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/TokenAdminRegistry.sol";
import {RateLimiter} from "@chainlink/contracts-ccip/contracts/libraries/RateLimiter.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

import {
    ERC20,
    IERC20
} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/ERC20.sol";
import {OwnerIsCreator} from "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";

contract MockERC20TokenOwner is ERC20, OwnerIsCreator {
    constructor() ERC20("MockERC20Token", "MTK") {}

    function mint(address account, uint256 amount) public onlyOwner {
        _mint(account, amount);
    }
}

contract CCIPv1_5LockReleasePoolFork is Test {
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    MockERC20TokenOwner public mockERC20TokenEthSepolia;
    MockERC20TokenOwner public mockERC20TokenBaseSepolia;
    LockReleaseTokenPool public lockReleaseTokenPoolEthSepolia;
    LockReleaseTokenPool public lockReleaseTokenPoolBaseSepolia;

    Register.NetworkDetails ethSepoliaNetworkDetails;
    Register.NetworkDetails baseSepoliaNetworkDetails;

    uint256 ethSepoliaFork;
    uint256 baseSepoliaFork;

    address alice;

    function setUp() public {
        alice = makeAddr("alice");

        string memory ETHEREUM_SEPOLIA_RPC_URL = vm.envString("ETHEREUM_SEPOLIA_RPC_URL");
        string memory BASE_SEPOLIA_RPC_URL = vm.envString("BASE_SEPOLIA_RPC_URL");
        ethSepoliaFork = vm.createSelectFork(ETHEREUM_SEPOLIA_RPC_URL);
        baseSepoliaFork = vm.createFork(BASE_SEPOLIA_RPC_URL);

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // Step 1) Deploy token on Ethereum Sepolia
        vm.startPrank(alice);
        mockERC20TokenEthSepolia = new MockERC20TokenOwner();
        vm.stopPrank();

        // Step 2) Deploy token on Base Sepolia
        vm.selectFork(baseSepoliaFork);

        vm.startPrank(alice);
        mockERC20TokenBaseSepolia = new MockERC20TokenOwner();
        vm.stopPrank();
    }

    function test_forkSupportNewCCIPToken() public {
        // Step 3) Deploy LockReleaseTokenPool on Ethereum Sepolia
        vm.selectFork(ethSepoliaFork);
        ethSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        address[] memory allowlist = new address[](0);
        uint8 localTokenDecimals = 18;

        vm.startPrank(alice);
        lockReleaseTokenPoolEthSepolia = new LockReleaseTokenPool(
            IERC20(address(mockERC20TokenEthSepolia)),
            localTokenDecimals,
            allowlist,
            ethSepoliaNetworkDetails.rmnProxyAddress,
            true, // acceptLiquidity
            ethSepoliaNetworkDetails.routerAddress
        );
        vm.stopPrank();

        // Step 4) Deploy LockReleaseTokenPool on Base Sepolia
        vm.selectFork(baseSepoliaFork);
        baseSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startPrank(alice);
        lockReleaseTokenPoolBaseSepolia = new LockReleaseTokenPool(
            IERC20(address(mockERC20TokenBaseSepolia)),
            localTokenDecimals,
            allowlist,
            baseSepoliaNetworkDetails.rmnProxyAddress,
            true, // acceptLiquidity
            baseSepoliaNetworkDetails.routerAddress
        );
        vm.stopPrank();

        // Step 5) Set the LiquidityManager address and Add liquidity to the pool on Ethereum Sepolia
        vm.selectFork(ethSepoliaFork);
        uint256 amountToMint = 1_000_000;
        uint128 liquidityAmount = 100_000;

        vm.startPrank(alice);
        mockERC20TokenEthSepolia.mint(address(alice), amountToMint);
        mockERC20TokenEthSepolia.approve(address(lockReleaseTokenPoolEthSepolia), liquidityAmount);
        lockReleaseTokenPoolEthSepolia.setRebalancer(address(alice));
        lockReleaseTokenPoolEthSepolia.provideLiquidity(liquidityAmount);
        vm.stopPrank();

        // Step 6) Set the LiquidityManager address and Add liquidity to the pool on Base Sepolia
        vm.selectFork(baseSepoliaFork);

        vm.startPrank(alice);
        mockERC20TokenBaseSepolia.mint(address(alice), amountToMint);
        mockERC20TokenBaseSepolia.approve(address(lockReleaseTokenPoolBaseSepolia), liquidityAmount);
        lockReleaseTokenPoolBaseSepolia.setRebalancer(address(alice));
        lockReleaseTokenPoolBaseSepolia.provideLiquidity(liquidityAmount);
        vm.stopPrank();

        // Step 7) Claim Admin role on Ethereum Sepolia
        vm.selectFork(ethSepoliaFork);

        RegistryModuleOwnerCustom registryModuleOwnerCustomEthSepolia =
            RegistryModuleOwnerCustom(ethSepoliaNetworkDetails.registryModuleOwnerCustomAddress);

        vm.startPrank(alice);
        registryModuleOwnerCustomEthSepolia.registerAdminViaOwner(address(mockERC20TokenEthSepolia));
        vm.stopPrank();

        // Step 8) Claim Admin role on Base Sepolia
        vm.selectFork(baseSepoliaFork);

        RegistryModuleOwnerCustom registryModuleOwnerCustomBaseSepolia =
            RegistryModuleOwnerCustom(baseSepoliaNetworkDetails.registryModuleOwnerCustomAddress);

        vm.startPrank(alice);
        registryModuleOwnerCustomBaseSepolia.registerAdminViaOwner(address(mockERC20TokenBaseSepolia));
        vm.stopPrank();

        // Step 9) Accept Admin role on Ethereum Sepolia
        vm.selectFork(ethSepoliaFork);

        TokenAdminRegistry tokenAdminRegistryEthSepolia =
            TokenAdminRegistry(ethSepoliaNetworkDetails.tokenAdminRegistryAddress);

        vm.startPrank(alice);
        tokenAdminRegistryEthSepolia.acceptAdminRole(address(mockERC20TokenEthSepolia));
        vm.stopPrank();

        // Step 10) Accept Admin role on Base Sepolia
        vm.selectFork(baseSepoliaFork);

        TokenAdminRegistry tokenAdminRegistryBaseSepolia =
            TokenAdminRegistry(baseSepoliaNetworkDetails.tokenAdminRegistryAddress);

        vm.startPrank(alice);
        tokenAdminRegistryBaseSepolia.acceptAdminRole(address(mockERC20TokenBaseSepolia));
        vm.stopPrank();

        // Step 11) Link token to pool on Ethereum Sepolia
        vm.selectFork(ethSepoliaFork);

        vm.startPrank(alice);
        tokenAdminRegistryEthSepolia.setPool(address(mockERC20TokenEthSepolia), address(lockReleaseTokenPoolEthSepolia));
        vm.stopPrank();

        // Step 12) Link token to pool on Base Sepolia
        vm.selectFork(baseSepoliaFork);

        vm.startPrank(alice);
        tokenAdminRegistryBaseSepolia.setPool(
            address(mockERC20TokenBaseSepolia), address(lockReleaseTokenPoolBaseSepolia)
        );
        vm.stopPrank();

        // Step 13) Configure Token Pool on Ethereum Sepolia
        vm.selectFork(ethSepoliaFork);

        vm.startPrank(alice);
        TokenPool.ChainUpdate[] memory chains = new TokenPool.ChainUpdate[](1);
        bytes[] memory remotePoolAddressesEthSepolia = new bytes[](1);
        remotePoolAddressesEthSepolia[0] = abi.encode(address(lockReleaseTokenPoolBaseSepolia));
        chains[0] = TokenPool.ChainUpdate({
            remoteChainSelector: baseSepoliaNetworkDetails.chainSelector,
            remotePoolAddresses: remotePoolAddressesEthSepolia,
            remoteTokenAddress: abi.encode(address(mockERC20TokenBaseSepolia)),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: liquidityAmount, rate: 167}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: liquidityAmount, rate: 167})
        });
        uint64[] memory remoteChainSelectorsToRemove = new uint64[](0);
        lockReleaseTokenPoolEthSepolia.applyChainUpdates(remoteChainSelectorsToRemove, chains);
        vm.stopPrank();

        // Step 14) Configure Token Pool on Base Sepolia
        vm.selectFork(baseSepoliaFork);

        vm.startPrank(alice);
        chains = new TokenPool.ChainUpdate[](1);
        bytes[] memory remotePoolAddressesBaseSepolia = new bytes[](1);
        remotePoolAddressesBaseSepolia[0] = abi.encode(address(lockReleaseTokenPoolEthSepolia));
        chains[0] = TokenPool.ChainUpdate({
            remoteChainSelector: ethSepoliaNetworkDetails.chainSelector,
            remotePoolAddresses: remotePoolAddressesBaseSepolia,
            remoteTokenAddress: abi.encode(address(mockERC20TokenEthSepolia)),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: liquidityAmount, rate: 167}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: liquidityAmount, rate: 167})
        });
        lockReleaseTokenPoolBaseSepolia.applyChainUpdates(remoteChainSelectorsToRemove, chains);
        vm.stopPrank();

        // Step 15) Transfer tokens from Ethereum Sepolia to Base Sepolia
        vm.selectFork(ethSepoliaFork);

        address linkEthSepoliaAddress = ethSepoliaNetworkDetails.linkAddress;
        address routerEthSepoliaAddress = ethSepoliaNetworkDetails.routerAddress;
        ccipLocalSimulatorFork.requestLinkFromFaucet(address(alice), 20 ether);

        uint256 amountToSend = 100;
        Client.EVMTokenAmount[] memory tokenToSendDetails = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount =
            Client.EVMTokenAmount({token: address(mockERC20TokenEthSepolia), amount: amountToSend});
        tokenToSendDetails[0] = tokenAmount;

        vm.startPrank(alice);

        mockERC20TokenEthSepolia.approve(routerEthSepoliaAddress, amountToSend);
        IERC20(linkEthSepoliaAddress).approve(routerEthSepoliaAddress, 20 ether);

        uint256 balanceOfAliceBeforeEthSepolia = mockERC20TokenEthSepolia.balanceOf(alice);

        uint64 destinationChainSelector = baseSepoliaNetworkDetails.chainSelector;
        IRouterClient routerEthSepolia = IRouterClient(routerEthSepoliaAddress);
        routerEthSepolia.ccipSend(
            destinationChainSelector,
            Client.EVM2AnyMessage({
                receiver: abi.encode(address(alice)),
                data: "",
                tokenAmounts: tokenToSendDetails,
                extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})),
                feeToken: linkEthSepoliaAddress
            })
        );

        uint256 balanceOfAliceAfterEthSepolia = mockERC20TokenEthSepolia.balanceOf(alice);
        vm.stopPrank();

        assertEq(balanceOfAliceAfterEthSepolia, balanceOfAliceBeforeEthSepolia - amountToSend);

        ccipLocalSimulatorFork.switchChainAndRouteMessage(baseSepoliaFork);

        uint256 balanceOfAliceAfterBaseSepolia = mockERC20TokenBaseSepolia.balanceOf(alice);
        assertEq(balanceOfAliceAfterBaseSepolia, balanceOfAliceBeforeEthSepolia + amountToSend);
    }
}
