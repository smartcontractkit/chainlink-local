# Release Playbook

Step-by-step guide for publishing beta and stable releases of `@chainlink/local`.

## Release and Publish Rules
- Publishing workflow: `.github/workflows/publish.yml`
- Triggers:
  - automatic on tag push `v*`
  - manual fallback via `workflow_dispatch`
- Before publishing any beta or stable release, `CHANGELOG.md` must be updated for that version using [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
- Version check:
  - tag version must match `package.json` version
- Branch policy:
  - beta tag (`vX.Y.Z-beta`) must come from `develop`
  - stable tag (`vX.Y.Z`) must come from `main`

## Feature Development (beta track)
1. Branch from `develop` (for example `feat/<name>`, or `devrel-123/<name>`).
2. Open a draft PR targeting `develop`.
3. Commit incrementally using [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
4. Keep docs/tests updated (`npm run generate-docs` when docs sources changed).
5. Mark PR ready, get review, merge into `develop`.

## Publish Beta Release
1. Ensure `package.json` version is beta-formatted (for example `0.3.1-beta`).
2. Update `CHANGELOG.md` for the new release using [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) + [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
3. Draft GitHub release with:
   - tag: `v<version>-beta`
   - target: `develop`
   - pre-release: enabled
   - release title: `v<version>-beta`
4. Publish the release (tag push triggers publish workflow automatically).
5. If needed, use manual `workflow_dispatch` fallback from `develop` with `release_type=beta`.

## Promote to Stable Release
1. Open PR from `develop` to `main`.
2. Update `package.json` version to stable (remove `-beta` suffix).
3. Update `CHANGELOG.md` for the stable release using [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) + [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
4. Merge into `main` after review.
5. Draft GitHub release with:
   - tag: `v<version>`
   - target: `main`
   - pre-release: disabled
   - release title: `v<version>`
6. Publish release (tag push triggers stable publish automatically).
7. If needed, run manual fallback from `main` with `release_type=stable`.