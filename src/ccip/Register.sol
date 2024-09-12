// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

/// @title Register Contract
/// @notice This contract allows storing and retrieving network details for various chains.
/// @dev Stores network details in a mapping based on chain IDs.
contract Register {
    struct NetworkDetails {
        uint64 chainSelector;
        address routerAddress;
        address linkAddress;
        address wrappedNativeAddress;
        address ccipBnMAddress;
        address ccipLnMAddress;
        address rmnProxyAddress;
        address tokenAdminRegistryAddress;
        address registryModuleOwnerCustomAddress;
    }

    /// @notice Mapping to store network details based on chain ID.
    mapping(uint256 chainId => NetworkDetails) internal s_networkDetails;

    /// @notice Constructor to initialize the network details for various chains.
    constructor() {
        // Ethereum Sepolia
        s_networkDetails[11155111] = NetworkDetails({
            chainSelector: 16015286601757825753,
            routerAddress: 0xBc660D95b7c1DE05251047f2cEC6A4D4838406C1,
            linkAddress: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            wrappedNativeAddress: 0x097D90c9d3E0B50Ca60e1ae45F6A81010f9FB534,
            ccipBnMAddress: 0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05,
            ccipLnMAddress: 0x466D489b6d36E7E3b824ef491C225F5830E81cC1,
            rmnProxyAddress: 0x07A61c3293CA5FabDF0B1314FFdD8b41E700A706,
            tokenAdminRegistryAddress: 0x613D50Df3710D9b39bCef92dE5D7b9f8b6B23AB8,
            registryModuleOwnerCustomAddress: 0xC98d407983779aD1b579F3e4325A93961BC79da1
        });
        // Avalanche Fuji
        s_networkDetails[43113] = NetworkDetails({
            chainSelector: 14767482510784806043,
            routerAddress: 0xf85E941163a8B35F48bD8814227665d82Fd4dd65,
            linkAddress: 0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846,
            wrappedNativeAddress: 0xd00ae08403B9bbb9124bB305C09058E32C39A48c,
            ccipBnMAddress: 0xD21341536c5cF5EB1bcb58f6723cE26e8D8E90e4,
            ccipLnMAddress: 0x70F5c5C40b873EA597776DA2C21929A8282A3b35,
            rmnProxyAddress: 0x8F176C89e14D16546139286c44F062a106858656,
            tokenAdminRegistryAddress: 0x68511D2EF4e05f6Ea5c6B7A0c5b9aDa663E92cD3,
            registryModuleOwnerCustomAddress: 0x60bD3718f5334B67C3019ab2df59905039204F77
        });
        // Base Sepolia
        s_networkDetails[84532] = NetworkDetails({
            chainSelector: 10344971235874465080,
            routerAddress: 0xD30A891623872764A08D9BD0CeF3429b88D3946c,
            linkAddress: 0xE4aB69C077896252FAFBD49EFD26B5D171A32410,
            wrappedNativeAddress: 0x4200000000000000000000000000000000000006,
            ccipBnMAddress: 0x88A2d74F47a237a62e7A51cdDa67270CE381555e,
            ccipLnMAddress: 0xA98FA8A008371b9408195e52734b1768c0d1Cb5c,
            rmnProxyAddress: 0x125B2929339812aC3Bb3Ee9D33eb812CE8Bff3Ce,
            tokenAdminRegistryAddress: 0x479e47F5576CbaB2ae66e4C80426c43a0c58a619,
            registryModuleOwnerCustomAddress: 0xb274Cb3342C553B84d6deae1537dCd94C20975e0
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
