// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Register Contract
/// @notice This contract allows storing and retrieving network details for various chains.
/// @dev Stores network details in a mapping based on chain IDs.
contract Register {
    struct NetworkDetails {
        address verifierProxyAddress;
        address linkAddress;
    }

    /// @notice Mapping to store network details based on chain ID.
    mapping(uint256 chainId => NetworkDetails) internal s_networkDetails;

    /// @notice Constructor to initialize the network details for various chains.
    constructor() {
        // Arbitrum Sepolia
        s_networkDetails[421614] = NetworkDetails({
            verifierProxyAddress: 0x2ff010DEbC1297f19579B4246cad07bd24F2488A,
            linkAddress: 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E
        });

        // Avalanche Fuji
        s_networkDetails[43113] = NetworkDetails({
            verifierProxyAddress: 0x2bf612C65f5a4d388E687948bb2CF842FFb8aBB3,
            linkAddress: 0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846
        });

        // Base Sepolia
        s_networkDetails[84532] = NetworkDetails({
            verifierProxyAddress: 0x8Ac491b7c118a0cdcF048e0f707247fD8C9575f9,
            linkAddress: 0xE4aB69C077896252FAFBD49EFD26B5D171A32410
        });

        // opBNB Testnet
        s_networkDetails[5611] =
            NetworkDetails({verifierProxyAddress: 0x001225Aca0efe49Dbb48233aB83a9b4d177b581A, linkAddress: address(0)});

        // Soneium Minato Testnet
        s_networkDetails[1946] = NetworkDetails({
            verifierProxyAddress: 0x26603bAC5CE09DAE5604700B384658AcA13AD6ae,
            linkAddress: 0x7ea13478Ea3961A0e8b538cb05a9DF0477c79Cd2
        });
    }

    /**
     * @notice Retrieves network details for a given chain ID.
     *
     * @param chainId - The ID of the chain to get the details for.
     * @return networkDetails - The network details for the specified chain ID.
     */
    function getNetworkDetails(uint256 chainId) external view returns (NetworkDetails memory networkDetails) {
        networkDetails = s_networkDetails[chainId];
    }

    /**
     * @notice Sets the network details for a given chain ID.
     *
     * @param chainId - The ID of the chain to set the details for.
     * @param networkDetails - The network details to set for the specified chain ID.
     */
    function setNetworkDetails(uint256 chainId, NetworkDetails memory networkDetails) external {
        s_networkDetails[chainId] = networkDetails;
    }
}
