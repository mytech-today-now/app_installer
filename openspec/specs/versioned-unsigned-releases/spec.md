# versioned-unsigned-releases Specification

## Purpose
Defines how protected semantic-version tags produce a gated unsigned Windows executable release whose version, source, compatibility, tests, and artifact digest can be checked.

## Requirements

### Requirement: Release tags match the existing product version
The release workflow MUST accept only stable `vMAJOR.MINOR.PATCH` tags whose version matches the GUI version in `VERSION`; the GUI and CLI script versions MUST also match their respective `VERSION` entries.

#### Scenario: Valid GUI version tag
- **WHEN** a protected tag matches the GUI version and both scripts match `VERSION`
- **THEN** release validation proceeds with that GUI version as the product version

#### Scenario: Invalid or mismatched tag
- **WHEN** a tag has non-semantic syntax or its version differs from the GUI version in `VERSION`
- **THEN** release validation fails before building or publishing assets

### Requirement: Release publication requires protected source and passing gates
The release workflow MUST publish only from a protected version tag that points to a commit on the default branch, and only after both supported PowerShell test jobs and the pinned executable build checks pass.

#### Scenario: Protected tag with passing matrix
- **WHEN** the protected tag points to the default branch and all Desktop 5.1 and Core 7.6.7 gates pass
- **THEN** the release job may prepare and publish assets

#### Scenario: Unprotected tag or failed gate
- **WHEN** the tag is not protected, is not on the default branch, or any required build or test job fails
- **THEN** no public release is published

### Requirement: Release assets identify one unsigned x64 executable
Each release MUST contain one x64 executable named `AppInstaller-<GUI-version>-win-x64.exe`, its SHA-256 sidecar, builder provenance, and a machine-readable release manifest with the source tag and commit, product and CLI versions, build toolchain, compatibility contract, payload inventory, target architecture, and passing test evidence.

#### Scenario: Complete unsigned x64 asset set
- **WHEN** release asset preparation receives one complete builder output with matching source and version metadata
- **THEN** it creates the versioned executable asset, correct digest sidecar, and provenance files without invoking a signing tool

#### Scenario: Missing, duplicate, changed, or signed output
- **WHEN** an executable, provenance file, inventory entry, or required test record is missing or duplicated, the digest differs, or Authenticode reports a signature
- **THEN** asset preparation fails without overwriting existing files

### Requirement: Release publication is duplicate-safe and least-privileged
The release workflow MUST use read-only repository permissions for validation, grant only `contents: write` to the publishing job, reject an existing release, verify the tag already exists, upload assets to an unpublished draft, and publish only after every upload succeeds.

#### Scenario: New release uploads successfully
- **WHEN** no release exists for the validated tag and every required asset upload succeeds
- **THEN** the workflow publishes the draft with release notes that describe compatibility, invocation, unsigned status, recovery, and checksum limits

#### Scenario: Duplicate or incomplete release
- **WHEN** a release already exists, the tag is missing or moved, or an upload fails
- **THEN** the workflow fails closed and does not publish or create a tag

### Requirement: Legacy executables remain separate from current release artifacts
The build and release process MUST preserve inventory-listed legacy executables, label provenance as unknown when repository evidence cannot establish it, and MUST NOT select legacy executables as build outputs or current release assets. Release preparation MUST accept only the configured versioned executable with its adjacent builder manifest identifying the current release artifact and matching its bytes.

#### Scenario: Build output targets a legacy path
- **WHEN** a build requests an output path listed in the legacy artifact inventory
- **THEN** the builder fails before writing and leaves the legacy file unchanged

#### Scenario: Release preparation sees legacy executables beside the current build
- **WHEN** the configured versioned executable has a matching adjacent manifest and digest while other executables are present in the repository
- **THEN** release preparation stages only the configured versioned executable and its allowlisted metadata

#### Scenario: Release input lacks current artifact identity
- **WHEN** the executable name, adjacent builder manifest, artifact identity, or digest does not match the current versioned build contract
- **THEN** release preparation fails without staging a legacy executable

#### Scenario: Legacy provenance cannot be established
- **WHEN** repository history and packaging inputs do not establish a legacy executable's original source or consumers
- **THEN** its metadata records provenance as unknown and keeps it ineligible for current releases

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
