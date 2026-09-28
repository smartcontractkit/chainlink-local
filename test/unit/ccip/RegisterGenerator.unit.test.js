import { describe, it } from "node:test";
import assert from "node:assert/strict";
import generator from "../../../helper_doc/updateRegisterContract.cjs";

const { selectWrappedNativeToken, formatRegisterData, formatRegisterMarkers } = generator;

const token = (symbol) => ({ symbol, address: `0x${symbol}` });
const pick = (...symbols) => selectWrappedNativeToken(symbols.map(token))?.symbol ?? null;

// Fee token lists as returned by https://docs.chain.link/api/ccip/v1/chains (Sep 2026).
describe("updateRegisterContract: selectWrappedNativeToken", () => {
    it("ignores fee tokens listed before the wrapped native token (GHO before WETH)", () => {
        assert.equal(pick("GHO", "LINK", "WETH"), "WETH"); // Ethereum, Arbitrum, Base, Sepolia
        assert.equal(pick("GHO", "LINK", "WAVAX"), "WAVAX"); // Avalanche
        assert.equal(pick("AlphaUSD", "BetaUSD", "LINK", "PathUSD", "ThetaUSD", "WTEMP"), "WTEMP"); // Tempo Testnet
    });

    it("prefers the chain's own wrapped native token over a bridged WETH", () => {
        assert.equal(pick("LINK", "WETH", "WMON"), "WMON"); // Monad Testnet
        assert.equal(pick("LINK", "WETH", "WXPL"), "WXPL"); // Plasma Testnet
    });

    it("returns null when the wrapped native token is ambiguous or missing", () => {
        assert.equal(pick("LINK", "WgUSDT", "WUSDT0"), null); // Stable
        assert.equal(pick("LINK", "PBTC"), null); // Botanix
        assert.equal(pick("LINK"), null);
        assert.equal(selectWrappedNativeToken(undefined), null);
    });
});

const chain = (overrides) => ({
    chainSelector: "1",
    routerAddress: "",
    linkAddress: "",
    wrappedNativeAddress: "",
    ccipBnMAddress: "",
    ccipLnMAddress: "",
    rmnProxyAddress: "",
    registryModuleOwnerCustomAddress: "",
    tokenAdminRegistryAddress: "",
    ...overrides
});

const networks = (count) => {
    const details = {};
    for (let id = 1; id <= count; id++) details[id] = chain({ chainSelector: String(id * 10) });
    return details;
};

describe("updateRegisterContract: formatRegisterData", () => {
    it("splits chains into shards of at most 40 and emits one getter per shard", () => {
        const src = formatRegisterData(networks(43));

        assert.equal((src.match(/contract RegisterData\d+/g) || []).length, 2);
        assert.match(src, /library RegisterDataShards/);
        assert.equal((src.match(/if \(chainId == /g) || []).length, 43);
        assert.equal((src.match(/return \(unknown, false\);/g) || []).length, 2);
        assert.match(src, /function etchAll\(Vm vm, address registerAddress\) internal/);
    });

    it("writes readable entries and inlines zero addresses", () => {
        const src = formatRegisterData({
            7: chain({ chainSelector: "42", routerAddress: `0x${"11".repeat(20)}` })
        });

        assert.match(src, /\/\/ Chain 7/);
        assert.match(src, /if \(chainId == 7\) \{/);
        assert.match(src, /chainSelector: 42,/);
        assert.match(src, /routerAddress: address\(0x1111111111111111111111111111111111111111\)/);
        assert.match(src, /ccipBnMAddress: address\(0\)/);
    });

    it("emits the shard count into the Register markers", () => {
        assert.match(formatRegisterMarkers(networks(41)), /_SHARD_COUNT = 2;/);
        assert.match(formatRegisterMarkers(networks(1)), /_SHARD_COUNT = 1;/);
    });
});
