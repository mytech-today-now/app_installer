# Tasks

## 1. Version policy and user-visible metadata

- [x] 1.1 Confirm VERSION entries, ScriptVersion assignments, Git tags, and current release workflow behavior.
- [x] 1.2 Keep GUI 2.0.6 as the executable release version and CLI 2.0.2 as its separate script version.
- [x] 1.3 Correct current script headers and startup banners without changing historical version records.
- [x] 1.4 Document the exact mapping and stable-only release policy in README and release notes.

## 2. Build and release validation

- [x] 2.1 Reject malformed, missing, duplicate, prerelease, stale, or mismatched current version declarations.
- [x] 2.2 Validate README mappings, EXE file properties, versioned artifact name, and release manifest from VERSION.
- [x] 2.3 Reject build provenance whose source commit differs from the validated release commit.

## 3. Verification and tracking

- [x] 3.1 Run focused version, build, release asset, workflow, and syntax checks under available PowerShell engines.
- [x] 3.2 Update report issue-18 and verify Beads and OpenSpec status without creating tags or publishing a release.
