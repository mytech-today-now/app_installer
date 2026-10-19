# App Installer Repository Guide

This repository provides a PowerShell application installer. `app-installer.ps1` is the Windows GUI entry point, and `app-installer-cli.ps1` is the cross-platform CLI. `apps-manifest.json` maps applications to platform package IDs; `apps/` contains app-specific scripts and `modules/` contains shared PowerShell code. `platform-detect.ps1` detects the current platform. The top-level `install.bat`, `install.sh`, and `invoke-elevated-install.ps1` are setup and launch helpers. See `README.md` for supported platforms and usage, and `CHANGELOG.md` for recent behavior changes.

## Working in this repository

- Check `git status --short` and read relevant documentation before editing. Preserve existing staged, unstaged, and untracked work, and keep changes scoped to the requested task.
- Keep `apps-manifest.json`, app-specific scripts, and shared module behavior consistent when adding or changing an application. Follow the existing platform and package-manager mappings.
- `compatibility.json` is the single Windows and PowerShell support contract. The verified Windows client scope is Windows 11 25H2 build 26200 or 26H2 build 26300, Home or Pro, x64. Windows PowerShell Desktop 5.1 supports GUI and CLI; the GUI requires .NET Framework 4.7.2 release 461808 or later. PowerShell Core 7.6.7 supports CLI and can use the GUI when Windows Desktop runtime 10 and the required assemblies load. The non-Windows CLI uses PowerShell Core 7.6.7 on operating systems supported by that PowerShell release. Update the manifest, README, diagnostics, executable metadata, and boundary tests together when this matrix changes. Keep Windows-only GUI dependencies out of cross-platform CLI paths.
- Follow the top-level launchers' direct `-NoProfile -File` pattern. Do not add an execution-policy override or change a user's policy as part of a launch flow.
- Treat package installation or removal, elevation, scheduled updates, WinGet setup, downloaded helpers, and operating-system configuration as state-changing. Preserve source, digest, and signer validation for remote helpers and WinGet setup, and keep paths fail-closed when a required check or pin is missing.
- Preserve the CLI's `ShouldProcess` and `-WhatIf` behavior when changing operations that modify the system. Prefer the existing offline regression checks before any live package-manager or system operation.
- Do not run live install, uninstall, elevation, scheduled-task, bootstrap, or operating-system configuration workflows as routine code validation. Only perform those workflows when the task explicitly requires a live exercise.

## Validation

Tests are standalone PowerShell scripts under `tests/`; select the script that covers the behavior being changed and check its host or platform prerequisites. The focused syntax check is:

```powershell
pwsh -NoProfile -File .\other_files\test-syntax.ps1
```

On Windows, also run it with Windows PowerShell 5.1 when validating compatibility:

```powershell
powershell.exe -NoProfile -File .\other_files\test-syntax.ps1
```

The syntax check parses the files listed in `other_files/test-syntax.ps1`; it does not verify live package-manager, elevation, scheduled-task, or operating-system behavior.

The compatibility contract and executable metadata checks are offline:

```powershell
pwsh -NoProfile -File .\tests\test-compatibility-contract.ps1
pwsh -NoProfile -File .\tests\test-executable-metadata.ps1
pwsh -NoProfile -File .\tests\test-executable-resource-update.ps1
```

Unsupported Windows hosts must be rejected before downloads, elevation, package-manager calls, or persistent changes. Do not run live setup or runtime provisioning as a validation step.

## Augment Extensions Integration

This project uses Augment Extensions for additional AI coding guidance. Check `.augment/extensions.json`, then inspect linked modules that are relevant to the task:

```bash
augx list --linked
augx show <module-name>
augx search <keyword>
```
