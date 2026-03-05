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
        address registryModuleOwnerCustomAddress;
        address tokenAdminRegistryAddress;
    }

    /// @notice Mapping to store network details based on chain ID.
    mapping(uint256 chainId => NetworkDetails) internal s_networkDetails;

    /// @notice Constructor to initialize the network details for various chains.
    constructor() {
        // Ethereum
        s_networkDetails[1] = NetworkDetails({
            chainSelector: 5009297550715157269,
            routerAddress: address(0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D),
            linkAddress: address(0x514910771AF9Ca656af840dff83E8264EcF986CA),
            wrappedNativeAddress: address(0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x411dE17f12D1A34ecC7F45f49844626267c75e81),
            registryModuleOwnerCustomAddress: address(0x4855174E9479E211337832E109E7721d43A4CA64),
            tokenAdminRegistryAddress: address(0xb22764f98dD05c789929716D677382Df22C05Cb6)
        });

        // OP
        s_networkDetails[10] = NetworkDetails({
            chainSelector: 3734403246176062136,
            routerAddress: address(0x3206695CaE29952f4b0c22a169725a865bc8Ce0f),
            linkAddress: address(0x350a791Bfc2C21F9Ed5d10980Dad2e2638ffa7f6),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x55b3FCa23EdDd28b1f5B4a3C7975f63EFd2d06CE),
            registryModuleOwnerCustomAddress: address(0xAFEd606Bd2CAb6983fC6F10167c98aaC2173D77f),
            tokenAdminRegistryAddress: address(0x657c42abE4CD8aa731Aec322f871B5b90cf6274F)
        });

        // Cronos
        s_networkDetails[25] = NetworkDetails({
            chainSelector: 1456215246176062136,
            routerAddress: address(0xE26B0A098D861d5C7d9434aD471c0572Ca6EAa67),
            linkAddress: address(0x8c80A01F461f297Df7F9DA3A4f740D7297C8Ac85),
            wrappedNativeAddress: address(0x5C7F8A570d578ED84E63fdFA7b1eE72dEae1AE23),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xd22A59e9b4eA2af16e66487411204224F5003351),
            registryModuleOwnerCustomAddress: address(0x36293c0fbF1872Be5b6cBc65704fB22d41405388),
            tokenAdminRegistryAddress: address(0x32c4634338f1386fdD18E0bD6dF51Ca2Fa56f762)
        });

        // Rootstock
        s_networkDetails[30] = NetworkDetails({
            chainSelector: 11964252391146578476,
            routerAddress: address(0xCe7aFb0BF5F73BfDB5e9E04976eBac2005746bD0),
            linkAddress: address(0x938D84942f5D924070A6bb82F8e56a5E2b3098A4),
            wrappedNativeAddress: address(0x542fDA317318eBF1d3DEAf76E0b632741A7e677d),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x54E38BFA3584415C28228Ed4865Ed4FA5cDD013A),
            registryModuleOwnerCustomAddress: address(0x51e2A24742Db77604B881d6781Ee16B5b8fcBE29),
            tokenAdminRegistryAddress: address(0xad71ac82aCFCbDD27BBd3F3eD2fA24E26E49CBE2)
        });

        // Rootstock Testnet
        s_networkDetails[31] = NetworkDetails({
            chainSelector: 8953668971247136127,
            routerAddress: address(0xfEE82327fC68cE497283159Eb724Ba7427b097e3),
            linkAddress: address(0x39dD98CcCC3a51b2c0007e23517488e363581264),
            wrappedNativeAddress: address(0x09B6Ca5E4496238a1F176aEA6bB607db96C2286E),
            ccipBnMAddress: address(0xEc9c9E6A862BA7aee87731110a01A2f087EC7ECc),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x2c78A454169241ddCa342BED991B5E4222C0bd0D),
            registryModuleOwnerCustomAddress: address(0xaDFb7b14a3eB752b392b69a68bfDD21eAF27466E),
            tokenAdminRegistryAddress: address(0x18825F888230922CdAdA6C7c4AaE70bDbfdF01Ab)
        });

        // XDC Network
        s_networkDetails[50] = NetworkDetails({
            chainSelector: 17673274061779414707,
            routerAddress: address(0x2a9f896660E802c59a3178b2E8CB7FBaCCC04e86),
            linkAddress: address(0xE27dd9BF01B55ce6803c0d81386A04212c718b95),
            wrappedNativeAddress: address(0x951857744785E80e2De051c32EE7b25f9c458C42),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x4e52dD94e9BCfeFE3C78153bDfB0AB1d30687297),
            registryModuleOwnerCustomAddress: address(0x318Ec96df83AccC18B5EAD5D23e0F022F7Eb5503),
            tokenAdminRegistryAddress: address(0xEC1276CA704c612A28cb2C873dEdCEba97F65cED)
        });

        // XDC Apothem Network
        s_networkDetails[51] = NetworkDetails({
            chainSelector: 3017758115101368649,
            routerAddress: address(0x1D0b2edF6b66845872b6cC82C036E3601Cb2Be57),
            linkAddress: address(0xe5e3a4fF1773d043a387b16Ceb3c91cC49bAFD54),
            wrappedNativeAddress: address(0x56408DC41E35d3E8E92A16bc94787438df9387a1),
            ccipBnMAddress: address(0x1350D63CAEc50778A132e1Ab85D43a3B50FD61dD),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xEAB080c724587fFC9F2EFF82e36EE4Fb27774959),
            registryModuleOwnerCustomAddress: address(0xd3e461C55676B10634a5F81b747c324B85686Dd1),
            tokenAdminRegistryAddress: address(0xD610B8f58689de7755947C05342A2DFaC30ebD57)
        });

        // BNB Chain
        s_networkDetails[56] = NetworkDetails({
            chainSelector: 11344663589394136015,
            routerAddress: address(0x34B03Cb9086d7D758AC55af71584F81A598759FE),
            linkAddress: address(0x404460C6A5EdE2D891e8297795264fDe62ADBB75),
            wrappedNativeAddress: address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x9e09697842194f77d315E0907F1Bda77922e8f84),
            registryModuleOwnerCustomAddress: address(0x47Db76c9c97F4bcFd54D8872FDb848Cab696092d),
            tokenAdminRegistryAddress: address(0x736Fd8660c443547a85e4Eaf70A49C1b7Bb008fc)
        });

        // Astar Shibuya
        s_networkDetails[81] = NetworkDetails({
            chainSelector: 6955638871347136141,
            routerAddress: address(0x22aE550d87eBf775E0c1fDc8881121c8A51F5903),
            linkAddress: address(0xe74037112db8807B3B4B3895F5790e5bc1866a29),
            wrappedNativeAddress: address(0xbd5F3751856E11f3e80dBdA567Ef91Eb7e874791),
            ccipBnMAddress: address(0xc49ec0eB4beb48B8Da4cceC51AA9A5bD0D0A4c43),
            ccipLnMAddress: address(0xB9d4e1141E67ECFedC8A8139b5229b7FF2BF16F5),
            rmnProxyAddress: address(0xc96ac0533F240ad52694391583267ACAbc479C07),
            registryModuleOwnerCustomAddress: address(0xB6bD6e3e56a8E28CCbE44b6442cA8b586B964Af8),
            tokenAdminRegistryAddress: address(0x54eBB8F7E81305E1bBdDD03860A9a5D41312bB35)
        });

        // BNB Chain Testnet
        s_networkDetails[97] = NetworkDetails({
            chainSelector: 13264668187771770619,
            routerAddress: address(0xE1053aE1857476f36A3C62580FF9b016E8EE8F6f),
            linkAddress: address(0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06),
            wrappedNativeAddress: address(0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd),
            ccipBnMAddress: address(0xbFA2ACd33ED6EEc0ed3Cc06bF1ac38d22b36B9e9),
            ccipLnMAddress: address(0x79a4Fc27f69323660f5Bfc12dEe21c3cC14f5901),
            rmnProxyAddress: address(0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D),
            registryModuleOwnerCustomAddress: address(0x8Cd87FeAC14D69D770E67Bedf029e6fd3F33D0C7),
            tokenAdminRegistryAddress: address(0xF8f2A4466039Ac8adf9944fD67DBb3bb13888f2B)
        });

        // Gnosis
        s_networkDetails[100] = NetworkDetails({
            chainSelector: 465200170687744372,
            routerAddress: address(0x4aAD6071085df840abD9Baf1697d5D5992bDadce),
            linkAddress: address(0xE2e73A1c69ecF83F464EFCE6A5be353a37cA09b2),
            wrappedNativeAddress: address(0xfc421aD3C883Bf9E7C4f42dE845C4e4405799e73),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xf5e5e1676942520995c1e39aFaC58A75Fe1cd2bB),
            registryModuleOwnerCustomAddress: address(0x1f524a11d89D68a4E4b1c8A195E91Fb1d8f0B56a),
            tokenAdminRegistryAddress: address(0x73BC11423CBF14914998C23B0aFC9BE0cb5B2229)
        });

        // Shibarium
        s_networkDetails[109] = NetworkDetails({
            chainSelector: 3993510008929295315,
            routerAddress: address(0xc2CA5d5C17911e4B838194b51585DdF8fe5116C1),
            linkAddress: address(0x71052BAe71C25C78E37fD12E5ff1101A71d9018F),
            wrappedNativeAddress: address(0xC76F4c819D820369Fb2d7C1531aB3Bb18e6fE8d8),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xD2bdb98dA1Ff575d091CA5b76412C23Cba88CA02),
            registryModuleOwnerCustomAddress: address(0x1f524a11d89D68a4E4b1c8A195E91Fb1d8f0B56a),
            tokenAdminRegistryAddress: address(0x995d2Aa233aBeaCA2a64Edf898AE9F4e01bE15B9)
        });

        // Unichain
        s_networkDetails[130] = NetworkDetails({
            chainSelector: 1923510103922296319,
            routerAddress: address(0x68891f5F96695ECd7dEdBE2289D1b73426ae7864),
            linkAddress: address(0xEF66491eab4bbB582c57b14778afd8dFb70D8A1A),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x2c8De9677b07Cc256228069109D9842f0cB96291),
            registryModuleOwnerCustomAddress: address(0xd8F5e7FAc317c638d2Fe4d07ab3f436ca6b5e5c7),
            tokenAdminRegistryAddress: address(0xAB3Ee2e897cf23c10e76d26aB4674fEFA376bc0d)
        });

        // HashKey Chain Testnet
        s_networkDetails[133] = NetworkDetails({
            chainSelector: 4356164186791070119,
            routerAddress: address(0x1360c71dd2458B6d4A5Ad5946d9011BafA0435d7),
            linkAddress: address(0x8418c4d7e8e17ab90232DC72150730E6c4b84F57),
            wrappedNativeAddress: address(0x2896e619Fa7c831A7E52b87EffF4d671bEc6B262),
            ccipBnMAddress: address(0xB0F91Ce2ECAa3555D4b1fD4489bD9a207a7844f0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x9BbBb1Df7D813c9749d99D3CC3D8087b06A83984),
            registryModuleOwnerCustomAddress: address(0x99653DD5e0a6b655aD82e7F41a816CA666F51AFF),
            tokenAdminRegistryAddress: address(0x732cC8266993dDfc5a91035EBe7afF301Be4e8c3)
        });

        // Polygon
        s_networkDetails[137] = NetworkDetails({
            chainSelector: 4051577828743386545,
            routerAddress: address(0x849c5ED5a80F5B408Dd4969b78c2C8fdf0565Bfe),
            linkAddress: address(0xb0897686c545045aFc77CF20eC7A532E3120E0F1),
            wrappedNativeAddress: address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xf1ceAa46D8d13Cac9fC38aaEF3d3d14754C5A9c2),
            registryModuleOwnerCustomAddress: address(0xc751E86208F0F8aF2d5CD0e29716cA7AD98B5eF5),
            tokenAdminRegistryAddress: address(0x00F027eA6D0fb03256A15E9182B2B9227A4931d8)
        });

        // Monad
        s_networkDetails[143] = NetworkDetails({
            chainSelector: 8481857512324358265,
            routerAddress: address(0x33566fE5976AAa420F3d5C64996641Fc3858CaDB),
            linkAddress: address(0x76f257B1DDA5cC71bee4eF637Fbdde4C801310A9),
            wrappedNativeAddress: address(0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x99dFCa5d88f4D9C023531F4403966b8d61562AcD),
            registryModuleOwnerCustomAddress: address(0xB71513B6c80Adf35B43eACC24DA7A08A806a7f2C),
            tokenAdminRegistryAddress: address(0x11ACd984DD680363117B310f6ebdf78fD6c0195f)
        });

        // Sonic
        s_networkDetails[146] = NetworkDetails({
            chainSelector: 1673871237479749969,
            routerAddress: address(0xB4e1Ff7882474BB93042be9AD5E1fA387949B860),
            linkAddress: address(0x71052BAe71C25C78E37fD12E5ff1101A71d9018F),
            wrappedNativeAddress: address(0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x60536Ef486DB5E0e1771874E31485c12e3c2844f),
            registryModuleOwnerCustomAddress: address(0xb0112a2723D9D6CB5194580701A93B1eb67846D2),
            tokenAdminRegistryAddress: address(0x2961Cb47b5111F38d75f415c21ceB4120ddd1b69)
        });

        // Shibarium Puppynet
        s_networkDetails[157] = NetworkDetails({
            chainSelector: 17833296867764334567,
            routerAddress: address(0x449E234FEDF3F907b9E9Dd6BAf1ddc36664097E5),
            linkAddress: address(0x44637eEfD71A090990f89faEC7022fc74B2969aD),
            wrappedNativeAddress: address(0x41c3F37587EBcD46C0F85eF43E38BcfE1E70Ab56),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x8d677784DA3707e57aC0306464552560E05dBCD7),
            registryModuleOwnerCustomAddress: address(0xBB54D6097Ed013eB49509404efA665ee17f247c4),
            tokenAdminRegistryAddress: address(0x5B3BA3d2Dbe9565c2905fbB81776E332a59b6F05)
        });

        // HashKey Chain
        s_networkDetails[177] = NetworkDetails({
            chainSelector: 7613811247471741961,
            routerAddress: address(0xf2Fd62c083F3BF324e99ce157D1a42d7EbA77f1d),
            linkAddress: address(0x71052BAe71C25C78E37fD12E5ff1101A71d9018F),
            wrappedNativeAddress: address(0xB210D2120d57b758EE163cFfb43e73728c471Cf1),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x59F168858472c5ECC217588678F6c378951Bd524),
            registryModuleOwnerCustomAddress: address(0x04c5046A1f4E3fFf094c26dFCAA75eF293932f18),
            tokenAdminRegistryAddress: address(0x4b238f757f842280FeA88A1c2B4186b71eF8BC5E)
        });

        // Mint
        s_networkDetails[185] = NetworkDetails({
            chainSelector: 17164792800244661392,
            routerAddress: address(0x1d86012266F214a368766C2B9329FdCC75B1Ce6b),
            linkAddress: address(0x71052BAe71C25C78E37fD12E5ff1101A71d9018F),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xA84f7c3E7d1025EF1F991110B1956c024bb6Ac99),
            registryModuleOwnerCustomAddress: address(0x3869fE7e385554978Eff78423Fd16B5f0974D260),
            tokenAdminRegistryAddress: address(0xfAb243379A10D8090B32BC706288c2187dbe495C)
        });

        // X Layer
        s_networkDetails[196] = NetworkDetails({
            chainSelector: 3016212468291539606,
            routerAddress: address(0xF2b6Cb7867EB5502C3249dD37D7bc1Cc148e5232),
            linkAddress: address(0x8aF9711B44695a5A081F25AB9903DDB73aCf8FA9),
            wrappedNativeAddress: address(0xe538905cf8410324e03A5A23C1c177a474D59b2b),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x326B01f673681dAd72cd386CCe12FFF717be32cD),
            registryModuleOwnerCustomAddress: address(0xb227f007804c16546Bd054dfED2E7A1fD5437678),
            tokenAdminRegistryAddress: address(0xeCf1eAEE01E82F3388dECD7f4C3792374f3f72F3)
        });

        // opBNB
        s_networkDetails[204] = NetworkDetails({
            chainSelector: 465944652040885897,
            routerAddress: address(0xa3ca4306B9256aAB177C47A18b43593F03378976),
            linkAddress: address(0x99f0d88B81b758AB07E22C7AbA00E0121a882dEA),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xf7adFeB4433E09d4f652EC2c55d39e505F7c8b75),
            registryModuleOwnerCustomAddress: address(0xC2eAfBAD518849e9A5Acd33E687EeAc7306C1dea),
            tokenAdminRegistryAddress: address(0xEfF5D2147F9cAcdedF80C2ee1F5320B01C664bE5)
        });

        // B²
        s_networkDetails[223] = NetworkDetails({
            chainSelector: 5406759801798337480,
            routerAddress: address(0x9C34e9A192d7a4c2cf054668C1122C028C43026c),
            linkAddress: address(0x709229D9587886a1eDFeE6b5cE636E1D70d1cE39),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x1C6Faa5762860261014a355a9efF2bEea2255851),
            registryModuleOwnerCustomAddress: address(0x55aeb80Aa6Ab34aA83E1F387903F8Bb2Aa9e2F2d),
            tokenAdminRegistryAddress: address(0x2e1543255119CfB9D3501E32d7f5B244E59A06F4)
        });

        // Mind Network
        s_networkDetails[228] = NetworkDetails({
            chainSelector: 11690709103138290329,
            routerAddress: address(0x3E13485E767D53f938cD4AF502111d3fF8726A2D),
            linkAddress: address(0xd8A9246e84903e82CA01e42774b01A7CdD465BFa),
            wrappedNativeAddress: address(0x3902228D6A3d2Dc44731fD9d45FeE6a61c722D0b),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x4F26203d04A57A73df795DBed362d3A8d5C34D0c),
            registryModuleOwnerCustomAddress: address(0x7bc6fB227983Ad829dF8b210407A589F2EB34f64),
            tokenAdminRegistryAddress: address(0x469169915210462F5e01EFBE0822Cf7079F9306b)
        });

        // Lens
        s_networkDetails[232] = NetworkDetails({
            chainSelector: 5608378062013572713,
            routerAddress: address(0x498F3feBAd3ff75e05b7847B37a301fc2DA6fDC0),
            linkAddress: address(0x6e970e8d6758164798290c8db1D79a527ca6e1B2),
            wrappedNativeAddress: address(0x6bDc36E20D267Ff0dd6097799f82e78907105e2F),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xE187a792bbf76232A307d8E44615973C849E25A0),
            registryModuleOwnerCustomAddress: address(0xfCe3246A7Cc4Ae9E529836F584843fcCB73F736D),
            tokenAdminRegistryAddress: address(0xdD98482Ec0cfEFfe14EAb750A9c484F9D5d07380)
        });

        // Tac
        s_networkDetails[239] = NetworkDetails({
            chainSelector: 5936861837188149645,
            routerAddress: address(0x966519C334D895121B61584CAdeBc15571b62983),
            linkAddress: address(0xc2BE2F77562A6676098e8D363B9d8A33Ea009D4e),
            wrappedNativeAddress: address(0xB63B9f0eb4A6E6f191529D71d4D88cc8900Df2C9),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xbDCb06538A5f4F5aCC69bb0B7548d314d3c1A8Fd),
            registryModuleOwnerCustomAddress: address(0x313F663E79ef202251a28F0252c254842D5ABC6a),
            tokenAdminRegistryAddress: address(0xd31dB306E5D79F0018Ac92e08492284201493EA1)
        });

        // Cronos zkEVM Testnet
        s_networkDetails[240] = NetworkDetails({
            chainSelector: 16487132492576884721,
            routerAddress: address(0xFeFC5B70DA3297A8470e4D0D2Ea85E0F63bA6b0c),
            linkAddress: address(0xB96217A159cB11Bc51E87c8CAe46C7dF8826A827),
            wrappedNativeAddress: address(0xeD73b53197189BE3Ff978069cf30eBc28a8B5837),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xb776AF2E561Dd8720148D56C7316fDA56B56b9C8),
            registryModuleOwnerCustomAddress: address(0xbF7Fa3d397a92cE20Cd6Aa5376F0A4e41eD3f1b4),
            tokenAdminRegistryAddress: address(0x314B7a51b7472B7F3A998AeA30Cc4Aab731063C8)
        });

        // Fraxtal
        s_networkDetails[252] = NetworkDetails({
            chainSelector: 1462016016387883143,
            routerAddress: address(0x4bdF20477744Ec5F9DE738b5cC9ACd01763905ee),
            linkAddress: address(0xd6A6ba37fAaC229B9665E86739ca501401f5a940),
            wrappedNativeAddress: address(0xFc00000000000000000000000000000000000002),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x889b5Ada2Ce451ED68C5e1b40B8236C3448ff681),
            registryModuleOwnerCustomAddress: address(0xdd8aF6046349EDFD40123E0b616286cEC08010ed),
            tokenAdminRegistryAddress: address(0x6724621d8A560A84E4B6012c4bAA0eA6fF47B9DF)
        });

        // Hedera
        s_networkDetails[295] = NetworkDetails({
            chainSelector: 3229138320728879060,
            routerAddress: address(0x87b400B4d4F5Fe2Fdb6FBEa66C38003ced565b76),
            linkAddress: address(0x7Ce6bb2Cc2D3Fd45a974Da6a0F29236cb9513a98),
            wrappedNativeAddress: address(0xb1F616b8134F602c3Bb465fB5b5e6565cCAd37Ed),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x09d9c9a2Ba147654fB40e217B68f2874775271b9),
            registryModuleOwnerCustomAddress: address(0x1d952d2f6eE86Ef4940Fa648aA7477c8fF175F09),
            tokenAdminRegistryAddress: address(0xC9efBD4f73C37aE1573806030A4146e1E72EADc1)
        });

        // Hedera Testnet
        s_networkDetails[296] = NetworkDetails({
            chainSelector: 222782988166878823,
            routerAddress: address(0x802C5F84eAD128Ff36fD6a3f8a418e339f467Ce4),
            linkAddress: address(0x90a386d59b9A6a4795a011e8f032Fc21ED6FEFb6),
            wrappedNativeAddress: address(0xb1F616b8134F602c3Bb465fB5b5e6565cCAd37Ed),
            ccipBnMAddress: address(0x01Ac06943d2B8327a7845235Ef034741eC1Da352),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x0Df355104424BABfb2404600A4258CfE140a78Cf),
            registryModuleOwnerCustomAddress: address(0xf76cE612250eeEb8889F49FBCB11f1c2705305F6),
            tokenAdminRegistryAddress: address(0xA6643e4f53ceABad16970e8592D4eF7fea49260a)
        });

        // ZKsync Sepolia
        s_networkDetails[300] = NetworkDetails({
            chainSelector: 6898391096552792247,
            routerAddress: address(0xA1fdA8aa9A8C4b945C45aD30647b01f07D7A0B16),
            linkAddress: address(0x23A1aFD896c8c8876AF46aDc38521f4432658d1e),
            wrappedNativeAddress: address(0x4317b2eCD41851173175005783322D29E9bAee9E),
            ccipBnMAddress: address(0xFf6d0c1518A8104611f482eb2801CaF4f13c9dEb),
            ccipLnMAddress: address(0xBf8eA19505ab7Eb266aeD435B11bd56321BFB5c5),
            rmnProxyAddress: address(0x3DA20FD3D8a8f8c1f1A5fD03648147143608C467),
            registryModuleOwnerCustomAddress: address(0x57Fe4Ed8DF1c044f7E6860415A8aa61eE7597657),
            tokenAdminRegistryAddress: address(0xc7777f12258014866c677Bdb679D0b007405b7DF)
        });

        // ZKsync
        s_networkDetails[324] = NetworkDetails({
            chainSelector: 1562403441176082196,
            routerAddress: address(0x748Fd769d81F5D94752bf8B0875E9301d0ba71bB),
            linkAddress: address(0x52869bae3E091e36b0915941577F2D47d8d8B534),
            wrappedNativeAddress: address(0x5AEa5775959fBC2557Cc8789bC1bf90A239D9a91),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x2aBB46A2D32220b8801CE96CAbC32dd2dA7b7B20),
            registryModuleOwnerCustomAddress: address(0x55231e520F09D53ef836CE9477011C7057a70bd6),
            tokenAdminRegistryAddress: address(0x100a47C9DB342884E3314B91cec076BbAC8e619c)
        });

        // Cronos Testnet
        s_networkDetails[338] = NetworkDetails({
            chainSelector: 2995292832068775165,
            routerAddress: address(0xa0F5f5867F528CCc0f9bCc5225063b4A38b5dEBd),
            linkAddress: address(0x2896e619Fa7c831A7E52b87EffF4d671bEc6B262),
            wrappedNativeAddress: address(0x5C50653Ada833D649a718ba4D1Fb9e2EE49c202d),
            ccipBnMAddress: address(0x028E1B6f424c5A96E4bD5e1bbaB8b3C9088e5D39),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x967C605BFF8B9f7a4866ac9d1Ecc660F9CAd08Af),
            registryModuleOwnerCustomAddress: address(0xAA3450998528E43322698a914D0b756B98292A3b),
            tokenAdminRegistryAddress: address(0x58A89590d10BA6553760ca81E66Ce06dfB70429a)
        });

        // Cronos zkEVM
        s_networkDetails[388] = NetworkDetails({
            chainSelector: 8788096068760390840,
            routerAddress: address(0x17b828DF8679D68318f0849C1221AD1760699eCb),
            linkAddress: address(0x61170ca9fB9cF98d4c7d684e07be6D969D59667E),
            wrappedNativeAddress: address(0xC1bF55EE54E16229d9b369a5502Bfe5fC9F20b6d),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xA6f2662523693CFA3Ff2e36e3550ea432864c7DA),
            registryModuleOwnerCustomAddress: address(0x5Fa0fa2f1dE61BddD68dc8902b59Eaa028BE6F57),
            tokenAdminRegistryAddress: address(0x94Fa8b263dEb66fA3e160D408Cd200be8b030609)
        });

        // World Chain
        s_networkDetails[480] = NetworkDetails({
            chainSelector: 2049429975587534727,
            routerAddress: address(0x5fd9E4986187c56826A3064954Cfa2Cf250cfA0f),
            linkAddress: address(0x915b648e994d5f31059B38223b9fbe98ae185473),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x7DE7Ef73cF001ff15b3aA558855D7eeC439d43ab),
            registryModuleOwnerCustomAddress: address(0xb0112a2723D9D6CB5194580701A93B1eb67846D2),
            tokenAdminRegistryAddress: address(0x02Fe6ab4fb0943F58D9D925d1d2cbA9474997Ed0)
        });

        // Astar
        s_networkDetails[592] = NetworkDetails({
            chainSelector: 6422105447186081193,
            routerAddress: address(0x8D5c5CB8ec58285B424C93436189fB865e437feF),
            linkAddress: address(0x31EFB841d5e0b4082F7E1267dab8De1b853f2A9d),
            wrappedNativeAddress: address(0x37795FdD8C165CaB4D6c05771D564d80439CD093),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x7317D216F3DCDa40144a54eC9bA09829a423cb35),
            registryModuleOwnerCustomAddress: address(0x3f2Be15aEA9F68f63ADE10440C6fE00753300b68),
            tokenAdminRegistryAddress: address(0xB98eEd70e3cE8E342B0f770589769E3A6bc20A09)
        });

        // Janction Testnet
        s_networkDetails[679] = NetworkDetails({
            chainSelector: 5059197667603797935,
            routerAddress: address(0x6ddAFdf8bA76AFED73d6e7B599adDE014fA293bC),
            linkAddress: address(0x7311DED199CC28D80E58e81e8589aa160199FCD2),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x2b78139A0580592e2dfa55138c1F2eA5376b1ab4),
            registryModuleOwnerCustomAddress: address(0x95964Bf01b642Ce6Aa8996cC517B9a140fEb1E9f),
            tokenAdminRegistryAddress: address(0x869D08b51D16869899d16a0Ba3eAda58521f8854)
        });

        // Mode Sepolia
        s_networkDetails[919] = NetworkDetails({
            chainSelector: 829525985033418733,
            routerAddress: address(0xc49ec0eB4beb48B8Da4cceC51AA9A5bD0D0A4c43),
            linkAddress: address(0x925a4bfE64AE2bFAC8a02b35F78e60C29743755d),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0xB9d4e1141E67ECFedC8A8139b5229b7FF2BF16F5),
            ccipLnMAddress: address(0x86f9Eed8EAD1534D87d23FbAB247D764fC725D49),
            rmnProxyAddress: address(0xcbFD5e55619B4EE3E6e7fe3CEb0E78fDf7d82dfc),
            registryModuleOwnerCustomAddress: address(0xd7b86ed053806177718B9e03c63c4Bc501825C00),
            tokenAdminRegistryAddress: address(0xc89d4ff0cb206677a7555e52500879bfab73cC68)
        });

        // Bittensor EVM
        s_networkDetails[964] = NetworkDetails({
            chainSelector: 2135107236357186872,
            routerAddress: address(0xD941fBEcD2b971d0F54b4C34286C95faB52B60B8),
            linkAddress: address(0xf09AFe78d3c7d359b334d7cB88995751F7eC5E13),
            wrappedNativeAddress: address(0x5F3B70e0c089a1e3020B1990823Bc241a7bF3522),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x02A4D69cFfeC00Fbf7F3B60c93e3529Dfc58894d),
            registryModuleOwnerCustomAddress: address(0xcDca5D374e46A6DDDab50bD2D9acB8c796eC35C3),
            tokenAdminRegistryAddress: address(0xe72d25aDd538E8ef9CeF85622eA8912a6CB98Be6)
        });

        // Stable
        s_networkDetails[988] = NetworkDetails({
            chainSelector: 16978377838628290997,
            routerAddress: address(0xECFF67559c0583027A5fbd85136E33bC4D66eeA0),
            linkAddress: address(0x985FB0821Eef0056ec26DD8b33dC61b9415B7F4b),
            wrappedNativeAddress: address(0xB23540d08122C634a839F0143267BeA9936Dd466),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x8A76fe7fA6da27f85a626c5C53730B38D13603d7),
            registryModuleOwnerCustomAddress: address(0x7CcFb2Fa43637b4858Cb1269CF0d64a99e8C668a),
            tokenAdminRegistryAddress: address(0x3c23e6FB09064e9A64829Fa8FEe27Ad19A27Bfa9)
        });

        // HyperEVM
        s_networkDetails[999] = NetworkDetails({
            chainSelector: 2442541497099098535,
            routerAddress: address(0x13b3332b66389B1467CA6eBd6fa79775CCeF65ec),
            linkAddress: address(0x1AC2EE68b8d038C982C1E1f73F596927dd70De59),
            wrappedNativeAddress: address(0x5555555555555555555555555555555555555555),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x07f15e9813FBd007d38CF534133C0838f449ecFA),
            registryModuleOwnerCustomAddress: address(0xe2712A0C09DfB8031857Adb8D73Eb04997D271bA),
            tokenAdminRegistryAddress: address(0xcE44363496ABc3a9e53B3F404a740F992D977bDF)
        });

        // Kaia Kairos
        s_networkDetails[1001] = NetworkDetails({
            chainSelector: 2624132734533621656,
            routerAddress: address(0x41477416677843fCE577748D2e762B6638492755),
            linkAddress: address(0xAF3243f975afe2269Da8Ffa835CA3A8F8B6A5A36),
            wrappedNativeAddress: address(0xF04fcEC93DEB6191B704a0ec5d0FFF2A8B2c39be),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x0a57d85E0CE3AafB22079A4c18B4Eb6D3B88BA46),
            registryModuleOwnerCustomAddress: address(0x68cFC03A4607fFA9C1017e0a3739a9C304097b80),
            tokenAdminRegistryAddress: address(0xA6c4CfcDfAaAabeE20C50A6aDa130608cf9D3CC8)
        });

        // Metis Andromeda
        s_networkDetails[1088] = NetworkDetails({
            chainSelector: 8805746078405598895,
            routerAddress: address(0x7b9FB8717D306e2e08ce2e1Efa81F026bf9AD13c),
            linkAddress: address(0xd2FE54D1E5F568eB710ba9d898Bf4bD02C7c0353),
            wrappedNativeAddress: address(0x75cb093E4D61d2A2e65D8e0BBb01DE8d89b53481),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xd99cc1d64027E07Cd2AaE871E16bb32b8F401998),
            registryModuleOwnerCustomAddress: address(0xE939C02E92e9E66d1F0D8E4F099E7d3d269a8a11),
            tokenAdminRegistryAddress: address(0x3af897541eB03927c7431bF68884A6C2C23b683f)
        });

        // Polygon zkEVM
        s_networkDetails[1101] = NetworkDetails({
            chainSelector: 4348158687435793198,
            routerAddress: address(0xA9999937159B293c72e2367Ce314cb3544e7C1a3),
            linkAddress: address(0xdB7A504CF869484dd6aC5FaF925c8386CBF7573D),
            wrappedNativeAddress: address(0x4F9A0e7FD2Bf6067db6994CF12E4495Df938E6e9),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x272fB92E5D43ffcCEb56bBE5b2D7B88a86235c48),
            registryModuleOwnerCustomAddress: address(0xb227f007804c16546Bd054dfED2E7A1fD5437678),
            tokenAdminRegistryAddress: address(0xe87fB6c46DCAADA001681819d2bD3c64f58D8963)
        });

        // Wemix
        s_networkDetails[1111] = NetworkDetails({
            chainSelector: 5142893604156789321,
            routerAddress: address(0x7798b795Fde864f4Cd1b124a38Ba9619B7F8A442),
            linkAddress: address(0x80f1FcdC96B55e459BF52b998aBBE2c364935d69),
            wrappedNativeAddress: address(0x7D72b22a74A216Af4a002a1095C8C707d6eC1C5f),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x2375959c6571AC7a83c164C6FCcbd09E7782773d),
            registryModuleOwnerCustomAddress: address(0xF549af21578Cfe2385FFD3488B3039fd9e52f006),
            tokenAdminRegistryAddress: address(0xE993e046AC50659800a91Bab0bd2daBF59CbD171)
        });

        // Wemix Testnet
        s_networkDetails[1112] = NetworkDetails({
            chainSelector: 9284632837123596123,
            routerAddress: address(0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D),
            linkAddress: address(0x3580c7A817cCD41f7e02143BFa411D4EeAE78093),
            wrappedNativeAddress: address(0xbE3686643c05f00eC46e73da594c78098F7a9Ae7),
            ccipBnMAddress: address(0xF4E4057FbBc86915F4b2d63EEFFe641C03294ffc),
            ccipLnMAddress: address(0xcb342aE3D65E3fEDF8F912B0432e2B8F88514d5D),
            rmnProxyAddress: address(0xA930c1E0fF1E1005E8Ef569Aa81e6EEbf466b1c3),
            registryModuleOwnerCustomAddress: address(0x76c00B055414de203B79B4955E28119BF459033e),
            tokenAdminRegistryAddress: address(0xecf484BFcC51F24fcB31056c262A021bAf688D9B)
        });

        // Core Testnet
        s_networkDetails[1114] = NetworkDetails({
            chainSelector: 4264732132125536123,
            routerAddress: address(0xded0EE188Fe8F1706D9049e29C82081A5ebEcb2F),
            linkAddress: address(0x6C475841d1D7871940E93579E5DBaE01634e17aA),
            wrappedNativeAddress: address(0x7Ce5fCfFd1296d870b3578809B31D8CA8bF5aC3d),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xF39a1260F4E3345D810e1b8aA569200e1D27A998),
            registryModuleOwnerCustomAddress: address(0x13d13E0BBf0387c0e9C6beb73D0593d2FFc1F24d),
            tokenAdminRegistryAddress: address(0x2c99403fDB26F654c410D81264033faE289fa7Ea)
        });

        // Core
        s_networkDetails[1116] = NetworkDetails({
            chainSelector: 1224752112135636129,
            routerAddress: address(0xF7Cc8b0B5263A74AFBb1a2ac87FfF1CF7E62152f),
            linkAddress: address(0x3902228D6A3d2Dc44731fD9d45FeE6a61c722D0b),
            wrappedNativeAddress: address(0x40375C92d9FAf44d2f9db9Bd9ba41a3317a2404f),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x1e9B034c67B6eA4cB819aA8BE4E84cff2d5417fb),
            registryModuleOwnerCustomAddress: address(0x50056397CF6ccF50D1748e95c32EC361951ee6F9),
            tokenAdminRegistryAddress: address(0x4D2B43c60f3e476Ee94637C4e3be844FC9a70012)
        });

        // B² Testnet
        s_networkDetails[1123] = NetworkDetails({
            chainSelector: 1948510578179542068,
            routerAddress: address(0x34A49Eb641daF64d61be00Aa7F759f8225351101),
            linkAddress: address(0x436a1907D9e6a65E6db73015F08f9C66F6B63E45),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0x0643fD73C261eC4B369C3a8C5c0eC8c57485E32d),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x2ce782d1B03CF45F003685614AFaD6495FAf70D4),
            registryModuleOwnerCustomAddress: address(0x9a3F1b6Fb4007413078352c5b25C2814aD5732BC),
            tokenAdminRegistryAddress: address(0xfCaaFD5157aae3cAE886318a0D104D0B19fEEaA1)
        });

        // Lisk
        s_networkDetails[1135] = NetworkDetails({
            chainSelector: 15293031020466096408,
            routerAddress: address(0x0145c1fbA8a16128c1061eB9CE7eC3cadb8e30c7),
            linkAddress: address(0x71052BAe71C25C78E37fD12E5ff1101A71d9018F),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x193e4f6c1A2FD8fa167c8a6e8E05564402DF6890),
            registryModuleOwnerCustomAddress: address(0x15C03488B29e27d62BAf10E30b0c474bf60E0264),
            tokenAdminRegistryAddress: address(0x98acD723D0E9C13d09Df4619Abec729F3434a10a)
        });

        // Unichain Sepolia
        s_networkDetails[1301] = NetworkDetails({
            chainSelector: 14135854469784514356,
            routerAddress: address(0x5b7D7CDf03871dc9Eb00830B027e70A75bd3DC95),
            linkAddress: address(0xda40816f278Cd049c137F6612822D181065EBfB4),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0x6122841A203d34Cd3087c3C19d04d101F6FaF8e8),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x6dFD89Ff6bDa2EA420Dfe6Cc57E7e1F9cf610925),
            registryModuleOwnerCustomAddress: address(0x07d59512C970D0Df9D7d82AfC5996e822E000539),
            tokenAdminRegistryAddress: address(0xf2d17820416B692c52515A828B8A26d2f22cafce)
        });

        // Sei Testnet
        s_networkDetails[1328] = NetworkDetails({
            chainSelector: 1216300075444106652,
            routerAddress: address(0x59F5222c5d77f8D3F56e34Ff7E75A05d2cF3a98A),
            linkAddress: address(0xA9d21ed8260DE08fF39DC5e7B65806d4e1CB817B),
            wrappedNativeAddress: address(0x3921eA6Cf927BE80211Bb57f19830700285b0AdA),
            ccipBnMAddress: address(0x271F22d029c6edFc9469faE189C4F43E457F257C),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x754aBd2496Bea05ceDE80Df8bE530f6132208c41),
            registryModuleOwnerCustomAddress: address(0x28217C5dd0718e9f8EB301b28E32eFd13D71308A),
            tokenAdminRegistryAddress: address(0xDF27EE0050C2D3831089B14aCC465aBF9fD12C64)
        });

        // Sei Network
        s_networkDetails[1329] = NetworkDetails({
            chainSelector: 9027416829622342829,
            routerAddress: address(0xAba60dA7E88F7E8f5868C2B6dE06CB759d693af0),
            linkAddress: address(0x71052BAe71C25C78E37fD12E5ff1101A71d9018F),
            wrappedNativeAddress: address(0xE30feDd158A2e3b13e9badaeABaFc5516e95e8C7),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x32C67585dA17839245c75D80d36c8CBD7d35E1a5),
            registryModuleOwnerCustomAddress: address(0x258Fc917b8de98b4aA0d38776E95dcce9e7EC8aC),
            tokenAdminRegistryAddress: address(0x910a46cA93E8086BF1d7D65190eE6AEe5256Bd61)
        });

        // Pharos Mainnet
        s_networkDetails[1672] = NetworkDetails({
            chainSelector: 7801139999541420232,
            routerAddress: address(0x4e52dD94e9BCfeFE3C78153bDfB0AB1d30687297),
            linkAddress: address(0x51e2A24742Db77604B881d6781Ee16B5b8fcBE29),
            wrappedNativeAddress: address(0x52C48d4213107b20bC583832b0d951FB9CA8F0B0),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xF4486d70EBED800204898Ec99C812661551471dC),
            registryModuleOwnerCustomAddress: address(0xE27dd9BF01B55ce6803c0d81386A04212c718b95),
            tokenAdminRegistryAddress: address(0xB79791184973589c38e114D43Eb8E4588C283A18)
        });

        // Mint Sepolia
        s_networkDetails[1687] = NetworkDetails({
            chainSelector: 10749384167430721561,
            routerAddress: address(0x6Ce68Fb8eA7376d5c84de5486dE46286F6Dd3e36),
            linkAddress: address(0x7ECBE3416d92E8d79C8e5d8EB8Aad5DdEdAa0237),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0x56408DC41E35d3E8E92A16bc94787438df9387a1),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x00b5C67a12F0B7fe9387A94284d94D133Ca85e0c),
            registryModuleOwnerCustomAddress: address(0x811652BfD76D678CD798f2D83d437DCcEC336E1c),
            tokenAdminRegistryAddress: address(0xD2820Aad3FC3544491A8FD58B433721Ec8a2304a)
        });

        // Metal L2 Testnet
        s_networkDetails[1740] = NetworkDetails({
            chainSelector: 6286293440461807648,
            routerAddress: address(0xB6F0d42A356aD4DC890BCD3EdCAFb1df13a30777),
            linkAddress: address(0x7ECBE3416d92E8d79C8e5d8EB8Aad5DdEdAa0237),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0xbD6F12f358D8ee3b35B0AD612450a186bA866B72),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x587e5Db25504ed21Fac9D1aED52e48467d4B71Fe),
            registryModuleOwnerCustomAddress: address(0x09ED6dC4d7cF091A1f9579FACA0d3f485A1c367B),
            tokenAdminRegistryAddress: address(0x2FEAeE6E125791ef86d8b07DBf3ede1680434ea6)
        });

        // Metal L2
        s_networkDetails[1750] = NetworkDetails({
            chainSelector: 13447077090413146373,
            routerAddress: address(0x020c61ECEEE0E5DC32F2503AbB6E070fa0EbBfaA),
            linkAddress: address(0x587d19DDF735D6B536aAdB1a2A92938eB23B8d5C),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x87E84fc7cBD63D7e8653C660De09Fe48AB0276a8),
            registryModuleOwnerCustomAddress: address(0x258Fc917b8de98b4aA0d38776E95dcce9e7EC8aC),
            tokenAdminRegistryAddress: address(0xc41640B959Ca2A62b9293509202D8615dC293634)
        });

        // Soneium
        s_networkDetails[1868] = NetworkDetails({
            chainSelector: 12505351618335765396,
            routerAddress: address(0x8C8B88d827Fe14Df2bc6392947d513C86afD6977),
            linkAddress: address(0x32D8F819C8080ae44375F8d383Ffd39FC642f3Ec),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x3117f515D763652A32d3D6D447171ea7c9d57218),
            registryModuleOwnerCustomAddress: address(0x2c3D51c7B454cB045C8cEc92d2F9E717C7519106),
            tokenAdminRegistryAddress: address(0x5ba21F6824400B91F232952CA6d7c8875C1755a4)
        });

        // Soneium Minato
        s_networkDetails[1946] = NetworkDetails({
            chainSelector: 686603546605904534,
            routerAddress: address(0x443a1bce545d56E2c3f20ED32eA588395FFce0f4),
            linkAddress: address(0x7ea13478Ea3961A0e8b538cb05a9DF0477c79Cd2),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x6172F4f60eEE3876cF83318DEe4477BfAf15Ffd3),
            registryModuleOwnerCustomAddress: address(0xe06fE3AEfef3a27b8BF0edd5ae834B006EdE3aa1),
            tokenAdminRegistryAddress: address(0xD2334a6f4f79CE462193EAcB89eB2c29Ae552750)
        });

        // Ronin
        s_networkDetails[2020] = NetworkDetails({
            chainSelector: 6916147374840168594,
            routerAddress: address(0x46527571D5D1B68eE7Eb60B18A32e6C60DcEAf99),
            linkAddress: address(0x3902228D6A3d2Dc44731fD9d45FeE6a61c722D0b),
            wrappedNativeAddress: address(0xe514d9DEB7966c8BE0ca922de8a064264eA6bcd4),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xceA253a8c2BB995054524d071498281E89aACD59),
            registryModuleOwnerCustomAddress: address(0xC6a4854eeB493224d5f9485E12Dd3A81f22EEE14),
            tokenAdminRegistryAddress: address(0x90e83d532A4aD13940139c8ACE0B93b0DdbD323a)
        });

        // Memento Testnet
        s_networkDetails[2129] = NetworkDetails({
            chainSelector: 12168171414969487009,
            routerAddress: address(0xEAB080c724587fFC9F2EFF82e36EE4Fb27774959),
            linkAddress: address(0xe5e3a4fF1773d043a387b16Ceb3c91cC49bAFD54),
            wrappedNativeAddress: address(0x85Be6b6ff4e61C3bEB0Fb73a2A9dC3A80e279c86),
            ccipBnMAddress: address(0x62325603b3550CbF763cb47F9Fe081dD977e728a),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x6D5035E99D19b436814BFBA65065EfFE2DF34726),
            registryModuleOwnerCustomAddress: address(0x23a5084Fa78104F3DF11C63Ae59fcac4f6AD9DeE),
            tokenAdminRegistryAddress: address(0x995ab3eC29E1660A93cFddAA19C710A1b5afCCc9)
        });

        // Kroma Sepolia
        s_networkDetails[2358] = NetworkDetails({
            chainSelector: 5990477251245693094,
            routerAddress: address(0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D),
            linkAddress: address(0xa75cCA5b404ec6F4BB6EC4853D177FE7057085c8),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000001),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0x835fcBB6770E1246CfCf52F83cDcec3177d0bb6b),
            rmnProxyAddress: address(0xA930c1E0fF1E1005E8Ef569Aa81e6EEbf466b1c3),
            registryModuleOwnerCustomAddress: address(0x683995A22b3654556E9EeA29C0b9df973be6D549),
            tokenAdminRegistryAddress: address(0xaE669d8217c00b02Fb7a7d9902c897745F4f4c83)
        });

        // TAC Saint Petersburg
        s_networkDetails[2391] = NetworkDetails({
            chainSelector: 9488606126177218005,
            routerAddress: address(0x1D0b2edF6b66845872b6cC82C036E3601Cb2Be57),
            linkAddress: address(0xe5e3a4fF1773d043a387b16Ceb3c91cC49bAFD54),
            wrappedNativeAddress: address(0xCf61405b7525F09f4E7501fc831fE7cbCc823d4c),
            ccipBnMAddress: address(0x4Bc8740F54eC7CD6738f19ff00438bFE3DCbceB3),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xEAB080c724587fFC9F2EFF82e36EE4Fb27774959),
            registryModuleOwnerCustomAddress: address(0xd3e461C55676B10634a5F81b747c324B85686Dd1),
            tokenAdminRegistryAddress: address(0xD610B8f58689de7755947C05342A2DFaC30ebD57)
        });

        // Polygon zkEVM Cardona
        s_networkDetails[2442] = NetworkDetails({
            chainSelector: 1654667687261492630,
            routerAddress: address(0x91A7f913EEF5E3058AD1Bf8842C294f7219C7271),
            linkAddress: address(0x5576815a38A3706f37bf815b261cCc7cCA77e975),
            wrappedNativeAddress: address(0x1CE28d5C81B229c77C5651feB49c4C489f8c52C4),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0xA4C9e2108ca478DE0B91c7D9Ba034bbc93C22Ecc),
            rmnProxyAddress: address(0x174813BA5102bD363924bABBeEcE4865FBC426BF),
            registryModuleOwnerCustomAddress: address(0xb7E0D638cE82ba6AdC88D7FeBD5E06e549bAC4b6),
            tokenAdminRegistryAddress: address(0x6bdFA65ccd2Aba2913De2c0a588C317Dc651d9C3)
        });

        // Fraxtal Testnet
        s_networkDetails[2522] = NetworkDetails({
            chainSelector: 8901520481741771655,
            routerAddress: address(0x0a355FC36C10007D3059637f0cd7cFfBE845241a),
            linkAddress: address(0xb192c5Fb8e33694F0CFD4357806a63dc59feEBEF),
            wrappedNativeAddress: address(0xFC00000000000000000000000000000000000006),
            ccipBnMAddress: address(0x6122841A203d34Cd3087c3C19d04d101F6FaF8e8),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x9496599d8C12955028E615B26D014c1387E771cb),
            registryModuleOwnerCustomAddress: address(0x9F6a9ac622384d0e11E8e018CB0a77B2B81091Ee),
            tokenAdminRegistryAddress: address(0x9f9fd4eD94e95DbaDf34f582CB1b9245A4CF2Cc8)
        });

        // Abstract
        s_networkDetails[2741] = NetworkDetails({
            chainSelector: 3577778157919314504,
            routerAddress: address(0x09521B0B5BB2d4406124c0207Cf551829B45f84d),
            linkAddress: address(0x2Ea38D6cDb6774992d4A62fe622f4405663729Dd),
            wrappedNativeAddress: address(0x3439153EB7AF838Ad19d56E1571FBD09333C2809),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x2edAc8B8928c4e1Ed559e619b6A8a4aaCe9Ef18A),
            registryModuleOwnerCustomAddress: address(0xB79791184973589c38e114D43Eb8E4588C283A18),
            tokenAdminRegistryAddress: address(0x7EEdf2DBC74924Cb1f23fC8845CD35bF18b697de)
        });

        // Morph
        s_networkDetails[2818] = NetworkDetails({
            chainSelector: 18164309074156128038,
            routerAddress: address(0x3201a20D2a33820C0DaC8Bc93C4819755C2a8c7F),
            linkAddress: address(0x76a443768A5e3B8d1AED0105FC250877841Deb40),
            wrappedNativeAddress: address(0x5300000000000000000000000000000000000011),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x15C03488B29e27d62BAf10E30b0c474bf60E0264),
            registryModuleOwnerCustomAddress: address(0x9A82E768C885DEF7C4b47451Fd4Db53d8B21ed07),
            tokenAdminRegistryAddress: address(0xEfd5fEFEdE55B5C41B8fa0d171a79ba5BeadD2Aa)
        });

        // Morph Hoodi
        s_networkDetails[2910] = NetworkDetails({
            chainSelector: 1064004874793747259,
            routerAddress: address(0xd1CBe8dF481C7a78AaaAfB0466814d13d93bd9b7),
            linkAddress: address(0xe5e3a4fF1773d043a387b16Ceb3c91cC49bAFD54),
            wrappedNativeAddress: address(0x5300000000000000000000000000000000000011),
            ccipBnMAddress: address(0x69521081Fd90669b59b1Cb3F67a2229D36a7De00),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x9A60462e4CA802E3E945663930Be0d162e662091),
            registryModuleOwnerCustomAddress: address(0x5Dc49Ec54B92F7D493bC8126c0730DA74605cc00),
            tokenAdminRegistryAddress: address(0x65B023D3D4Ea880B835BF2CDE48B296Ee7157EcE)
        });

        // Botanix Testnet
        s_networkDetails[3636] = NetworkDetails({
            chainSelector: 1467223411771711614,
            routerAddress: address(0x8a27438666Ef45093802F869bd146fB183dd5A32),
            linkAddress: address(0x7311DED199CC28D80E58e81e8589aa160199FCD2),
            wrappedNativeAddress: address(0x233631132FD56c8f86D1FC97F0b82420a8d20af3),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x073B0329bEdD96E95462A8d446E8FC3F5A959105),
            registryModuleOwnerCustomAddress: address(0x3C6a0de9aF7051344aAE8b78a0ee4E43e050c7Dd),
            tokenAdminRegistryAddress: address(0xd86b92de626aD63db80AF78B54e5739b6aC8b099)
        });

        // Botanix
        s_networkDetails[3637] = NetworkDetails({
            chainSelector: 4560701533377838164,
            routerAddress: address(0x5EE890c89B5Ae75cBC516Dd53345e38E5B39B664),
            linkAddress: address(0x30e85A5c9525AD9a7A0FA5C74df4Baf0b01aD241),
            wrappedNativeAddress: address(0x0D2437F93Fed6EA64Ef01cCde385FB1263910C56),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x7f1310420E197B491311Ac75bF44e852f796779a),
            registryModuleOwnerCustomAddress: address(0xbDCb06538A5f4F5aCC69bb0B7548d314d3c1A8Fd),
            tokenAdminRegistryAddress: address(0x3eD4752266fF42FECe47dB8BA1249fF3978f3E5E)
        });

        // Merlin
        s_networkDetails[4200] = NetworkDetails({
            chainSelector: 241851231317828981,
            routerAddress: address(0x8Be462D21b05eEeF81a3AA384b7C6CF18597232A),
            linkAddress: address(0x71052BAe71C25C78E37fD12E5ff1101A71d9018F),
            wrappedNativeAddress: address(0xF6D226f9Dc15d9bB51182815b320D3fBE324e1bA),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x225c0187d88e5E42455c4B46078D15283551930B),
            registryModuleOwnerCustomAddress: address(0xE27dd9BF01B55ce6803c0d81386A04212c718b95),
            tokenAdminRegistryAddress: address(0xA51Cdb9154bB0c9Bc3CE25dBf7DE3331B3A1C8E7)
        });

        // Lisk Sepolia
        s_networkDetails[4202] = NetworkDetails({
            chainSelector: 5298399861320400553,
            routerAddress: address(0x78805d2881d233a430983Dbc170990AefDe60C93),
            linkAddress: address(0x6641415a61bCe80D97a715054d1334360Ab833Eb),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0x03B2F16FC12010d2e35055092055674645C38378),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x1e4a4432d4d278992BE84695C3cc20E1e4bD99A0),
            registryModuleOwnerCustomAddress: address(0xd54205E00835B63Db005ADEF8d99E4984601ACAf),
            tokenAdminRegistryAddress: address(0x8e09D700c1246a0e2Eb6169D67fc51c2f618a21A)
        });

        // MegaETH Mainnet
        s_networkDetails[4326] = NetworkDetails({
            chainSelector: 6093540873831549674,
            routerAddress: address(0xfa546248C54939AA6C48279CdC1EAf9A1125c411),
            linkAddress: address(0xee85aEfb15b9489563A6a29891ebe0750AA1A7Ae),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xA27056438FfA1f286AB197488808692F0db93F8B),
            registryModuleOwnerCustomAddress: address(0x1E11bAB3f07fa72312182fFDc460AE45400E6e7b),
            tokenAdminRegistryAddress: address(0xf4a170A36D4C656F614d44453f73308Bdb275196)
        });

        // World Chain Sepolia
        s_networkDetails[4801] = NetworkDetails({
            chainSelector: 5299555114858065850,
            routerAddress: address(0x47693fc188b2c30078F142eadc2C009E8D786E8d),
            linkAddress: address(0xC82Ea35634BcE95C394B6BC00626f827bB0F4801),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0x8fdE0C794fDA5a7A303Ce216f79B9695a7714EcB),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x469f402B75c7679eccac0Afab43aB60A292f1976),
            registryModuleOwnerCustomAddress: address(0xBD04B1B560A30cB3DA471574bB38F069F9C97399),
            tokenAdminRegistryAddress: address(0x5A02ce533FF13f2A069CfACEe49431c017e17aBC)
        });

        // Mantle
        s_networkDetails[5000] = NetworkDetails({
            chainSelector: 1556008542357238666,
            routerAddress: address(0x670052635a9850bb45882Cb2eCcF66bCff0F41B7),
            linkAddress: address(0xfe36cF0B43aAe49fBc5cFC5c0AF22a623114E043),
            wrappedNativeAddress: address(0xfc421aD3C883Bf9E7C4f42dE845C4e4405799e73),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x91E2186E93F0ECeDDCdf9850078F104daB085E79),
            registryModuleOwnerCustomAddress: address(0xf49f81b3d2F2a79b706621FA2D5934136352140c),
            tokenAdminRegistryAddress: address(0x000A744940eB5D857c0d61d97015DFc83107404F)
        });

        // Mantle Sepolia
        s_networkDetails[5003] = NetworkDetails({
            chainSelector: 8236463271206331221,
            routerAddress: address(0xFd33fd627017fEf041445FC19a2B6521C9778f86),
            linkAddress: address(0x22bdEdEa0beBdD7CfFC95bA53826E55afFE9DE04),
            wrappedNativeAddress: address(0x19f5557E23e9914A18239990f6C70D68FDF0deD5),
            ccipBnMAddress: address(0xEA8cA8AE1c54faB8D185FC1fd7C2d70Bee8a417e),
            ccipLnMAddress: address(0xCdeE7708A96479f6D029741144f458B7FA807A6C),
            rmnProxyAddress: address(0xcCB84Ec3F6AFdD2052134f74aaAc95Ae41A7B333),
            registryModuleOwnerCustomAddress: address(0xf76cE612250eeEb8889F49FBCB11f1c2705305F6),
            tokenAdminRegistryAddress: address(0x0F1eE88A582f31d92510E300fc1330AA5a525D51)
        });

        // Superseed
        s_networkDetails[5330] = NetworkDetails({
            chainSelector: 470401360549526817,
            routerAddress: address(0xAD93FBB3A9a077F896e1F57739e43dEd063f181F),
            linkAddress: address(0x41Ccf59e3F30EB624eF8E5Ea34b2da96bee472d9),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x1A99FF887e5bb3962dA97F409487663B5F539799),
            registryModuleOwnerCustomAddress: address(0x1d952d2f6eE86Ef4940Fa648aA7477c8fF175F09),
            tokenAdminRegistryAddress: address(0x7a1874cBc865580c6cbE09af25509dF12A6b4F58)
        });

        // opBNB Testnet
        s_networkDetails[5611] = NetworkDetails({
            chainSelector: 13274425992935471758,
            routerAddress: address(0xD9182959D9771cc77e228cB3caFe671f45A37630),
            linkAddress: address(0x56E16E648c51609A14Eb14B99BAB771Bee797045),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xfd203BE5303939fA8514A3D9CDe38e31877317B7),
            registryModuleOwnerCustomAddress: address(0x9F367a290B4Cc64d0F85B3783d332256b26143B9),
            tokenAdminRegistryAddress: address(0x1fF7474b42f8e9B7353dd90F8C020f738f7Fc452)
        });

        // MegaETH Testnet
        s_networkDetails[6342] = NetworkDetails({
            chainSelector: 2443239559770384419,
            routerAddress: address(0x35e752bf853009C8E080CdB3De88e3273B1c75E3),
            linkAddress: address(0x4d03398C2588D92B220578dAEde29814E41c8033),
            wrappedNativeAddress: address(0xa787B3E0471b718bBfEaA59B502fd0C4EBd7b74E),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xa0d305199271Be1C1479dA683Fc0CfC0757fBEC3),
            registryModuleOwnerCustomAddress: address(0x569a9A63a4543a5Cb79AE717dF1E26E7D30Ae08D),
            tokenAdminRegistryAddress: address(0x333b07484C0951075e9c5Fe7440ea0A93373b633)
        });

        // Base
        s_networkDetails[8453] = NetworkDetails({
            chainSelector: 15971525489660198786,
            routerAddress: address(0x881e3A65B4d4a04dD529061dd0071cf975F58bCD),
            linkAddress: address(0x88Fb150BDc53A65fe94Dea0c9BA0a6dAf8C6e196),
            wrappedNativeAddress: address(0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xC842c69d54F83170C42C4d556B4F6B2ca53Dd3E8),
            registryModuleOwnerCustomAddress: address(0xAFEd606Bd2CAb6983fC6F10167c98aaC2173D77f),
            tokenAdminRegistryAddress: address(0x6f6C373d09C07425BaAE72317863d7F6bb731e37)
        });

        // Plasma
        s_networkDetails[9745] = NetworkDetails({
            chainSelector: 9335212494177455608,
            routerAddress: address(0xcDca5D374e46A6DDDab50bD2D9acB8c796eC35C3),
            linkAddress: address(0x76a443768A5e3B8d1AED0105FC250877841Deb40),
            wrappedNativeAddress: address(0xb77E872A68C62CfC0dFb02C067Ecc3DA23B4bbf3),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xAEf7A922931848d2e731D5914f428b4E851d1Ad5),
            registryModuleOwnerCustomAddress: address(0x02A4D69cFfeC00Fbf7F3B60c93e3529Dfc58894d),
            tokenAdminRegistryAddress: address(0xc23071a8AE83671f37bdA1DaDBC745a9780f632A)
        });

        // Plasma Testnet
        s_networkDetails[9746] = NetworkDetails({
            chainSelector: 3967220077692964309,
            routerAddress: address(0xEC7088f7952ba58f268E25AC3868DF92bF462AEf),
            linkAddress: address(0xe5e3a4fF1773d043a387b16Ceb3c91cC49bAFD54),
            wrappedNativeAddress: address(0xc2e1B8e9a765A19315cD9BbbD84a1BB6DC3FC335),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xd04a5677Bea8A8D33E493924f429B9D788134849),
            registryModuleOwnerCustomAddress: address(0x8c3f29f9a492ddc95F32A9a5Bc0742e88763508A),
            tokenAdminRegistryAddress: address(0x85d7587F98655F858d4CD234B6d2cf1C747160D2)
        });

        // Monad Testnet
        s_networkDetails[10143] = NetworkDetails({
            chainSelector: 2183018362218727504,
            routerAddress: address(0x5aD0A67f4Da0E8665a3fbf15E4215A780407Cf33),
            linkAddress: address(0xe5e3a4fF1773d043a387b16Ceb3c91cC49bAFD54),
            wrappedNativeAddress: address(0xdE4E7FED43FAC37EB21aA0643d9852f75332eab8),
            ccipBnMAddress: address(0xb3B832Acd77fd31aCA5Bd7159d34e5063EC4c09f),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xD610B8f58689de7755947C05342A2DFaC30ebD57),
            registryModuleOwnerCustomAddress: address(0x524B83ae8208490151339c626fd0E35b964483e3),
            tokenAdminRegistryAddress: address(0xd3e461C55676B10634a5F81b747c324B85686Dd1)
        });

        // Gnosis Chiado
        s_networkDetails[10200] = NetworkDetails({
            chainSelector: 8871595565390010547,
            routerAddress: address(0x19b1bac554111517831ACadc0FD119D23Bb14391),
            linkAddress: address(0xDCA67FD8324990792C0bfaE95903B8A64097754F),
            wrappedNativeAddress: address(0x18c8a7ec7897177E4529065a7E7B0878358B3BfF),
            ccipBnMAddress: address(0xA189971a2c5AcA0DFC5Ee7a2C44a2Ae27b3CF389),
            ccipLnMAddress: address(0x30DeCD269277b8094c00B0bacC3aCaF3fF4Da7fB),
            rmnProxyAddress: address(0x1be106fd3b104275B1e56BcAca554B8cbc5a2577),
            registryModuleOwnerCustomAddress: address(0x6A9670741411dBf0c284E69BB1FF4aB482421d38),
            tokenAdminRegistryAddress: address(0x75ada0256Bea7956824B190419b52ba6660f9CF9)
        });

        // Abstract Sepolia
        s_networkDetails[11124] = NetworkDetails({
            chainSelector: 16235373811196386733,
            routerAddress: address(0xC308ef8a02e39887CCF55a796a128CBD1F2072a1),
            linkAddress: address(0x6641415a61bCe80D97a715054d1334360Ab833Eb),
            wrappedNativeAddress: address(0x9EDCde0257F2386Ce177C3a7FCdd97787F0D841d),
            ccipBnMAddress: address(0x596b8A0A2A63E5B4b2c0e201c4C27078642c8509),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xDcF391514C1ede0B8629A45Da710d3D7228B543C),
            registryModuleOwnerCustomAddress: address(0x41a11E4955A8bAEC73e2c679db7EA21ffa1807e0),
            tokenAdminRegistryAddress: address(0x828bDf5427A79a1A4cC17d8e2aD0fDe72499ae4F)
        });

        // Sonic Testnet
        s_networkDetails[14601] = NetworkDetails({
            chainSelector: 1763698235108410440,
            routerAddress: address(0x5bB5906e88ED789032Cd007D37da60291846E2A3),
            linkAddress: address(0x19e696e75ccbB3155EEbB579BFa555Fab22293bA),
            wrappedNativeAddress: address(0x4C344A0E257bF949D67A89be8B4516306D90E23E),
            ccipBnMAddress: address(0xBc393E3499047B24213338C24B8E8185250dc1Cb),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x4F213c8374c4F223eB85d8770Fc76eAd5163FC23),
            registryModuleOwnerCustomAddress: address(0x4D8785d2D1Fa810C0B39A688AEB46146e79a4569),
            tokenAdminRegistryAddress: address(0x22af2fDb6Ec9E5AF82585Ee0efb65b5E46086841)
        });

        // 0G
        s_networkDetails[16661] = NetworkDetails({
            chainSelector: 4426351306075016396,
            routerAddress: address(0x0aA145a62153190B8f0D3cA00c441e451529f755),
            linkAddress: address(0x76159c2b43ff6F630193e37EC68452169914C1Bb),
            wrappedNativeAddress: address(0x1Cd0690fF9a693f5EF2dD976660a8dAFc81A109c),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xBF38331E34ef7f248020611bB31Be0576D06413D),
            registryModuleOwnerCustomAddress: address(0x91339eb99C4c2Be9A071203DD99E014A3189FD29),
            tokenAdminRegistryAddress: address(0x051665f2455116e929b9972c36d23070F5054Ce0)
        });

        // Everclear
        s_networkDetails[25327] = NetworkDetails({
            chainSelector: 9723842205701363942,
            routerAddress: address(0x54fC28aa6DBf53277a7E5F4c789F823b86b9f781),
            linkAddress: address(0x318Ec96df83AccC18B5EAD5D23e0F022F7Eb5503),
            wrappedNativeAddress: address(0x2e31ebD2eB114943630Db6ba8c7f7687bdA5835F),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x2a9f896660E802c59a3178b2E8CB7FBaCCC04e86),
            registryModuleOwnerCustomAddress: address(0x051665f2455116e929b9972c36d23070F5054Ce0),
            tokenAdminRegistryAddress: address(0xBF38331E34ef7f248020611bB31Be0576D06413D)
        });

        // Apechain Curtis
        s_networkDetails[33111] = NetworkDetails({
            chainSelector: 9900119385908781505,
            routerAddress: address(0x6139Bd336bebFaaCbca33D183CeD1C90B62500cB),
            linkAddress: address(0xa787B3E0471b718bBfEaA59B502fd0C4EBd7b74E),
            wrappedNativeAddress: address(0x1762A2B15f63ca4E1165A9385cB40412CF545aC3),
            ccipBnMAddress: address(0xF48cae4B1F4EB3a1682600D4F3aFA166db5B162E),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x9D23ae40a0AeE8fF58ac4037D669773b14eEb035),
            registryModuleOwnerCustomAddress: address(0xbc9A4b299741CBf2A8eD5D2078A426027C31B2A3),
            tokenAdminRegistryAddress: address(0x4054fA847d51bE8bFC8D2E633eb4AD0C7D17C39C)
        });

        // Apechain
        s_networkDetails[33139] = NetworkDetails({
            chainSelector: 14894068710063348487,
            routerAddress: address(0xe9c6945281028cb6530d43F998eE539dFE2a9191),
            linkAddress: address(0xf575731b78981B86d34321d875A3D25a48479be6),
            wrappedNativeAddress: address(0x48b62137EdfA95a428D35C09E44256a739F6B557),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x768a1a3B321126A8B214d7376D48465C7f6Fa061),
            registryModuleOwnerCustomAddress: address(0x1c2F528e3BEeFF81Bc03CC63E64dB131d18be7fA),
            tokenAdminRegistryAddress: address(0xD3ED6fC9fd22412764ac2Ef64fB664b9393dF9F2)
        });

        // Mode
        s_networkDetails[34443] = NetworkDetails({
            chainSelector: 7264351850409363825,
            routerAddress: address(0x24C40f13E77De2aFf37c280BA06c333531589bf1),
            linkAddress: address(0x183E3691EfF3524B2315D3703D94F922CbE51F54),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xA0876B45271615c737781185C2B5ada60ed2D2B9),
            registryModuleOwnerCustomAddress: address(0xCe3f7378aE409e1CE0dD6fFA70ab683326b73f04),
            tokenAdminRegistryAddress: address(0xB4b40c010A547dff6A22d94bC2C1c1e745b62aB2)
        });

        // AB Chain
        s_networkDetails[36888] = NetworkDetails({
            chainSelector: 4829375610284793157,
            routerAddress: address(0x492641F648a4986844848E0beFE66D14817bCE34),
            linkAddress: address(0x76a443768A5e3B8d1AED0105FC250877841Deb40),
            wrappedNativeAddress: address(0x51dA03503FBBA94B9d0D88C15690D840F02F15F4),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xf09AFe78d3c7d359b334d7cB88995751F7eC5E13),
            registryModuleOwnerCustomAddress: address(0xf4a170A36D4C656F614d44453f73308Bdb275196),
            tokenAdminRegistryAddress: address(0xA27056438FfA1f286AB197488808692F0db93F8B)
        });

        // Lens Sepolia
        s_networkDetails[37111] = NetworkDetails({
            chainSelector: 6827576821754315911,
            routerAddress: address(0xf5Aa9fe2B78d852490bc4E4Fe9ab19727DD10298),
            linkAddress: address(0x7f1b9eE544f9ff9bB521Ab79c205d79C55250a36),
            wrappedNativeAddress: address(0xeee5a340Cdc9c179Db25dea45AcfD5FE8d4d3eB8),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x1C6e13153FdFC78793E211f557820ed86B10c36B),
            registryModuleOwnerCustomAddress: address(0xBFB9E98c32b80916Bd4350F644a98ba24393a73c),
            tokenAdminRegistryAddress: address(0x10Cb4265e13801cAcEd7682Bb8B5d2ed6E97964E)
        });

        // Arbitrum One
        s_networkDetails[42161] = NetworkDetails({
            chainSelector: 4949039107694359620,
            routerAddress: address(0x141fa059441E0ca23ce184B6A78bafD2A517DdE8),
            linkAddress: address(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4),
            wrappedNativeAddress: address(0x7dfF72693f6A4149b17e7C6314655f6A9F7c8B33),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xC311a21e6fEf769344EB1515588B9d535662a145),
            registryModuleOwnerCustomAddress: address(0x1f1df9f7fc939E71819F766978d8F900B816761b),
            tokenAdminRegistryAddress: address(0x39AE1032cF4B334a1Ed41cdD0833bdD7c7E7751E)
        });

        // Celo
        s_networkDetails[42220] = NetworkDetails({
            chainSelector: 1346049177634351622,
            routerAddress: address(0xfB48f15480926A4ADf9116Dca468bDd2EE6C5F62),
            linkAddress: address(0xd07294e6E917e07dfDcee882dd1e2565085C2ae0),
            wrappedNativeAddress: address(0x2021B12D8138e2D63cF0895eccABC0DFc92416c6),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x56e0507d4E69D98bE7Eb4ada01d2315596F9f281),
            registryModuleOwnerCustomAddress: address(0xb0112a2723D9D6CB5194580701A93B1eb67846D2),
            tokenAdminRegistryAddress: address(0xf19e0555fAA9051e277eeD5A0DcdB13CDaca39a9)
        });

        // Tempo
        s_networkDetails[42429] = NetworkDetails({
            chainSelector: 3963528237232804922,
            routerAddress: address(0xAE7D1b3D8466718378038de45D4D376E73A04EB6),
            linkAddress: address(0x384C8843411f725e800E625d5d1B659256D629dF),
            wrappedNativeAddress: address(0x20C0000000000000000000000000000000000001),
            ccipBnMAddress: address(0x9Af873f951c444d37B27B440ae53AB63CE58E5e5),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xc2e1B8e9a765A19315cD9BbbD84a1BB6DC3FC335),
            registryModuleOwnerCustomAddress: address(0x7A635FdfDC70469B6e8796Bd7dEeB3f24fd4f949),
            tokenAdminRegistryAddress: address(0xEC7088f7952ba58f268E25AC3868DF92bF462AEf)
        });

        // Etherlink
        s_networkDetails[42793] = NetworkDetails({
            chainSelector: 13624601974233774587,
            routerAddress: address(0x1912C3cFafE8A76A32a92861d815aC2837F237Ca),
            linkAddress: address(0x8ce7618E8f8E514d13889283F58FF03B794e6CC3),
            wrappedNativeAddress: address(0xc9B53AB2679f573e480d01e0f49e2B5CFB7a3EAb),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x1E11bAB3f07fa72312182fFDc460AE45400E6e7b),
            registryModuleOwnerCustomAddress: address(0xfa546248C54939AA6C48279CdC1EAf9A1125c411),
            tokenAdminRegistryAddress: address(0x492641F648a4986844848E0beFE66D14817bCE34)
        });

        // Hemi
        s_networkDetails[43111] = NetworkDetails({
            chainSelector: 1804312132722180201,
            routerAddress: address(0x5e48912cFDd14417D6856872341f894AE0EF07DD),
            linkAddress: address(0x63dbE12A6381D64adE47bc3D92aBF4393DFF4BC8),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xa1E3b310025c9E1861374D9CAF629E0DAa8Ecd8C),
            registryModuleOwnerCustomAddress: address(0xE27dd9BF01B55ce6803c0d81386A04212c718b95),
            tokenAdminRegistryAddress: address(0x81e81F9B2C0B79C00F38357068AE049090F2DaDE)
        });

        // Avalanche Fuji
        s_networkDetails[43113] = NetworkDetails({
            chainSelector: 14767482510784806043,
            routerAddress: address(0xF694E193200268f9a4868e4Aa017A0118C9a8177),
            linkAddress: address(0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846),
            wrappedNativeAddress: address(0xd00ae08403B9bbb9124bB305C09058E32C39A48c),
            ccipBnMAddress: address(0xD21341536c5cF5EB1bcb58f6723cE26e8D8E90e4),
            ccipLnMAddress: address(0x70F5c5C40b873EA597776DA2C21929A8282A3b35),
            rmnProxyAddress: address(0xAc8CFc3762a979628334a0E4C1026244498E821b),
            registryModuleOwnerCustomAddress: address(0xefa93f3312840683893DbdeB3d53359b2d948F50),
            tokenAdminRegistryAddress: address(0xA92053a4a3922084d992fD2835bdBa4caC6877e6)
        });

        // Zircuit
        s_networkDetails[48900] = NetworkDetails({
            chainSelector: 17198166215261833993,
            routerAddress: address(0x0A6436B56378D305729713ac332ccdCD367f3918),
            linkAddress: address(0x5D6d033B4FbD2190D99D930719fAbAcB64d2439a),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xf735667F2F3193d407089bb4c50824941821b156),
            registryModuleOwnerCustomAddress: address(0x55aeb80Aa6Ab34aA83E1F387903F8Bb2Aa9e2F2d),
            tokenAdminRegistryAddress: address(0x47d2D93EEDb694bf445E7F6458f17669459612c7)
        });

        // Memento
        s_networkDetails[51888] = NetworkDetails({
            chainSelector: 6473245816409426016,
            routerAddress: address(0x492641F648a4986844848E0beFE66D14817bCE34),
            linkAddress: address(0x76a443768A5e3B8d1AED0105FC250877841Deb40),
            wrappedNativeAddress: address(0x086917568f9317b68595B7552842de816698D7BD),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xf09AFe78d3c7d359b334d7cB88995751F7eC5E13),
            registryModuleOwnerCustomAddress: address(0xf4a170A36D4C656F614d44453f73308Bdb275196),
            tokenAdminRegistryAddress: address(0xA27056438FfA1f286AB197488808692F0db93F8B)
        });

        // Superseed Sepolia
        s_networkDetails[53302] = NetworkDetails({
            chainSelector: 13694007683517087973,
            routerAddress: address(0xC3388E1147C5F049db9dd254Dbfa06ab7F19e7FE),
            linkAddress: address(0xA3063eE34d9B4E407DF0E153c9bE679680e3A956),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x9D13Ef88bbfD4B3B4f4d8C61C2d528c398183814),
            registryModuleOwnerCustomAddress: address(0x6992d18b0850b01f6c121879284fD23f300ba8AD),
            tokenAdminRegistryAddress: address(0x66B6772Cb49374AaA088279d6524143B6E1914fE)
        });

        // Ink
        s_networkDetails[57073] = NetworkDetails({
            chainSelector: 3461204551265785888,
            routerAddress: address(0xca7c90A52B44E301AC01Cb5EB99b2fD99339433A),
            linkAddress: address(0x71052BAe71C25C78E37fD12E5ff1101A71d9018F),
            wrappedNativeAddress: address(0xfc421aD3C883Bf9E7C4f42dE845C4e4405799e73),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x3A293fa336E118900AD0f2EcfeC0DAa6A4DeDaA1),
            registryModuleOwnerCustomAddress: address(0x04c5046A1f4E3fFf094c26dFCAA75eF293932f18),
            tokenAdminRegistryAddress: address(0xEb062d21c713A3d940BB0FaECFdC387d6Ea23697)
        });

        // Linea Sepolia
        s_networkDetails[59141] = NetworkDetails({
            chainSelector: 5719461335882077547,
            routerAddress: address(0xB4431A6c63F72916151fEA2864DBB13b8ce80E8a),
            linkAddress: address(0xF64E6E064a71B45514691D397ad4204972cD6508),
            wrappedNativeAddress: address(0x06565ed324Ee9fb4DB0FF80B7eDbE4Cb007555a3),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0xA7EA79b9E466e8D2a440128867ed399bC78f4aaE),
            rmnProxyAddress: address(0xb550D73F428C08441E4d92d762CceE5F39b1c608),
            registryModuleOwnerCustomAddress: address(0xeabcDfdc6dA2c66144f150CbD1eDa54c842B67B3),
            tokenAdminRegistryAddress: address(0x5B5179082056227721031C2ef1c45049864D0149)
        });

        // Linea
        s_networkDetails[59144] = NetworkDetails({
            chainSelector: 4627098889531055414,
            routerAddress: address(0x549FEB73F2348F6cD99b9fc8c69252034897f06C),
            linkAddress: address(0xa18152629128738a5c081eb226335FEd4B9C95e9),
            wrappedNativeAddress: address(0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x1F8fbCf559f08FE7c4076f0d68DB861e1E27f95b),
            registryModuleOwnerCustomAddress: address(0x0a12ec21c43ab2b4f69693Da1b0149e7652689c0),
            tokenAdminRegistryAddress: address(0xBc933cEE67d2b1c08490ee8C51E2dF653a713534)
        });

        // Metis Sepolia
        s_networkDetails[59902] = NetworkDetails({
            chainSelector: 3777822886988675105,
            routerAddress: address(0xaCdaBa07ECad81dc634458b98673931DD9d3Bc14),
            linkAddress: address(0x9870D6a0e05F867EAAe696e106741843F7fD116D),
            wrappedNativeAddress: address(0x5c48e07062aC4E2Cf4b9A768a711Aef18e8fbdA0),
            ccipBnMAddress: address(0x20Aa09AAb761e2E600d65c6929A9fd1E59821D3f),
            ccipLnMAddress: address(0x705b364CadE0e515577F2646529e3A417473a155),
            rmnProxyAddress: address(0xfd66EBE7335E91ae6f4CCCccdDDF262Ab5e35c71),
            registryModuleOwnerCustomAddress: address(0x64f8535919A00D2b09d8E5C7ab70eC4b81128CdB),
            tokenAdminRegistryAddress: address(0x31668C3E8f96415286e9e03592ad97E50e565f52)
        });

        // BOB
        s_networkDetails[60808] = NetworkDetails({
            chainSelector: 3849287863852499584,
            routerAddress: address(0x827716e74F769AB7b6bb374A29235d9c2156932C),
            linkAddress: address(0x5aB885CDa7216b163fb6F813DEC1E1532516c833),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xe4D8E0A02C61f6DDe95255E702fe1237428673D8),
            registryModuleOwnerCustomAddress: address(0x55aeb80Aa6Ab34aA83E1F387903F8Bb2Aa9e2F2d),
            tokenAdminRegistryAddress: address(0xa57d04119AFf4884F8602213E58d8AaAD18229cb)
        });

        // Henesys
        s_networkDetails[68414] = NetworkDetails({
            chainSelector: 12657445206920369324,
            routerAddress: address(0x492641F648a4986844848E0beFE66D14817bCE34),
            linkAddress: address(0x76a443768A5e3B8d1AED0105FC250877841Deb40),
            wrappedNativeAddress: address(0x150869eac5C58d3655f860C4316107fB626244d0),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xf09AFe78d3c7d359b334d7cB88995751F7eC5E13),
            registryModuleOwnerCustomAddress: address(0xf4a170A36D4C656F614d44453f73308Bdb275196),
            tokenAdminRegistryAddress: address(0xA27056438FfA1f286AB197488808692F0db93F8B)
        });

        // Polygon Amoy
        s_networkDetails[80002] = NetworkDetails({
            chainSelector: 16281711391670634445,
            routerAddress: address(0x9C32fCB86BF0f4a1A8921a9Fe46de3198bb884B2),
            linkAddress: address(0x0Fd9e8d3aF1aaee056EB9e802c3A762a667b1904),
            wrappedNativeAddress: address(0x360ad4f9a9A8EFe9A8DCB5f461c4Cc1047E1Dcf9),
            ccipBnMAddress: address(0xcab0EF91Bee323d1A617c0a027eE753aFd6997E4),
            ccipLnMAddress: address(0x3d357fb52253e86c8Ee0f80F5FfE438fD9503FF2),
            rmnProxyAddress: address(0x7c1e545A40750Ee8761282382D51E017BAC68CBB),
            registryModuleOwnerCustomAddress: address(0xAF2356327c6BBd644A273271B6cA301B49787970),
            tokenAdminRegistryAddress: address(0x1e73f6842d7afDD78957ac143d1f315404Dd9e5B)
        });

        // Berachain Bartio
        s_networkDetails[80084] = NetworkDetails({
            chainSelector: 8999465244383784164,
            routerAddress: address(0xb1653462481e1bF30B5cca3082e2454E41668c65),
            linkAddress: address(0x52CEEed7d3f8c6618e4aaD6c6e555320d0D83271),
            wrappedNativeAddress: address(0x7507c1dc16935B82698e4C63f2746A2fCf994dF8),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xf3E86536f95EC830983A51716C3577887cd2c47B),
            registryModuleOwnerCustomAddress: address(0x8E4011605b934c615C82938c9AEf9e23F6442D10),
            tokenAdminRegistryAddress: address(0x2df015A976044B2e09aa7c135b2B1e92CF47c50f)
        });

        // Berachain
        s_networkDetails[80094] = NetworkDetails({
            chainSelector: 1294465214383781161,
            routerAddress: address(0x71a275704c283486fBa26dad3dd0DB78804426eF),
            linkAddress: address(0x71052BAe71C25C78E37fD12E5ff1101A71d9018F),
            wrappedNativeAddress: address(0x6969696969696969696969696969696969696969),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x25943b8C30C47F4eF09CcF2BAE315EbaF591881d),
            registryModuleOwnerCustomAddress: address(0x160603D7C0Ac00409276bf6707430712Caf5b555),
            tokenAdminRegistryAddress: address(0x0944C3Fb1dB7D165336569221995B31cBE6c8A55)
        });

        // Blast
        s_networkDetails[81457] = NetworkDetails({
            chainSelector: 4411394078118774322,
            routerAddress: address(0x12e0B8E349C6fb7E6E40713E8125C3cF1127ea8C),
            linkAddress: address(0x93202eC683288a9EA75BB829c6baCFb2BfeA9013),
            wrappedNativeAddress: address(0x4300000000000000000000000000000000000004),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x50dbd1e73ED032f42B5892E5F3689972FefAc880),
            registryModuleOwnerCustomAddress: address(0xb227f007804c16546Bd054dfED2E7A1fD5437678),
            tokenAdminRegistryAddress: address(0x846Fccd01D4115FD1E81267495773aeB33bF1dC7)
        });

        // Base Sepolia
        s_networkDetails[84532] = NetworkDetails({
            chainSelector: 10344971235874465080,
            routerAddress: address(0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93),
            linkAddress: address(0xE4aB69C077896252FAFBD49EFD26B5D171A32410),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0x88A2d74F47a237a62e7A51cdDa67270CE381555e),
            ccipLnMAddress: address(0xA98FA8A008371b9408195e52734b1768c0d1Cb5c),
            rmnProxyAddress: address(0x99360767a4705f68CcCb9533195B761648d6d807),
            registryModuleOwnerCustomAddress: address(0x176ae8C6C11DD2c031B924CE1A0A43188035f3f6),
            tokenAdminRegistryAddress: address(0x736D0bBb318c1B27Ff686cd19804094E66250e17)
        });

        // Plume
        s_networkDetails[98866] = NetworkDetails({
            chainSelector: 17912061998839310979,
            routerAddress: address(0x5C4f4622AD0EC4a47e04840db7E9EcA8354109af),
            linkAddress: address(0xb549B375dA0c76f8b3877B9aDfDD28378f087A64),
            wrappedNativeAddress: address(0xEa237441c92CAe6FC17Caaf9a7acB3f953be4bd1),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x975B590aCc4aAd12f69974339B26cCE24A380031),
            registryModuleOwnerCustomAddress: address(0x022D74c2D24e7625368720dcBA5674bd8A951892),
            tokenAdminRegistryAddress: address(0x01E5B2fAC7156c54f034E1767f2799fDd41B8285)
        });

        // Plume Testnet
        s_networkDetails[98867] = NetworkDetails({
            chainSelector: 13874588925447303949,
            routerAddress: address(0x5e5Fd4720E1CE826138D043aF578D69f48af502F),
            linkAddress: address(0xB97e3665AEAF96BDD6b300B2e0C93C662104A068),
            wrappedNativeAddress: address(0xC1FD14775c8665B31c7154074f537338774351EB),
            ccipBnMAddress: address(0x225fAc4130595d1C7dabbE61A8bA9B051440b76c),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xAa3ae5481EE445711252131f1516922D0962916A),
            registryModuleOwnerCustomAddress: address(0x693926456C8b210f56E29Bc5b4514B32A5224c88),
            tokenAdminRegistryAddress: address(0x855cF0d18A0BeBEDA7c1CD2F943686120cCCC6bd)
        });

        // ADI Network AB Testnet
        s_networkDetails[99999] = NetworkDetails({
            chainSelector: 9418205736192840573,
            routerAddress: address(0x5D445DF89674096B6A138565cAE955FF816f352D),
            linkAddress: address(0x64c12A9Bfdb4DEB5F37A0eC4c5fae0405669612A),
            wrappedNativeAddress: address(0xddeA1446FD21e3d2CB934A78Fe200a266739fad4),
            ccipBnMAddress: address(0x23577b74c98325f9e70677EA8B72707F06625343),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x8Fdc413B5Da54cEE04b181b83f99D82587F7e768),
            registryModuleOwnerCustomAddress: address(0xb3b3F359f5C7CDE7568606889cB08cDC0a9f91Df),
            tokenAdminRegistryAddress: address(0xEf3278a2F481415446060264b1f7903F96771447)
        });

        // Katana Tatara
        s_networkDetails[129399] = NetworkDetails({
            chainSelector: 9090863410735740267,
            routerAddress: address(0x1dF1fe714A376f248d51AAB826C3feeC379e80fC),
            linkAddress: address(0x29261B6Fb93097885bEB714ee253Da63A52dFc46),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xAD8BeA8bC5Fe468Dc1F7BbEce59A86584407255f),
            registryModuleOwnerCustomAddress: address(0x32E18611aeb4e42d931dF838fd4e019CC6B2A674),
            tokenAdminRegistryAddress: address(0xFE50B8Cd5a07E23550fE6b3B138408936c10EC29)
        });

        // Taiko Alethia
        s_networkDetails[167000] = NetworkDetails({
            chainSelector: 16468599424800719238,
            routerAddress: address(0xeb2502AeD3Cfd6E37e292c6B837a8FFF9a042367),
            linkAddress: address(0x917a3964C37993e99a47C779bEb5Db1E9d13804d),
            wrappedNativeAddress: address(0xA51894664A773981C6C112C43ce576f315d5b1B6),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x01f66BA71474d30De43d3c7B389F4019505B7F59),
            registryModuleOwnerCustomAddress: address(0x4e52dD94e9BCfeFE3C78153bDfB0AB1d30687297),
            tokenAdminRegistryAddress: address(0x308a2A7d13B12ba26649F381C53F7e7C60d0D9c6)
        });

        // Taiko Hekla
        s_networkDetails[167009] = NetworkDetails({
            chainSelector: 7248756420937879088,
            routerAddress: address(0x07a2b9BB0456a7e999B61ca8F166ADDF5878F468),
            linkAddress: address(0x01fcdEedbA59bc68b0914D92277678dAB6827e2c),
            wrappedNativeAddress: address(0xae2C46ddb314B9Ba743C6dEE4878F151881333D9),
            ccipBnMAddress: address(0x54B50385e417469dbdb697f40651e8864664D992),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xF3E5e253164B60109db668ef7Eba6f9813F8A761),
            registryModuleOwnerCustomAddress: address(0xBB33E6d7A454843204Fd0ae53fdbf2535A993C10),
            tokenAdminRegistryAddress: address(0xa089c6A73e8c2EE98cC96bF99A8b6aE687e715DF)
        });

        // Mind Network Testnet
        s_networkDetails[192940] = NetworkDetails({
            chainSelector: 7189150270347329685,
            routerAddress: address(0xf877Eb80E5Ab0d58afF1a1431756B74Dd5190021),
            linkAddress: address(0xE0352dEd874c3E72d922CE533E136385fBE4a9B4),
            wrappedNativeAddress: address(0x12e3b49DF7dD40792EFbB1B3eAB1295951Bad5EE),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xbef6CEC4a6C3A14404C63Ae84dA2AAf456f8a6C9),
            registryModuleOwnerCustomAddress: address(0x23577b74c98325f9e70677EA8B72707F06625343),
            tokenAdminRegistryAddress: address(0x8Fb9dD6DaC6e871F09bBE5632a78e1C23249EAe9)
        });

        // Bitlayer Testnet
        s_networkDetails[200810] = NetworkDetails({
            chainSelector: 3789623672476206327,
            routerAddress: address(0x3dfbe078277609D34c8ef015c61f23A9BeDE61BB),
            linkAddress: address(0x2A5bACb2440BC17D53B7b9Be73512dDf92265e48),
            wrappedNativeAddress: address(0x3e57d6946f893314324C975AA9CEBBdF3232967E),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xdB44738b1DD21E05e3c56ecD73701daC2c793c0D),
            registryModuleOwnerCustomAddress: address(0x58783b4E644Af8f549C1D79e80E3DC65727cE09A),
            tokenAdminRegistryAddress: address(0x44919DB06c5c2f14F8d44b1A67F8032E0B617293)
        });

        // Bitlayer
        s_networkDetails[200901] = NetworkDetails({
            chainSelector: 7937294810946806131,
            routerAddress: address(0x6c0aA29330c58dda07faD577fF5a0280823a910c),
            linkAddress: address(0x56B275c0Ec034a229a1deD8DB17089544bc276D9),
            wrappedNativeAddress: address(0xfF204e2681A6fA0e2C3FaDe68a1B28fb90E4Fc5F),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xcaa6131cEe85ba2F140cBa05F6825aC60B6CEA56),
            registryModuleOwnerCustomAddress: address(0x1f524a11d89D68a4E4b1c8A195E91Fb1d8f0B56a),
            tokenAdminRegistryAddress: address(0xd999758aEB04BDa755Ae78344FFF5534947620CD)
        });

        // Arbitrum Sepolia
        s_networkDetails[421614] = NetworkDetails({
            chainSelector: 3478487238524512106,
            routerAddress: address(0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165),
            linkAddress: address(0xb1D4538B4571d411F07960EF2838Ce337FE1E80E),
            wrappedNativeAddress: address(0xb13Cfa6f8B2Eed2C37fB00fF0c1A59807C585810),
            ccipBnMAddress: address(0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D),
            ccipLnMAddress: address(0x139E99f0ab4084E14e6bb7DacA289a91a2d92927),
            rmnProxyAddress: address(0x9527E2d01A3064ef6b50c1Da1C0cC523803BCFF2),
            registryModuleOwnerCustomAddress: address(0xaD417c0611dBD225471D31F056b8B6beC1CBC153),
            tokenAdminRegistryAddress: address(0x8126bE56454B628a88C17849B9ED99dd5a11Bd2f)
        });

        // Scroll Sepolia
        s_networkDetails[534351] = NetworkDetails({
            chainSelector: 2279865765895943307,
            routerAddress: address(0x6aF501292f2A33C81B9156203C9A66Ba0d8E3D21),
            linkAddress: address(0x7273ebbB21F8D8AcF2bC12E71a08937712E9E40c),
            wrappedNativeAddress: address(0x5300000000000000000000000000000000000004),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0x0298e204F9131d45EEb436D693f32C6eA1190622),
            rmnProxyAddress: address(0x8f4413e02265F65eF89FB908dbA2915fF9f7F8cB),
            registryModuleOwnerCustomAddress: address(0xeA2912f446Ff28663D2E5A971da751A84E409292),
            tokenAdminRegistryAddress: address(0xf49C561cf56149517c67793a3035D1877ffE2f04)
        });

        // Scroll
        s_networkDetails[534352] = NetworkDetails({
            chainSelector: 13204309965629103672,
            routerAddress: address(0x9a55E8Cab6564eb7bbd7124238932963B8Af71DC),
            linkAddress: address(0x548C6944cba02B9D1C0570102c89de64D258d3Ac),
            wrappedNativeAddress: address(0x5300000000000000000000000000000000000004),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x68B38980aD70650a6f3229BA156e5c1F88A21320),
            registryModuleOwnerCustomAddress: address(0x3539F2E214d8BC7E611056383323aC6D1b01943c),
            tokenAdminRegistryAddress: address(0x846dEA1c1706FC35b4aa78B32d31F1599DAA47b4)
        });

        // Ethereum Hoodi
        s_networkDetails[560048] = NetworkDetails({
            chainSelector: 10380998176179737091,
            routerAddress: address(0xc93Dac3422660A41500a24C94BF14616995e3CA6),
            linkAddress: address(0x76c00B055414de203B79B4955E28119BF459033e),
            wrappedNativeAddress: address(0xF0b60c40554fE9d385EB5F1Ec03471f0d66EC589),
            ccipBnMAddress: address(0xAA3450998528E43322698a914D0b756B98292A3b),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xEB5D23FD0CFcd7EB3D16ac6F3A58CAdaF44c2324),
            registryModuleOwnerCustomAddress: address(0x19e696e75ccbB3155EEbB579BFa555Fab22293bA),
            tokenAdminRegistryAddress: address(0x073b3C71eb4630c4C88F1f72954fdFff30cf3f8D)
        });

        // Merlin Testnet
        s_networkDetails[686868] = NetworkDetails({
            chainSelector: 5269261765892944301,
            routerAddress: address(0x500063c3827cd871E7b4Af0384E369bDEb75b2e2),
            linkAddress: address(0xB904d5b9a1e74F6576fFF550EeE75Eaa68e2dd50),
            wrappedNativeAddress: address(0x1A6357313BA1B6bc92e7325A9BAf241Ca3e493dD),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xcb89C5D13C18850fA5AEe997b7B4DEdD87ab1B34),
            registryModuleOwnerCustomAddress: address(0xd7b86ed053806177718B9e03c63c4Bc501825C00),
            tokenAdminRegistryAddress: address(0xcafA13f9Bc0AA3aB37e29cA18343507bf8D43E93)
        });

        // Pharos Atlantic Testnet
        s_networkDetails[688689] = NetworkDetails({
            chainSelector: 16098325658947243212,
            routerAddress: address(0x1E202D00714bFBcD7a5b4CF782791C38DA8BdC99),
            linkAddress: address(0x2f79e049f552E600D5d8118923278Aa0fCD67179),
            wrappedNativeAddress: address(0x838800b758277CC111B2d48Ab01e5E164f8E9471),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xB45B9eb94F25683B47e5AFb0f74A05a58be86311),
            registryModuleOwnerCustomAddress: address(0x5370103629Fe91F28708ec4DC1A7A70DC5396EBf),
            tokenAdminRegistryAddress: address(0xAd1652471967E7FBf524245782A7f4430F6a4243)
        });

        // Hemi Sepolia
        s_networkDetails[743111] = NetworkDetails({
            chainSelector: 16126893759944359622,
            routerAddress: address(0xc1D615EC997F581741d867B08bC7050c90d213B0),
            linkAddress: address(0x5246409a2e09134824c4E709602205B176491e57),
            wrappedNativeAddress: address(0x0C8aFD1b58aa2A5bAd2414B861D8A7fF898eDC3A),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x0001518b4D94c0E1961D27F3120487f891739d0B),
            registryModuleOwnerCustomAddress: address(0xB45B9eb94F25683B47e5AFb0f74A05a58be86311),
            tokenAdminRegistryAddress: address(0x5c8a206f4800A61fF4430a2b75381A0033172860)
        });

        // Katana
        s_networkDetails[747474] = NetworkDetails({
            chainSelector: 2459028469735686113,
            routerAddress: address(0x7c19b79D2a054114Ab36ad758A36e92376e267DA),
            linkAddress: address(0xc2C447b04e0ED3476DdbDae8E9E39bE7159d27b6),
            wrappedNativeAddress: address(0xEE7D8BCFb72bC1880D0Cf19822eB0A2e6577aB62),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x32270E4FA459cA47ae0334488e27ffb9bC9aB4a1),
            registryModuleOwnerCustomAddress: address(0x10fD7245f6ca39885D3A398b03dCcCC833fC96A1),
            tokenAdminRegistryAddress: address(0x048B911A1AE5dD4f0aEE5241A30d3DEDa3501D54)
        });

        // Ink Sepolia
        s_networkDetails[763373] = NetworkDetails({
            chainSelector: 9763904284804119144,
            routerAddress: address(0x17fCda531D8E43B4e2a2A2492FBcd4507a1685A1),
            linkAddress: address(0x3423C922911956b1Ccbc2b5d4f38216a6f4299b4),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0x414dbe1d58dd9BA7C84f7Fc0e4f82bc858675d37),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x84017cfddD12D319E5bBf090e0de6d55B78160Cb),
            registryModuleOwnerCustomAddress: address(0xaB018890bBdDf9B80E21d1c335c5f6acdbE0f5D6),
            tokenAdminRegistryAddress: address(0x3A849a05a590FeaEf26c2d425241A2BF29307161)
        });

        // BOB Sepolia
        s_networkDetails[808813] = NetworkDetails({
            chainSelector: 5535534526963509396,
            routerAddress: address(0x7808184405d6Cbc663764003dE21617fa640bc82),
            linkAddress: address(0xcd2AfB2933391E35e8682cbaaF75d9CA7339b183),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0x3B7d0d0CeC08eBF8dad58aCCa4719791378b2329),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xD642e08eeF81bb55B8282701234659A3233E2145),
            registryModuleOwnerCustomAddress: address(0xbc9A4b299741CBf2A8eD5D2078A426027C31B2A3),
            tokenAdminRegistryAddress: address(0xAd57E853813d48c0D3687497bbdcF3eBc47dECB1)
        });

        // Treasure Topaz
        s_networkDetails[978658] = NetworkDetails({
            chainSelector: 3676916124122457866,
            routerAddress: address(0x7425448a70fEb77F0319cC8cD19691FECE7F5C05),
            linkAddress: address(0x0FE9fAAF3e26f756443fd8f92F6711989a8e0fF5),
            wrappedNativeAddress: address(0x095ded714d42cBD5fb2E84A0FfbFb140E38dC9E1),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x43f7b33Aee99208A38e4384655d35D8F0dCe7C51),
            registryModuleOwnerCustomAddress: address(0x4c1812293c06f5eae71B15A7ceA47f637C4C53c6),
            tokenAdminRegistryAddress: address(0xDdbC9B776f1e0AC6A462D80e1d2aa3cF9464454E)
        });

        // Jovay Sepolia Testnet
        s_networkDetails[2019775] = NetworkDetails({
            chainSelector: 945045181441419236,
            routerAddress: address(0x2016AA303B331bd739Fd072998e579a3052500A6),
            linkAddress: address(0xd3e461C55676B10634a5F81b747c324B85686Dd1),
            wrappedNativeAddress: address(0xFe06d41BA962A74209845f938c387b363a931505),
            ccipBnMAddress: address(0xB45B9eb94F25683B47e5AFb0f74A05a58be86311),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x5Dc49Ec54B92F7D493bC8126c0730DA74605cc00),
            registryModuleOwnerCustomAddress: address(0xd1CBe8dF481C7a78AaaAfB0466814d13d93bd9b7),
            tokenAdminRegistryAddress: address(0xaCc1C3b214CA255918C9Da66Db3bcc933d57188B)
        });

        // Arc Network Testnet
        s_networkDetails[5042002] = NetworkDetails({
            chainSelector: 3034092155422581607,
            routerAddress: address(0xdE4E7FED43FAC37EB21aA0643d9852f75332eab8),
            linkAddress: address(0x3F1f176e347235858DD6Db905DDBA09Eaf25478a),
            wrappedNativeAddress: address(0xbf4B839A7939a52acbF8fC52D5Bd5BFE69a064EA),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xD610B8f58689de7755947C05342A2DFaC30ebD57),
            registryModuleOwnerCustomAddress: address(0x524B83ae8208490151339c626fd0E35b964483e3),
            tokenAdminRegistryAddress: address(0xd3e461C55676B10634a5F81b747c324B85686Dd1)
        });

        // Jovay
        s_networkDetails[5734951] = NetworkDetails({
            chainSelector: 1523760397290643893,
            routerAddress: address(0x492641F648a4986844848E0beFE66D14817bCE34),
            linkAddress: address(0x76a443768A5e3B8d1AED0105FC250877841Deb40),
            wrappedNativeAddress: address(0xeA29Cbb2808CF848C185E4405Bb002F53f92a241),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xf09AFe78d3c7d359b334d7cB88995751F7eC5E13),
            registryModuleOwnerCustomAddress: address(0xf4a170A36D4C656F614d44453f73308Bdb275196),
            tokenAdminRegistryAddress: address(0xA27056438FfA1f286AB197488808692F0db93F8B)
        });

        // DogeOS Chikyu Testnet
        s_networkDetails[6281971] = NetworkDetails({
            chainSelector: 7254999290874773717,
            routerAddress: address(0x524B83ae8208490151339c626fd0E35b964483e3),
            linkAddress: address(0xe5e3a4fF1773d043a387b16Ceb3c91cC49bAFD54),
            wrappedNativeAddress: address(0xF6BDB158A5ddF77F1B83bC9074F6a472c58D78aE),
            ccipBnMAddress: address(0x4A92387cE022FDae06c2e49020be7B24AAB16070),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x0820f975ce90EE5c508657F0C58b71D1fcc85cE0),
            registryModuleOwnerCustomAddress: address(0xD610B8f58689de7755947C05342A2DFaC30ebD57),
            tokenAdminRegistryAddress: address(0xEAB080c724587fFC9F2EFF82e36EE4Fb27774959)
        });

        // Zora
        s_networkDetails[7777777] = NetworkDetails({
            chainSelector: 3555797439612589184,
            routerAddress: address(0x65b40941fa86Fc444043257cd677a7F0bD034F79),
            linkAddress: address(0x3662B6f73c5560229D1a98aF6e59E6649D568374),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xFb6e1F0041c273dE4b99B23E2cB4c12CECe06C56),
            registryModuleOwnerCustomAddress: address(0x03Df929510A52C97bb1B3E5f33EA5D9735A50280),
            tokenAdminRegistryAddress: address(0x791BA3010A5BFeA773d2cfD6Ea4D0Ce9627856eB)
        });

        // Ethereum Sepolia
        s_networkDetails[11155111] = NetworkDetails({
            chainSelector: 16015286601757825753,
            routerAddress: address(0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59),
            linkAddress: address(0x779877A7B0D9E8603169DdbD7836e478b4624789),
            wrappedNativeAddress: address(0xc4bF5CbDaBE595361438F8c6a187bDc330539c60),
            ccipBnMAddress: address(0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05),
            ccipLnMAddress: address(0x466D489b6d36E7E3b824ef491C225F5830E81cC1),
            rmnProxyAddress: address(0xba3f6251de62dED61Ff98590cB2fDf6871FbB991),
            registryModuleOwnerCustomAddress: address(0xa3c796d480638d7476792230da1E2ADa86e031b0),
            tokenAdminRegistryAddress: address(0x95F29FEE11c5C55d26cCcf1DB6772DE953B37B82)
        });

        // OP Sepolia
        s_networkDetails[11155420] = NetworkDetails({
            chainSelector: 5224473277236331295,
            routerAddress: address(0x114A20A10b43D4115e5aeef7345a1A71d2a60C57),
            linkAddress: address(0xE4aB69C077896252FAFBD49EFD26B5D171A32410),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0x8aF4204e30565DF93352fE8E1De78925F6664dA7),
            ccipLnMAddress: address(0x044a6B4b561af69D2319A2f4be5Ec327a6975D0a),
            rmnProxyAddress: address(0xb40A3109075965cc09E93719e33E748abf680dAe),
            registryModuleOwnerCustomAddress: address(0x6AfeDdaE519bA02985B4DD027b3f22298e1D828D),
            tokenAdminRegistryAddress: address(0x1d702b1FA12F347f0921C722f9D9166F00DEB67A)
        });

        // Neo X Testnet T4
        s_networkDetails[12227332] = NetworkDetails({
            chainSelector: 2217764097022649312,
            routerAddress: address(0x609747816B6C237d5C4960065BC11d2F0DE752A6),
            linkAddress: address(0x7F85bAC57B5D4b81F866F495c30AB8C8c453f6FD),
            wrappedNativeAddress: address(0x1CE16390FD09040486221e912B87551E4e44Ab17),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xc707eecF5CD423BbeaAc55fb1D11a7FB74bf4a4b),
            registryModuleOwnerCustomAddress: address(0xd54205E00835B63Db005ADEF8d99E4984601ACAf),
            tokenAdminRegistryAddress: address(0x9F7F6002b5f6F4d5a53BFDf380435fa18Ae2Dc13)
        });

        // Corn
        s_networkDetails[21000000] = NetworkDetails({
            chainSelector: 9043146809313071210,
            routerAddress: address(0x183f6069A0D5c2DEC1Dd1eCF3B1581e12dEb4Efe),
            linkAddress: address(0x7311DED199CC28D80E58e81e8589aa160199FCD2),
            wrappedNativeAddress: address(0xda5dDd7270381A7C2717aD10D1c0ecB19e3CDFb2),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x91ca2Aa7429e5F702f1F750b317AB604d5a6a16e),
            registryModuleOwnerCustomAddress: address(0x04c5046A1f4E3fFf094c26dFCAA75eF293932f18),
            tokenAdminRegistryAddress: address(0xCd51e57cD26b9B5eecbfe3d96DAabF3d12A663DA)
        });

        // Corn Testnet
        s_networkDetails[21000001] = NetworkDetails({
            chainSelector: 1467427327723633929,
            routerAddress: address(0x9981250f56d4d0Fa9736343659B4890ebbb94110),
            linkAddress: address(0x996EfAb6011896Be832969D91E9bc1b3983cfdA1),
            wrappedNativeAddress: address(0xda5dDd7270381A7C2717aD10D1c0ecB19e3CDFb2),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0x3C49708F8F3F7da6D0846d63Fa4E49Ab52ba9539),
            registryModuleOwnerCustomAddress: address(0x9377075Bf25BaCB38dbe1c29DeB143aEeE0cb51F),
            tokenAdminRegistryAddress: address(0xf0dF3Bb68A4392FF686c92486ce80E2CF4f0f326)
        });

        // Blast Sepolia
        s_networkDetails[168587773] = NetworkDetails({
            chainSelector: 2027362563942762617,
            routerAddress: address(0xfb2f2A207dC428da81fbAFfDDe121761f8Be1194),
            linkAddress: address(0x02c359ebf98fc8BF793F970F9B8302bb373BdF32),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000023),
            ccipBnMAddress: address(0x8D122C3e8ce9C8B62b87d3551bDfD8C259Bb0771),
            ccipLnMAddress: address(0x35347A2fC1f2a4c5Eae03339040d0b83b09e6FDA),
            rmnProxyAddress: address(0x1cb6afB6F411f0469c3C0d5D46f6e8f7fd3eADe0),
            registryModuleOwnerCustomAddress: address(0x912F59E92467C54BBab49ED3a5d431504aFBa30c),
            tokenAdminRegistryAddress: address(0x98f1703B9C02f9Ab8bA4cc209Ee8D7B188Bb43a8)
        });

        // Zora Sepolia
        s_networkDetails[999999999] = NetworkDetails({
            chainSelector: 16244020411108056671,
            routerAddress: address(0xC5c058814cb85bF52c83264e09da90CB4c932cb7),
            linkAddress: address(0xBEDDEB2DF8904cdBCFB6Bf29b91d122D5Ae4eb7e),
            wrappedNativeAddress: address(0x4200000000000000000000000000000000000006),
            ccipBnMAddress: address(0),
            ccipLnMAddress: address(0),
            rmnProxyAddress: address(0xf3bc6E7D8A43228B49e976C5f9eDFF5fdFDDaC24),
            registryModuleOwnerCustomAddress: address(0x09ED6dC4d7cF091A1f9579FACA0d3f485A1c367B),
            tokenAdminRegistryAddress: address(0xa024d8e48513D1105E0c50d4494DfD827200364e)
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
