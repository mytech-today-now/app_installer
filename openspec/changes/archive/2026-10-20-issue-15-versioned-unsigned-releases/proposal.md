# Proposal

## Why

The repository has a deterministic unsigned x64 executable builder and a public compatibility workflow, but no tag-driven release path that binds an executable to a semantic version, source commit, payload inventory, and verifiable digest. A gated release workflow makes those facts visible before users download the binary.

Source finding: `ai-prompts/pre-mortem-2026-10-17-12-01-24.html#issue-15`.

## What Changes

- Validate stable `vMAJOR.MINOR.PATCH` tags against the existing GUI version entry in `VERSION` and the GUI and CLI script metadata.
- Reuse the existing Windows PowerShell compatibility workflow and pinned executable builder for release gates.
- Publish one unsigned x64 EXE with a SHA-256 sidecar, build provenance, release manifest, and complete compatibility and recovery notes.
- Require a protected tag and successful test matrix, reject duplicate releases, and keep the GitHub release unpublished until all assets are uploaded.
- Add fixture-based release tests and document the release format and checksum limits.

## Capabilities

### New Capabilities

- `versioned-unsigned-releases`: Validate protected semantic-version tags and publish one gated, unsigned x64 executable with verifiable release metadata.

### Modified Capabilities

None.

## Impact

Updates the Windows build workflow to support reuse, adds a tag-triggered release workflow and PowerShell release tooling, extends focused workflow and artifact tests, and documents the release contract. It uses the existing build system and GitHub's standard hosted Windows runner and release API. No new dependencies, signing service, certificate, or custom secret is introduced.
