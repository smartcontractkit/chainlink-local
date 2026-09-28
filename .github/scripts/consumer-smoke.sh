#!/usr/bin/env bash
# Consumer smoke test for the @chainlink/local npm tarball.
#
# Packs the repo (npm pack), then builds two throwaway consumer projects that install ONLY the
# published tarball (plus hardhat for the Hardhat consumer) and run two Solidity tests against it:
#   1. The README usage example (test/smoke/ccip/ReadmeUsageExample.t.sol), copied verbatim.
#   2. A CCIPLocalSimulatorFork smoke test asserting known Sepolia network details.
#
# Assumes `npm ci` has already been run in the repo (this script does not install repo devDependencies).
# Needs network access to registry.npmjs.org (tarball deps) and github.com (forge-std is a git dependency).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chainlink-local-consumer-smoke.XXXXXX")"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

log() { printf '\n==> %s\n' "$1"; }

# ---------------------------------------------------------------------------
# 1. Pack the repo and sanity-check the tarball / repo state around npm pack.
# ---------------------------------------------------------------------------
log "Packing repo with npm pack"
PACK_DIR="$WORK_DIR/pack"
mkdir -p "$PACK_DIR"

(cd "$REPO_ROOT" && npm pack --silent --pack-destination "$PACK_DIR")

shopt -s nullglob
TGZ_FILES=("$PACK_DIR"/*.tgz)
shopt -u nullglob
if [[ ${#TGZ_FILES[@]} -ne 1 ]]; then
  echo "FAIL: expected exactly one tarball in $PACK_DIR, found ${#TGZ_FILES[@]}" >&2
  exit 1
fi
TGZ="${TGZ_FILES[0]}"
log "Tarball: $TGZ"

log "Checking repo remappings.txt is unchanged after npm pack (prepack/postpack must restore it)"
(cd "$REPO_ROOT" && git diff --exit-code -- remappings.txt)
echo "OK: remappings.txt unchanged"

log "Checking tarball's package/remappings.txt uses the node_modules variant"
TARBALL_REMAPPINGS="$(tar -xzO -f "$TGZ" package/remappings.txt)"
EXPECTED_REMAPPINGS="$(cat "$REPO_ROOT/remappings-npm.txt")"
if [[ "$TARBALL_REMAPPINGS" != "$EXPECTED_REMAPPINGS" ]]; then
  echo "FAIL: tarball package/remappings.txt does not match repo remappings-npm.txt" >&2
  echo "--- tarball ---" >&2
  echo "$TARBALL_REMAPPINGS" >&2
  echo "--- expected (remappings-npm.txt) ---" >&2
  echo "$EXPECTED_REMAPPINGS" >&2
  exit 1
fi
echo "OK: tarball remappings.txt matches the node_modules variant"

README_TEST_SRC="$REPO_ROOT/test/smoke/ccip/ReadmeUsageExample.t.sol"
if [[ ! -f "$README_TEST_SRC" ]]; then
  echo "FAIL: $README_TEST_SRC not found" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Shared second test: CCIPLocalSimulatorFork smoke test against Sepolia network details.
# ---------------------------------------------------------------------------
write_network_details_test() {
  local dest="$1"
  cat > "$dest" <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {Register} from "@chainlink/local/src/ccip/Register.sol";

contract NetworkDetailsSmokeTest is Test {
    function test_sepoliaNetworkDetailsAndStrictRouting() public {
        CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();

        Register.NetworkDetails memory details = ccipLocalSimulatorFork.getNetworkDetails(11155111);
        assertEq(details.chainSelector, 16015286601757825753);
        assertTrue(ccipLocalSimulatorFork.getStrictRouting());
    }
}
EOF
}

# ---------------------------------------------------------------------------
# 3. Hardhat 3 consumer (npm install of the tarball only, plus hardhat).
# ---------------------------------------------------------------------------
log "Building Hardhat 3 consumer"
HH_DIR="$WORK_DIR/hardhat-consumer"
mkdir -p "$HH_DIR/test"
cd "$HH_DIR"

cat > package.json <<EOF
{
  "name": "chainlink-local-consumer-hardhat-smoke",
  "private": true,
  "type": "module",
  "version": "0.0.0"
}
EOF

npm install --silent --no-audit --no-fund "$TGZ" hardhat@3.1.10

cat > hardhat.config.ts <<'EOF'
import { defineConfig } from "hardhat/config";

export default defineConfig({
  solidity: {
    version: "0.8.24",
    settings: {
      evmVersion: "cancun",
    },
  },
});
EOF

cp "$README_TEST_SRC" test/ReadmeUsageExample.t.sol
write_network_details_test test/NetworkDetails.t.sol

log "Running npx hardhat test solidity (Hardhat consumer)"
npx hardhat test solidity

# ---------------------------------------------------------------------------
# 4. Foundry consumer (npm install of the tarball only).
# ---------------------------------------------------------------------------
log "Building Foundry (npm) consumer"
FOUNDRY_DIR="$WORK_DIR/foundry-consumer"
mkdir -p "$FOUNDRY_DIR/test"
cd "$FOUNDRY_DIR"

cat > package.json <<EOF
{
  "name": "chainlink-local-consumer-foundry-smoke",
  "private": true,
  "version": "0.0.0"
}
EOF

npm install --silent --no-audit --no-fund "$TGZ"

cat > foundry.toml <<'EOF'
[profile.default]
libs = ["node_modules"]
evm_version = "cancun"
EOF

# Exact lines from README's "Foundry (npm)" installation section.
cat > remappings.txt <<'EOF'
@chainlink/local/=node_modules/@chainlink/local/
@chainlink/contracts-ccip/=node_modules/@chainlink/contracts-ccip/
@chainlink/contracts/=node_modules/@chainlink/contracts/
@openzeppelin/contracts@4.8.3/=node_modules/@openzeppelin/contracts-4.8.3/
@openzeppelin/contracts@5.3.0/=node_modules/@openzeppelin/contracts-5.3.0/
forge-std/=node_modules/forge-std/src/
EOF

# Fail when README drifts from the remappings tested here.
while IFS= read -r line; do
  if ! grep -qxF "$line" "$REPO_ROOT/README.md"; then
    echo "FAIL: README.md no longer lists the Foundry (npm) remapping: $line" >&2
    exit 1
  fi
done < remappings.txt

cp "$README_TEST_SRC" test/ReadmeUsageExample.t.sol
write_network_details_test test/NetworkDetails.t.sol

log "Running forge test (Foundry consumer)"
forge test

log "Consumer smoke tests passed"
