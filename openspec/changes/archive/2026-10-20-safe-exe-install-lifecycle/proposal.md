# Proposal

## Why

Issue 16 identifies that the EXE starts the GUI and self-copies its payload, but install scope, file ownership, upgrade recovery, and uninstall retention were not defined. The existing user-scoped copy keeps queue state and custom JSON profiles, but replacement of the whole install directory could discard other files.

Source finding: `ai-prompts/pre-mortem-2026-10-17-12-01-24.html#issue-16`.

## What Changes

- Define the EXE as a per-user IExpress launcher that installs the validated payload under `%USERPROFILE%\myTech.Today\AppInstaller`.
- Record product version and owned file hashes in `.app-installer-install.json`.
- Preserve user data, unrelated files, inherited ACLs, and modified owned code through staged install, upgrade, repair, and rollback.
- Add an explicit lifecycle management command with retained-data uninstall behavior.
- Add offline lifecycle tests and document scope, ownership, migration, and recovery.

No package selection, runtime provisioning policy, machine-wide installation, or EXE publication is changed.

## Capabilities

### New Capabilities

- `user-scoped-executable-install-lifecycle`: Install, upgrade, repair, roll back, and remove manifest-owned executable payload files without deleting user state or unrelated files.

### Modified Capabilities

None.

## Impact

Changes the payload lifecycle module and GUI copy call, adds the lifecycle command to the packaged payload, adds focused offline tests, and updates the README and changelog. The Beads work item is `app_installer-foa`, linked to the report finding and kept open until its acceptance checks pass.
