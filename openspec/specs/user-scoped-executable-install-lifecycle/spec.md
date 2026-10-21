# user-scoped-executable-install-lifecycle Specification

## Purpose
Define safe installation, upgrade, repair, rollback, and removal of the App Installer executable payload while preserving user state and unrelated files.

## Requirements

### Requirement: Per-user install scope and ownership

The system MUST install the Windows payload under the current user's `%USERPROFILE%\myTech.Today\AppInstaller` path, inherit the user's profile ACLs, and record the product version and hashes of owned payload files. It MUST NOT request elevation or broaden permissions for payload installation.

#### Scenario: Fresh install

- **WHEN** a validated payload is installed into a new user directory
- **THEN** the complete payload and ownership manifest are staged, validated, and activated under the current user
- **AND** queue data, profiles, logs, shortcuts, and runtimes outside the payload are not claimed as owned files

### Requirement: Idempotent replacement preserves user state

The system MUST make a healthy same-version launch idempotent. During upgrade or repair it MUST carry forward unowned files and directories, queue state and its backup, all user profiles, and app configuration. It MUST stop before activation when an unowned file conflicts with an incoming payload path.

#### Scenario: Repeated install

- **WHEN** the same valid version is installed again
- **THEN** the system reports that the installation is already current without replacing the install tree

#### Scenario: Existing script installation

- **WHEN** a prior script installation has recognizable payload markers
- **THEN** the system adopts its owned payload files and preserves user data, logs, shortcuts, and unrelated files during upgrade

#### Scenario: Unowned path conflict

- **WHEN** an unowned file occupies a path in the new package
- **THEN** the system stops before activation and leaves both the existing install and conflicting file unchanged

### Requirement: Modified code and profiles remain recoverable

The system MUST preserve modified owned code before repair and report its recovery path. It MUST retain edited profiles at their original paths and validate the resulting integrity metadata. Automatic copy MUST NOT silently overwrite modified owned code.

#### Scenario: Explicit repair of modified code

- **WHEN** repair finds an owned code file whose hash differs from the ownership manifest
- **THEN** it copies the exact prior bytes under `.app-installer-preserved`
- **AND** it reports the original path and recovery path before activating the repaired payload

#### Scenario: Upgrade with an edited profile

- **WHEN** an existing default profile differs from the prior package
- **THEN** the profile remains at its original path and its bytes are included in the new payload integrity record

### Requirement: Staging and rollback preserve the previous version

The system MUST stage beside the install root, validate before activation, retain the previous tree until the new tree validates, and roll back without deleting files written after activation. It MUST report exact paths when rollback or cleanup leaves files behind.

#### Scenario: Interrupted staging

- **WHEN** staging fails before activation
- **THEN** the existing install remains valid and only the current operation's staging directory is removed

#### Scenario: Activation failure after a newer user file is written

- **WHEN** activation fails after a user file is written into the new tree
- **THEN** the previous tree is restored
- **AND** the failed new tree remains at a reported recovery path with the newer file intact

#### Scenario: Backup cleanup failure

- **WHEN** a new payload validates but the prior backup cannot be removed
- **THEN** the new payload remains active
- **AND** the exact retained backup path and cleanup error are reported

### Requirement: Uninstall removes only unchanged owned files

The system MUST require an explicit retained-data uninstall. It MUST remove only files listed in the ownership manifest whose current lengths and hashes match. It MUST retain profiles, queue state, logs, app configuration, unowned files, modified owned files, user-created shortcuts, and runtimes.

#### Scenario: Uninstall preview

- **WHEN** uninstall is requested without `-RemoveOwnedFiles`
- **THEN** it reports the owned file count without deleting files

#### Scenario: Uninstall with keep-data

- **WHEN** uninstall is requested with `-KeepData -RemoveOwnedFiles`
- **THEN** unchanged owned code is removed
- **AND** queue files, profiles, logs, app configuration, modified files, shortcuts, and runtimes remain unchanged
- **AND** the install root remains when retained data is present

### Requirement: Legacy uninstall requires a valid ownership baseline

The system MUST NOT remove legacy product files when neither a valid ownership manifest nor valid payload-integrity metadata establishes their original hashes. It MUST preserve files absent from an incoming package during migration.

#### Scenario: Legacy install has no valid baseline

- **WHEN** uninstall targets a recognizable legacy install without valid ownership or payload-integrity hashes
- **THEN** the system stops before removing files and explains that a verified upgrade or repair is required
- **AND** migration preserves files that are absent from the incoming payload as unowned data
