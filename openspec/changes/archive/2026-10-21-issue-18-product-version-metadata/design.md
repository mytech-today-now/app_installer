# Design

## Context

VERSION already stores the current GUI and CLI script versions separately. The builder uses the GUI value for the four-part EXE file version and versioned output name, and release tag validation requires the tag to match the GUI value. See proposal.md for the release policy.

## Goals / Non-Goals

**Goals:**

- Keep VERSION as the single source for both current script versions.
- Fail validation when current declarations or generated release metadata drift.
- Keep the GUI and CLI version mapping visible in user-facing release information.

**Non-Goals:**

- Generate new script versions or rewrite historical version records.
- Add prerelease support or change existing release tags.
- Rewrite either tracked legacy executable.

## Decisions

- Reuse VERSION rather than introduce another version manifest. It already contains the current GUI and CLI values and is used by payload integrity and release tooling.
- Treat the GUI value as the executable release version because the current Windows EXE launches the GUI package. Keep the CLI script at its existing independent version and include both values in release metadata and notes.
- Require stable three-part semantic versions. Prerelease and build-metadata forms remain unsupported because the workflow accepts only stable vMAJOR.MINOR.PATCH tags.
- Validate the source assignments, script headers, README declarations, release tag, output name, file resource, and release manifest against the current VERSION entries. Verify the build source commit and recorded inputs before release staging.
- Keep script version assignments as literal values for runtime display. Build-time validation makes these compatibility values explicit and rejects drift from VERSION.

## Risks / Trade-offs

- Literal script assignments and repeated README display values can become stale during manual edits. The shared build and release validator checks every current declaration before output generation or staging.
- The GUI and CLI versions remain different, which requires release notes to report the mapping clearly. The executable version and tag consistently use the GUI value.
- The checked-in launcher seed has historical file metadata. New output metadata is generated from VERSION, while legacy seed metadata remains untouched.

## Migration Plan

Correct the current script headers and startup displays, apply the existing GUI version to the new EXE metadata and artifact identity, and retain the CLI version. Existing binaries and tags remain unchanged. Future release tags must match the GUI value in VERSION and pass the same source and artifact checks.
