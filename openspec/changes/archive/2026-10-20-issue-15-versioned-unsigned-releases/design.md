# Design

## Context

`VERSION` is the existing version source, but it records separate GUI and CLI versions. The GUI version is the version resource and filename source for the Windows EXE. `tools/Build-InstallerExe.ps1` already verifies the script versions, compatibility contract, clean source revision, x64 output, unsigned state, toolchain pins, and payload inventory. `.github/workflows/windows-build-compatibility.yml` already runs the required Desktop 5.1 and Core 7.6.7 matrix.

## Goals / Non-Goals

**Goals:**

- Keep release version selection tied to the documented GUI version while checking both script version entries.
- Reuse the existing compatibility workflow and builder instead of defining a second test matrix or build implementation.
- Fail closed on an unprotected, mismatched, unmerged, duplicate, incomplete, signed, or changed release artifact.
- Make release publication a final step after all gates, with no Actions artifact handoff or custom secret.

**Non-Goals:**

- Consolidating GUI and CLI product versions, which is outside this issue.
- Signing, timestamping, generating certificates, creating or pushing tags, or publishing a real release during implementation.
- Supporting Windows ARM64 or universal executables without a matching verified build.

## Decisions

1. **Use `v<GUI-version>` as the stable tag.** The existing executable uses the GUI version from `VERSION`; no separate release version is invented. A validator reuses the builder's GUI and CLI version contract and rejects malformed tags, leading-zero numeric components, or a tag mismatch.
2. **Call the current compatibility workflow as a reusable workflow.** Add `workflow_call` support and keep its existing push, pull request, and manual behavior. The release caller waits for both engine jobs. The final release job invokes the same pinned builder again after the matrix succeeds, avoiding artifact storage and its account quota while sharing build logic and pins.
3. **Require the protected-ref signal and a default-branch commit.** The caller checks `github.ref_protected`, verifies the remote tag still targets the event commit, and requires the commit to be reachable from the repository's default branch. It also requires the workflow files at the tagged commit to match the default branch so the release API does not need unavailable workflow-write permission.
4. **Prepare assets before publication.** A local PowerShell module validates the builder manifest and executable, copies the expected versioned x64 EXE into a fresh staging directory, writes its SHA-256 sidecar, and creates a release manifest and notes. The manifest carries the builder toolchain and payload inventory, compatibility data, tag and commit, and both passing engine results.
5. **Use the release REST API with `contents: write` only in the final job.** The publisher checks for an existing release, creates a draft, uploads the exact allowlisted files, then changes the draft to published. API errors stop the sequence. The publisher does not create tags, overwrite assets, or invoke signing tools.
6. **Test with fixtures and mocked API responses.** Release tests exercise tag syntax, version consistency, missing and duplicate files, digest matching, unsigned state, exact asset names, duplicate release rejection, failed uploads, and publish gating without network requests or real release writes.

## Risks / Trade-offs

- **No tag ruleset may currently protect `v*`.** The workflow requires GitHub's protected-ref signal and therefore refuses publication until an owner configures tag protection. This setting cannot be established by a repository-local workflow file.
- **The GitHub release API can reject a tag commit that changes workflow files relative to the default branch.** The publish gate checks default-branch ancestry and workflow-file equality; failures remain unpublished.
- **The second build adds runner time.** Standard GitHub-hosted runner minutes are free for this public repository, while the duplicate build avoids use of metered Actions artifact storage.
- **A failed upload can leave a draft.** The publisher never makes that draft public after a failed upload; a maintainer must remove or repair the draft before retrying the same tag.
- **Checksums do not establish publisher identity.** The release notes and manifest state that a digest detects byte changes only when the expected digest comes from a trusted release channel; it does not authenticate the publisher or replace a signature.

## Migration Plan

1. Merge the reusable workflow, tag validator, asset builder, publisher, tests, and release documentation through the default branch.
2. Configure a GitHub ruleset or tag protection rule for `v*` and allow the release job to use the repository `GITHUB_TOKEN` with `contents: write`.
3. Create a semantic-version tag only after reviewing the version source and default-branch commit. The workflow validates and publishes that already-existing tag.
4. If release preparation or upload fails, no public release is published. Remove or correct any remaining draft before retrying; do not move a tag to hide a provenance mismatch.

## Open Questions

None. The tag protection ruleset is an explicit release prerequisite and will be reported as unverified until checked in repository settings.
