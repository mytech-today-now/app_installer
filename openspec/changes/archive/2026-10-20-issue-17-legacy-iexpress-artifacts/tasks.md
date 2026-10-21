# Tasks

## 1. Artifact inventory and build separation

- [x] 1.1 Record hashes, tracked commit history, available file metadata, role, release eligibility, and provenance limits for both legacy files.
- [x] 1.2 Protect both legacy paths in the builder and identify current versioned build output in its provenance manifest.
- [x] 1.3 Add tests proving the current output is versioned, neither legacy path can be selected, and both legacy hashes remain unchanged.

## 2. Release selection and user guidance

- [x] 2.1 Require release preparation to validate the current artifact identity, configured versioned filename, adjacent build manifest, and artifact digest.
- [x] 2.2 Verify release staging includes only the configured versioned artifact and its allowlisted metadata.
- [x] 2.3 Update README and changelog guidance with artifact roles, prerequisites, reproducibility instructions, and unknown legacy provenance. Remove runnable examples for legacy paths.

## 3. Validation and tracking

- [x] 3.1 Run the focused builder, release asset, workflow contract, and syntax checks. Confirm both legacy executable hashes are unchanged.
- [x] 3.2 Update issue-17 status and archive this OpenSpec change after the evidence is recorded. Do not create a release or remove files.
