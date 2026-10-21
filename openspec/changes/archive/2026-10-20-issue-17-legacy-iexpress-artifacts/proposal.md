# Proposal

## Why

Two tracked executables have different histories and build roles, while the README still shows the older file as a runnable product. This change records the evidence and keeps the current versioned release path distinct from both legacy files.

## What Changes

- Record identity, tracked history, hashes, release eligibility, build role, and known provenance limits for both existing executables without changing their bytes.
- Protect both legacy paths from new build output and label the versioned release artifact in builder provenance.
- Require release preparation to validate the current artifact identity and the adjacent build manifest before staging assets.
- Update README guidance and examples to identify the supported versioned release, its prerequisites, and the unknown status of legacy artifacts.
- Add offline checks for legacy path protection, manifest selection, and unchanged legacy hashes.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `versioned-unsigned-releases`: Require the release workflow to select the current versioned artifact and its matching provenance, while preserving and excluding legacy executables.

## Impact

Updates the build metadata and guard, release asset validation, focused build and release tests, README and changelog guidance, and the versioned release specification. No dependencies or release publication behavior are added. Neither legacy executable is executed, renamed, deleted, or overwritten.
