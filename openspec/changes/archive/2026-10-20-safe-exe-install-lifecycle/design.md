# Design

## Decisions

### User scope and paths

- Keep the existing Windows install root: `%USERPROFILE%\myTech.Today\AppInstaller`.
- Keep logs at `%USERPROFILE%\myTech.Today\logs` and the CLI's existing per-user platform paths.
- Inherit the current user's profile ACLs. Do not request elevation, broaden access, or offer a machine-wide destination.
- Do not create a product shortcut. Never enumerate or remove shortcuts outside the install root.

### Ownership and migration

- Write `.app-installer-install.json` after the staged payload validates. It records product ID, version, scope, state, and owned paths with byte lengths and SHA-256 values.
- The ownership manifest is a local ownership record. It is not a signature and does not authenticate an unsigned package.
- For prior script installs, recognize a valid payload integrity record or the existing payload manifest and product entry points. Preserve queue files, all profiles, app configuration, and every unowned file and directory.
- When a legacy install has no valid integrity baseline, preserve files absent from the incoming payload as unowned data. Do not remove its product files during uninstall until a verified upgrade or repair records ownership hashes.
- Preserve an edited profile at its original path and recalculate payload integrity for the resulting install.
- If an unowned file conflicts with an incoming product path, stop before activation. Do not overwrite or adopt it.
- If an owned code file differs from the recorded hash, automatic copy fails closed. Explicit repair keeps the exact prior bytes under `.app-installer-preserved/<id>/<relative-path>`, reports both paths, and then validates the repaired payload.

### Staging, activation, and rollback

- Copy the complete validated payload to a unique sibling staging directory so staging and activation use the same volume.
- Carry forward unowned data and directories, including empty directories. Preserve ACLs by requiring the staged files and directories to inherit the same ACL as the existing user-scoped tree. If a custom ACL differs, fail before activation.
- Validate staged payload integrity and ownership metadata before moving the current root.
- Move the current root to a unique sibling backup, then move the validated stage into the stable root. Recheck the previous tree for concurrent changes before cleanup.
- On failure, move an activated new tree to a `.failed-*` sibling so files written after activation remain recoverable, then restore the previous directory. If a move, restore, stage cleanup, or backup cleanup fails, report the exact remaining path and error.
- Keep one active payload at the stable install root. The prior version exists beside it only during the transaction and is removed after the new payload validates.

### Repair and uninstall

- GUI startup uses the verified launch payload as the repair source. A healthy matching version returns without replacing the install. A missing or damaged owned file is restored. Local code edits are copied to a recovery folder and reported before replacement.
- `Manage-AppInstallerInstall.ps1` exposes Install, Upgrade, Repair, and Uninstall operations and supports `-WhatIf`.
- Uninstall requires `-KeepData`; the product does not provide a mode that deletes queue state, profiles, logs, or arbitrary user data.
- Uninstall without `-RemoveOwnedFiles` is a no-change preview. With both flags, remove only manifest-owned files whose current length and SHA-256 still match. Keep modified owned files, all profiles, queue files, unowned files, logs, shortcuts, and runtimes.
- Leave the install root when retained data remains. Do not remove PowerShell or .NET runtimes.

## Risks

- A custom ACL that cannot be reproduced through inheritance blocks replacement and requires the user to resolve the ACL before retrying.
- A user-created file that occupies a packaged path blocks upgrade until the conflict is moved or reviewed.
- The payload integrity and install ownership hashes detect local changes but do not authenticate the unsigned executable or its publisher.
- An unsigned IExpress package can still produce SmartScreen or antivirus warnings.

## Validation

Use `tests/test-executable-install-lifecycle.ps1`, `tests/test-executable-payload.ps1`, and `other_files/test-syntax.ps1`. These checks use temporary directories and fakes. They do not establish live installation, elevation, runtime provisioning, or EXE publication behavior.
