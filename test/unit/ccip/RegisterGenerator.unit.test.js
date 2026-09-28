import { describe, it } from "node:test";
import assert from "node:assert/strict";
import generator from "../../../helper_doc/updateRegisterContract.cjs";

const { selectWrappedNativeToken } = generator;

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
