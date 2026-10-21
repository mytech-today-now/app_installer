# Spec Delta

## ADDED Requirements

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
