import { ethers, network } from "hardhat";
import { requestLinkFromFaucet, requestNativeFromFaucet } from "../data-streams/DataStreamsLocalSimulatorFork";

// 1st Terminal: npx hardhat node
// 2nd Terminal: npx hardhat run ./scripts/examples/DataStreamsConsumerFork.ts --network localhost

async function main() {
    const verifierProxyInterface = new ethers.Interface([
        "function verify(bytes calldata payload, bytes calldata parameterPayload) external payable returns (bytes memory verifierResponse)",
        "function s_feeManager() external view returns (address)"
    ]);

    const feeManagerInterface = new ethers.Interface([
        "function getFeeAndReward(address subscriber, bytes memory unverifiedReport, address quoteAddress) external returns ((address token,uint256 amount) memory, (address token,uint256 amount) memory, uint256)",
        "function i_linkAddress() external view returns (address)",
        "function i_nativeAddress() external view returns (address)",
        "function i_rewardManager() external view returns (address)"
    ]);

    const erc20Interface = new ethers.Interface(["function approve(address spender, uint256 amount) external returns (bool)"]);

    const ARBITRUM_SEPOLIA_RPC_URL = process.env.ARBITRUM_SEPOLIA_RPC_URL;

    await network.provider.request({
        method: "hardhat_reset",
        params: [{
            forking: {
                jsonRpcUrl: ARBITRUM_SEPOLIA_RPC_URL,
                blockNumber: 99556570
            },
        }],
    });

    const [alice] = await ethers.getSigners();

    const UNVERIFIED_INPUT_REPORT = "0x0006f9b553e393ced311551efd30d1decedb63d76ad41737462e2cdbbdff1578000000000000000000000000000000000000000000000000000000004b0b4006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000220000000000000000000000000000000000000000000000000000000000000028001010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000120000359843a543ee2fe414dc14c7e7920ef10f4372990b79d6361cdc0dd1ba7820000000000000000000000000000000000000000000000000000000067407f400000000000000000000000000000000000000000000000000000000067407f4000000000000000000000000000000000000000000000000000001b1fa2a2d6400000000000000000000000000000000000000000000000000016e76dd08b2c34000000000000000000000000000000000000000000000000000000006741d0c00000000000000000000000000000000000000000000000b5c654dd994866cb600000000000000000000000000000000000000000000000b5c6042e4f23a92c400000000000000000000000000000000000000000000000b5c7dc7c8e30df80000000000000000000000000000000000000000000000000000000000000000002f68eeb7e489bef244eb83d56e1b8af210a65363e5ad4407f374e5c06f46db98c36b4181b70329535011ba504fb8e09570c10a6de7f1f138cf322237c72cb0d650000000000000000000000000000000000000000000000000000000000000002648579956ffb863e4ea9470a87bb59b26e91ea893f96c2ab933786e531f2701a06d92b4e896a42d40d19a3b5ba1711d5f00bc262084d7afce44a5bbde3014fe5";

    const EXPECTED_REPORT_DATA = {
        feedId: "0x000359843a543ee2fe414dc14c7e7920ef10f4372990b79d6361cdc0dd1ba782",
        validFromTimestamp: 1732280128,
        observationsTimestamp: 1732280128,
        nativeFee: 29822686516800,
        linkFee: 6446908323867700,
        expiresAt: 1732366528,
        price: 3353151968509396700000n,
        bid: 3353129257778281000000n,
        ask: 3353262200000000000000n
    };

    const verifierProxyAddress = `0x2ff010DEbC1297f19579B4246cad07bd24F2488A`;
    const verifierProxy = new ethers.Contract(verifierProxyAddress, verifierProxyInterface, alice);

    const feeManagerAddress = await verifierProxy.s_feeManager();
    const feeManager = new ethers.Contract(feeManagerAddress, feeManagerInterface, alice);

    const rewardManagerAddress = await feeManager.i_rewardManager();

    const defaultAbiCoder = ethers.AbiCoder.defaultAbiCoder();

    const [, reportData] = defaultAbiCoder.decode(["bytes32[3]", "bytes"], UNVERIFIED_INPUT_REPORT);

    console.log(reportData);

    // Pay for verification in LINK
    let feeTokenAddress = await feeManager.i_linkAddress();

    await requestLinkFromFaucet(feeTokenAddress, alice.address, EXPECTED_REPORT_DATA.linkFee);

    const linkToken = new ethers.Contract(feeTokenAddress, erc20Interface, alice);
    await linkToken.approve(rewardManagerAddress, EXPECTED_REPORT_DATA.linkFee);

    let parameterPayload = defaultAbiCoder.encode(["address"], [feeTokenAddress]);

    await verifierProxy.verify(UNVERIFIED_INPUT_REPORT, parameterPayload); // this must not revert

    // Pay for verification in Native
    feeTokenAddress = await feeManager.i_nativeAddress();
    const gasCosts = ethers.parseEther("0.1");
    await requestNativeFromFaucet(alice.address, EXPECTED_REPORT_DATA.nativeFee + Number(gasCosts));

    parameterPayload = defaultAbiCoder.encode(["address"], [feeTokenAddress]);

    await verifierProxy.verify(UNVERIFIED_INPUT_REPORT, parameterPayload, { value: EXPECTED_REPORT_DATA.nativeFee }); // this must not revert

    // const txData = verifierProxy.interface.encodeFunctionData("verify", [UNVERIFIED_INPUT_REPORT, parameterPayload]);
    // const txResult = await alice.call({
    //     to: verifierProxyAddress,
    //     data: txData,
    // });
    // console.log(txResult);
}


main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
