# Chainlink Local - Agents Guide

Guide for AI coding agents working in `smartcontractkit/chainlink-local`.

## What this library does

Chainlink Local is a developer-focused testing package that simulates Chainlink services (especially CCIP) in local and forked environments.

- Local mode (`CCIPLocalSimulator`, `DataStreamsLocalSimulator`) lets developers test app logic quickly without waiting for live offchain systems.
- Fork mode (`CCIPLocalSimulatorFork`, `DataStreamsLocalSimulatorFork`) runs against forked networks so integrations behave closer to real testnet conditions.
- The intent is parity of user app behavior between local/fork testing and testnet deployment (minus environment-specific addresses/config).
- It is available for usage in Foundry, Hardhat 3, Hardhat 2 and Remix IDE environments.
- Official documentation is available at: https://docs.chain.link/chainlink-local

## Goal
- Make minimal, correct changes that preserve simulator behavior and test ergonomics.
- Prefer targeted edits and targeted tests over broad refactors.

## Context Budget First
Load files in this order and stop as soon as you have enough context:
1. `package.json` (scripts, versions, docs/release commands)
2. `foundry.toml` and `hardhat.config.ts` (tooling layout)
3. Only the relevant `src/**` files and matching tests in `test/**`
4. If docs task: `helper_doc/*.mjs` and `api_reference/**`
5. If release/publish task: `.github/workflows/publish.yml`

Avoid loading large/unnecessary trees unless explicitly required:
- `lib/**`, `out/**`, `cache/**`, `artifacts/**`, `node_modules/**`

## Directory layout
- `src/`: production contracts by service (`ccip`, `data-feeds`, `data-streams`)
- `src/test/`: helper/example contracts used by tests
- `test/smoke/`: local-mode tests
- `test/e2e/`: fork-mode tests
- `test/unit/`: unit-level tests
- `scripts/`: helpers for Hardhat users that write tests using JavaScript or TypeScript
- `helper_doc/`: docs generation scripts (you shouldn't touch these)
- `api_reference/`: generated docs output (read only; do not edit directly)

## Hard Rules
- Never edit `lib/**`. If user explicitly asks, use forge for dependency management.
- Never edit `node_modules/**`. If user explicitly asks, use npm for dependency management.
- Keep changes surgical; do not refactor unrelated code.
- Preserve test placement conventions:
  - local mode -> `test/smoke/**`
  - fork mode -> `test/e2e/**`
- Do not hand-edit generated docs in `api_reference/**`; regenerate via scripts.
- If a command fails after deleting generated docs, restore state before continuing.

## Common Commands
- Compile:
  - `npm run forge-compile`
  - `npm run hardhat-compile`
- Test:
  - `npm run forge-test`
  - `npm run hardhat-test`
  - `forge test <path-to-test>`
- Docs:
  - `npm run generate-docs` (deterministic; does not fetch Register data)
  - `npm run update-register` (networked; updates `src/ccip/Register.sol`)

## Release and Publish
For the full release workflow (beta, stable, branch policy, CHANGELOG requirements), see [`.agent/playbooks/RELEASE_PLAYBOOK.md`](.agent/playbooks/RELEASE_PLAYBOOK.md).

## Dependency Policy
- Keep `@chainlink/contracts` and `@chainlink/contracts-ccip` as direct `dependencies`.
- Avoid introducing new tooling dependencies unless there is a clear maintenance win.
- If bumping Chainlink packages, do not move them to `devDependencies` or `peerDependencies`.

### Current core npm dependency versions
| Package | Version |
| --- | --- |
| `@chainlink/contracts-ccip` | `1.6.2` |
| `@chainlink/contracts` | `1.5.0` |

## Dependency Update Playbook
Use these commands unless a maintainer requests something different.

### npm / Hardhat dependencies
- Add runtime dependency:
  - `npm install <package>@<version>`
- Add dev dependency:
  - `npm install --save-dev <package>@<version>`
- Update existing dependency:
  - `npm install <package>@<new-version>`
- Verify:
  - check `package.json` (`dependencies` vs `devDependencies` placement)
  - run the smallest relevant compile/test command
- Example (`@chainlink/contracts` -> `1.2.0`):
  - `npm install @chainlink/contracts@1.2.0`

### Foundry dependencies
- Optional: pull latest submodule state first (all or specific):
  - `forge update`
  - `forge update lib/chainlink-evm lib/chainlink-ccip`
- Install/update with pinned tag:
  - `forge install <org>/<repo>@<tag>`
- For direct dependencies:
  - `@chainlink/contracts` equivalent:
    - `forge install smartcontractkit/chainlink-evm@contracts-v<version>`
  - `@chainlink/contracts-ccip` equivalent:
    - `forge install smartcontractkit/chainlink-ccip@contracts-ccip-v<version>`
- Historical note:
  - older docs may reference `chainlink-brownie-contracts`; this repo uses `chainlink-evm`.
- After install:
  - verify `lib/` points to the expected tag/commit
  - verify npm versions in `package.json`
  - run `forge build` and relevant tests
  - never edit vendored files manually inside `lib/**` or `node_modules/**`

## Change Checklist
Before finishing:
1. Run the smallest relevant compile/test command(s).
2. Regenerate docs if your change affects docs sources.
3. Confirm no accidental edits in unrelated files.
4. Summarize:
   - what changed
   - what was intentionally not touched
   - any residual risk or follow-up

## Known Good Defaults
- Node.js `22.x` is the safe default for workflow parity.
- Prefer `rg` for search.
- Prefer explicit, boring solutions over abstraction-heavy changes.