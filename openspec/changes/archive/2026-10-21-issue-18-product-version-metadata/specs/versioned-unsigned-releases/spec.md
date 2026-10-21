## ADDED Requirements

### Requirement: One canonical version mapping drives executable releases

VERSION MUST contain exactly one stable semantic version for each current GUI and CLI script. Each script MUST have one matching ScriptVersion assignment and one matching header version. The README current-version declarations MUST match both entries. The GUI version MUST define the release tag, executable file version, and artifact name. The CLI version MAY remain different and MUST be recorded in release metadata and release notes.

#### Scenario: Valid distinct script versions

- **WHEN** VERSION declares valid stable GUI and CLI versions and each script header, script assignment, README mapping, and release tag matches the corresponding value
- **THEN** the GUI version is used for the EXE release identity while the CLI version remains separately visible

#### Scenario: Missing, malformed, duplicate, prerelease, or stale version metadata

- **WHEN** VERSION or current display metadata is missing, malformed, duplicated, prerelease, or differs from the matching script or README value
- **THEN** build or release validation fails before writing or publishing the executable

#### Scenario: Script payload provenance differs from the release commit

- **WHEN** builder provenance names a source commit different from the validated tag commit or any recorded build input differs from the source tree
- **THEN** release asset preparation fails without staging the executable

#### Scenario: Release notes describe a distinct CLI version

- **WHEN** release notes are generated for a valid release
- **THEN** they state the GUI version used for the executable and the separate bundled CLI script version
