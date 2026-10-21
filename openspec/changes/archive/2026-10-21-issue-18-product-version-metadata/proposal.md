# Use One Version Contract for the Executable

## Problem

The release pipeline already reads the GUI and CLI versions from VERSION, but script headers and early startup banners still display 2.0.0. README and release metadata also repeat version values that need an explicit consistency check.

## Proposed Change

Keep VERSION as the canonical source for the current GUI and CLI script versions. The GUI version defines the executable product version, stable release tag, four-part Windows file version, and versioned artifact name. Preserve the separate CLI version. Validate script headers and assignments, current README declarations, generated EXE properties, release manifest, release notes, and source commit provenance before release asset preparation.

## Scope

Update only version metadata, its validation, version-specific documentation, tests, and issue tracking. Keep historical changelog records intact. Stable tags remain the only supported release format.

## Out of Scope

Do not bump either script version, create or move Git tags, publish a release, change legacy executable bytes, or broaden supported prerelease behavior.

## Tracking

Report finding: ai-prompts/pre-mortem-2026-10-17-12-01-24.html#issue-18

Beads item: app_installer-33x
