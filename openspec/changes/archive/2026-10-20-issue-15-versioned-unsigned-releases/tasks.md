# Tasks

## 1. Tag and asset contract

- [x] 1.1 Add release tag validation tied to `VERSION` and both script version fields; verify valid, malformed, leading-zero, and mismatched tags with fixture cases.
- [x] 1.2 Add release asset preparation for the exact x64 EXE, SHA-256 sidecar, builder provenance, release manifest, and notes; verify duplicate, missing, changed, signed, and incomplete outputs fail without overwrites.
- [x] 1.3 Include source commit, build tools, compatibility data, payload inventory, and successful Desktop 5.1/Core 7.6.7 evidence in the release manifest; verify all fields in fixtures.

## 2. Gated GitHub workflow

- [x] 2.1 Make the existing compatibility workflow reusable without changing its current triggers, runner, matrix, or manual artifact opt-in; verify its workflow contract on both PowerShell engines.
- [x] 2.2 Add a protected semantic-tag release workflow with default-branch and workflow-file gates, `contents: read` validation, and a final `contents: write` job; verify triggers, permissions, immutable action pins, and fail-closed conditions offline.
- [x] 2.3 Implement duplicate-safe draft creation, allowlisted asset uploads, and publication after all uploads; verify no-release, duplicate-release, upload-failure, and successful mock API sequences without network access.

## 3. Release guidance and integration

- [x] 3.1 Document the tag rule, asset names, support and invocation matrix, recovery steps, unsigned status, checksum limitations, free-runner evidence, and external tag-protection prerequisite; verify the documented names and version source match the implementation.
- [x] 3.2 Run the focused release fixture, workflow, and syntax checks; run the release simulation and verify no tag or public release was created.

## Workflow follow-up

- Archive this OpenSpec change and close its matching Bead only after the fixture release simulation succeeds.
- Do not create or push a release tag or publish a real release during this implementation.
