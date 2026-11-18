import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, it, mock } from "node:test";
import { ARTIFACTS, ENV_ARTIFACTS, ENV_OFFLINE, resolveArtifacts } from "../../../scripts/svm/artifacts.ts";

describe("resolveArtifacts", () => {
  let cacheDir: string;
  const savedEnv = { ...process.env };

  beforeEach(() => {
    cacheDir = fs.mkdtempSync(path.join(os.tmpdir(), "svm-artifacts-"));
    delete process.env[ENV_ARTIFACTS];
    delete process.env[ENV_OFFLINE];
  });

  afterEach(() => {
    mock.restoreAll();
    process.env = { ...savedEnv };
    fs.rmSync(cacheDir, { recursive: true, force: true });
  });

  it("uses the cache and makes no download on a hit", async () => {
    const bundle = path.join(cacheDir, ARTIFACTS.release.replace("/", "-"));
    fs.mkdirSync(path.join(bundle, "target", "deploy"), { recursive: true });
    fs.mkdirSync(path.join(bundle, "target", "idl"), { recursive: true });
    const fetchMock = mock.method(globalThis, "fetch", async () => {
      throw new Error("fetch must not be called");
    });

    assert.equal(await resolveArtifacts({ cacheDir }), bundle);
    assert.equal(fetchMock.mock.callCount(), 0);
  });

  it("rejects a download whose sha256 is wrong, and extracts nothing", async () => {
    mock.method(globalThis, "fetch", async () => new Response(Buffer.from("not the real tarball")));

    await assert.rejects(resolveArtifacts({ cacheDir }), /Digest mismatch.*expected sha256 [0-9a-f]{64}, got [0-9a-f]{64}/s);
    assert.deepEqual(fs.readdirSync(cacheDir), []);
  });

  it("fails a cold cache in offline mode with instructions, without downloading", async () => {
    process.env[ENV_OFFLINE] = "1";
    const fetchMock = mock.method(globalThis, "fetch", async () => {
      throw new Error("fetch must not be called");
    });

    await assert.rejects(resolveArtifacts({ cacheDir }), (error: Error) => {
      assert.match(error.message, new RegExp(ENV_OFFLINE));
      assert.match(error.message, new RegExp(ENV_ARTIFACTS));
      return true;
    });
    assert.equal(fetchMock.mock.callCount(), 0);
  });

  it("honours the override variable and skips the cache and the network", async () => {
    const extracted = path.join(cacheDir, "mine");
    fs.mkdirSync(path.join(extracted, "target", "deploy"), { recursive: true });
    fs.mkdirSync(path.join(extracted, "target", "idl"), { recursive: true });
    process.env[ENV_ARTIFACTS] = extracted;
    const fetchMock = mock.method(globalThis, "fetch", async () => {
      throw new Error("fetch must not be called");
    });

    assert.equal(await resolveArtifacts({ cacheDir: path.join(cacheDir, "unused") }), extracted);
    assert.equal(fetchMock.mock.callCount(), 0);
  });

  it("rejects an override that is not a bundle", async () => {
    process.env[ENV_ARTIFACTS] = cacheDir;
    await assert.rejects(resolveArtifacts(), /does not contain target\/deploy/);
  });
});
