// Fetches, verifies and caches the pinned CCIP Solana program bundles (2.0 and 1.6).
//
// Ported in part from the prototype by Stefano Magini (magiodev-cll/chainlink-local, feat/svm-local,
// src/ccip-svm/src/artifacts.ts): the "download, check sha256, shell out to tar" flow and the
// `target/deploy` + `target/idl` layout. The pin is now an immutable tagged release, not `latest`.

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

/** CCIP version of a lane: which Solana programs run on the local chain. */
export type CcipVersion = "2.0" | "1.6";

/**
 * Pinned release per CCIP version. The releases are immutable; the digest guards against a corrupted or
 * tampered download. "2.0" is `smartcontractkit/chainlink-ccip-solana` contracts/v2.1.0. "1.6" is
 * `smartcontractkit/chainlink-ccip` solana-v1.6.4, whose single asset has no checksum file, so the digest is the
 * one GitHub shows for the asset.
 */
export const BUNDLES = {
  "2.0": {
    release: "contracts/v2.1.0",
    url: "https://github.com/smartcontractkit/chainlink-ccip-solana/releases/download/contracts/v2.1.0/artifacts.tar.gz",
    sha256: "ee365476da3854ee28e0232f1f1fc9937fccad2a6bfe6fe49f9943fe6d94fbb2",
  },
  "1.6": {
    release: "solana-v1.6.4",
    url: "https://github.com/smartcontractkit/chainlink-ccip/releases/download/solana-v1.6.4/artifacts.tar.gz",
    sha256: "d6305e9dfb42337716d0ef8dc0cf7a4b20a3e1a28dc6de6cd3f48271c271a5ff",
  },
} as const satisfies Record<CcipVersion, { release: string; url: string; sha256: string }>;

/** The CCIP 2.0 pin, kept for callers that predate `ccipVersion`. */
export const ARTIFACTS = BUNDLES["2.0"];

/** Points at an already-extracted CCIP 2.0 bundle (a directory that contains `target/deploy`). */
export const ENV_ARTIFACTS = "CHAINLINK_LOCAL_SVM_ARTIFACTS";
/** The same for the CCIP 1.6 bundle. A separate variable, so one setting cannot point a lane at the other version's programs. */
export const ENV_ARTIFACTS_1_6 = "CHAINLINK_LOCAL_SVM_ARTIFACTS_1_6";
const ENV_ARTIFACTS_BY_VERSION: Record<CcipVersion, string> = { "2.0": ENV_ARTIFACTS, "1.6": ENV_ARTIFACTS_1_6 };
/** `1` forbids any download. */
export const ENV_OFFLINE = "CHAINLINK_LOCAL_SVM_OFFLINE";

export interface ResolveOptions {
  /** Which bundle to resolve. Default "2.0". */
  ccipVersion?: CcipVersion;
  /** Cache directory. Defaults to `~/.cache/chainlink-local/svm`. */
  cacheDir?: string;
}

export function defaultCacheDir(): string {
  return path.join(os.homedir(), ".cache", "chainlink-local", "svm");
}

/** A bundle is a directory that contains `target/deploy` and `target/idl`. */
function isBundle(dir: string): boolean {
  return (
    fs.existsSync(path.join(dir, "target", "deploy")) &&
    fs.existsSync(path.join(dir, "target", "idl"))
  );
}

/**
 * Returns the directory that contains `target/deploy` and `target/idl`, downloading and verifying
 * the pinned bundle on first use.
 */
export async function resolveArtifacts(options: ResolveOptions = {}): Promise<string> {
  const bundle = BUNDLES[options.ccipVersion ?? "2.0"];
  const envName = ENV_ARTIFACTS_BY_VERSION[options.ccipVersion ?? "2.0"];
  const override = process.env[envName];
  if (override) {
    if (!isBundle(override)) {
      throw new Error(
        `${envName}=${override} does not contain target/deploy and target/idl. ` +
          `Point it at the directory that holds the "target" folder of an extracted artifacts.tar.gz, ` +
          `or unset it to use the pinned download.`,
      );
    }
    return override;
  }

  const cacheDir = options.cacheDir ?? defaultCacheDir();
  const bundleDir = path.join(cacheDir, bundle.release.replace("/", "-"));
  if (isBundle(bundleDir)) return bundleDir;

  if (process.env[ENV_OFFLINE] === "1") {
    throw new Error(
      `${ENV_OFFLINE}=1 forbids downloading the CCIP Solana programs (${bundle.release}), and ` +
        `${bundleDir} is empty. Either unset ${ENV_OFFLINE} once to populate the cache, or download ` +
        `${bundle.url}, extract it and set ${envName} to the extracted directory.`,
    );
  }

  const response = await fetch(bundle.url);
  if (!response.ok) {
    throw new Error(
      `Downloading ${bundle.url} failed with HTTP ${response.status}. ` +
        `Check your network, or set ${envName} to an already-extracted bundle.`,
    );
  }
  const tarball = Buffer.from(await response.arrayBuffer());
  const digest = createHash("sha256").update(tarball).digest("hex");
  if (digest !== bundle.sha256) {
    throw new Error(
      `Digest mismatch for ${bundle.url}: expected sha256 ${bundle.sha256}, got ${digest}. ` +
        `Nothing was extracted. Retry the download; if it persists, the file is corrupted or has been ` +
        `tampered with, so do not use it.`,
    );
  }

  // Extract next to the final location, then rename, so an interrupted run never leaves a
  // half-extracted directory that looks like a valid cache entry.
  fs.mkdirSync(cacheDir, { recursive: true });
  const staging = fs.mkdtempSync(path.join(cacheDir, ".extract-"));
  try {
    const tarballPath = path.join(staging, "artifacts.tar.gz");
    fs.writeFileSync(tarballPath, tarball);
    const extracted = path.join(staging, "bundle");
    fs.mkdirSync(extracted);
    execFileSync("tar", ["-xzf", tarballPath, "-C", extracted], { stdio: "ignore" });
    if (!isBundle(extracted)) {
      throw new Error(`${bundle.url} did not contain target/deploy and target/idl.`);
    }
    fs.rmSync(bundleDir, { recursive: true, force: true });
    fs.renameSync(extracted, bundleDir);
  } finally {
    fs.rmSync(staging, { recursive: true, force: true });
  }
  return bundleDir;
}

export function readProgram(bundleDir: string, name: string): Buffer {
  return fs.readFileSync(path.join(bundleDir, "target", "deploy", `${name}.so`));
}

export function readIdl(bundleDir: string, name: string): { address: string } & Record<string, unknown> {
  return JSON.parse(fs.readFileSync(path.join(bundleDir, "target", "idl", `${name}.json`), "utf8"));
}
