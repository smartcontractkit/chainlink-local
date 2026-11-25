// Fetches, verifies and caches the pinned CCIP 2.0 Solana program bundle.
//
// Ported in part from the prototype by Stefano Magini (magiodev-cll/chainlink-local, feat/svm-local,
// src/ccip-svm/src/artifacts.ts): the "download, check sha256, shell out to tar" flow and the
// `target/deploy` + `target/idl` layout. The pin is now an immutable tagged release, not `latest`.

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

/**
 * Pinned release of `smartcontractkit/chainlink-ccip-solana`. The release is immutable; the digest
 * guards against a corrupted or tampered download.
 */
export const ARTIFACTS = {
  release: "contracts/v2.1.0",
  url: "https://github.com/smartcontractkit/chainlink-ccip-solana/releases/download/contracts/v2.1.0/artifacts.tar.gz",
  sha256: "ee365476da3854ee28e0232f1f1fc9937fccad2a6bfe6fe49f9943fe6d94fbb2",
} as const;

/** Points at an already-extracted bundle (a directory that contains `target/deploy`). */
export const ENV_ARTIFACTS = "CHAINLINK_LOCAL_SVM_ARTIFACTS";
/** `1` forbids any download. */
export const ENV_OFFLINE = "CHAINLINK_LOCAL_SVM_OFFLINE";

export interface ResolveOptions {
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
  const override = process.env[ENV_ARTIFACTS];
  if (override) {
    if (!isBundle(override)) {
      throw new Error(
        `${ENV_ARTIFACTS}=${override} does not contain target/deploy and target/idl. ` +
          `Point it at the directory that holds the "target" folder of an extracted artifacts.tar.gz, ` +
          `or unset it to use the pinned download.`,
      );
    }
    return override;
  }

  const cacheDir = options.cacheDir ?? defaultCacheDir();
  const bundleDir = path.join(cacheDir, ARTIFACTS.release.replace("/", "-"));
  if (isBundle(bundleDir)) return bundleDir;

  if (process.env[ENV_OFFLINE] === "1") {
    throw new Error(
      `${ENV_OFFLINE}=1 forbids downloading the CCIP Solana programs (${ARTIFACTS.release}), and ` +
        `${bundleDir} is empty. Either unset ${ENV_OFFLINE} once to populate the cache, or download ` +
        `${ARTIFACTS.url}, extract it and set ${ENV_ARTIFACTS} to the extracted directory.`,
    );
  }

  const response = await fetch(ARTIFACTS.url);
  if (!response.ok) {
    throw new Error(
      `Downloading ${ARTIFACTS.url} failed with HTTP ${response.status}. ` +
        `Check your network, or set ${ENV_ARTIFACTS} to an already-extracted bundle.`,
    );
  }
  const tarball = Buffer.from(await response.arrayBuffer());
  const digest = createHash("sha256").update(tarball).digest("hex");
  if (digest !== ARTIFACTS.sha256) {
    throw new Error(
      `Digest mismatch for ${ARTIFACTS.url}: expected sha256 ${ARTIFACTS.sha256}, got ${digest}. ` +
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
      throw new Error(`${ARTIFACTS.url} did not contain target/deploy and target/idl.`);
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
