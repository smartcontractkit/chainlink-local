// Selectors, PDA seeds and address helpers for the local CCIP 2.0 trust layer.
//
// Ported in part from the prototype by Stefano Magini (magiodev-cll/chainlink-local, feat/svm-local,
// src/ccip-svm/src/constants.ts): the two selectors, `SEEDS`, `programDataAddress` and `pda`.

import { PublicKey } from "@solana/web3.js";

/** Solana devnet chain selector. The local Surfnet plays this chain. */
export const SVM_CHAIN_SELECTOR = 16423721717087811551n;
/** Ethereum Sepolia chain selector. Default source chain of delivered messages. */
export const EVM_CHAIN_SELECTOR = 16015286601757825753n;

/** `bytes4(keccak256("CommitteeVerifier 2.0.0"))`, the version tag of verifier results. */
export const CCV_VERSION_TAG = Uint8Array.from([0xe9, 0xa0, 0x5a, 0x20]);

export const BPF_LOADER_UPGRADEABLE = new PublicKey("BPFLoaderUpgradeab1e11111111111111111111111");
export const ADDRESS_LOOKUP_TABLE_PROGRAM = new PublicKey("AddressLookupTab1e1111111111111111111111111");

export const SEEDS = {
  config: "config",
  curses: "curses",
  referenceAddresses: "reference_addresses",
  sourceChain: "source_chain_state",
  remoteChain: "remote_chain",
  storageLocations: "storage_locations",
  ccvSigner: "ccv_signer",
} as const;

export function pda(seeds: (Uint8Array | Buffer)[], programId: PublicKey): PublicKey {
  return PublicKey.findProgramAddressSync(seeds, programId)[0];
}

export function programDataAddress(programId: PublicKey): PublicKey {
  return pda([programId.toBuffer()], BPF_LOADER_UPGRADEABLE);
}

/** Chain selector as the 8 little-endian bytes used in PDA seeds. */
export function selectorSeed(selector: bigint): Buffer {
  const buf = Buffer.alloc(8);
  buf.writeBigUInt64LE(selector);
  return buf;
}
