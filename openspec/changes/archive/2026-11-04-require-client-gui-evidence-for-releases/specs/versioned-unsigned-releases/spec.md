# Spec Delta

## MODIFIED Requirements

### Requirement: Release publication requires protected source and passing gates
The release workflow MUST publish only from a protected version tag that points to a commit on the default branch, and only after both supported PowerShell test jobs, the pinned executable build checks, and the supported Windows client GUI evidence gate pass.

#### Scenario: Protected tag with passing matrix
- **WHEN** the protected tag points to the default branch and all Desktop 5.1 and Core 7.6.9 compatibility gates pass, but the supported-client GUI evidence gate is missing or incomplete
- **THEN** no public release is published until both client rows pass for the tagged source revision

#### Scenario: Protected tag with passing matrix and client evidence
- **WHEN** the protected tag points to the default branch, all Desktop 5.1 and Core 7.6.9 compatibility gates pass, and both supported-client GUI evidence rows pass for the tagged source revision
- **THEN** the release job may prepare and publish assets

#### Scenario: Missing or invalid client evidence
- **WHEN** either client row is missing or NOT RUN, names an unsupported host or engine, reports a failed capability or isolated startup check, lacks required runtime or assembly evidence, or names a different source revision
- **THEN** release validation fails before publication and Server results do not satisfy either client row

#### Scenario: Unprotected tag or failed gate
- **WHEN** the tag is not protected, is not on the default branch, or any required build, test, or client evidence gate fails
- **THEN** no public release is published
