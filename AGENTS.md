# App Installer Repository Guide

This repository provides a PowerShell application installer. `app-installer.ps1` is the Windows GUI entry point, and `app-installer-cli.ps1` is the cross-platform CLI. `apps-manifest.json` maps applications to platform package IDs; `apps/` contains app-specific scripts and `modules/` contains shared PowerShell code. `platform-detect.ps1` detects the current platform. The top-level `install.bat`, `install.sh`, and `invoke-elevated-install.ps1` are setup and launch helpers. See `README.md` for supported platforms and usage, and `CHANGELOG.md` for recent behavior changes.

## Working in this repository

- Check `git status --short` and read relevant documentation before editing. Preserve existing staged, unstaged, and untracked work, and keep changes scoped to the requested task.
- Keep `apps-manifest.json`, app-specific scripts, and shared module behavior consistent when adding or changing an application. Follow the existing platform and package-manager mappings.
- `compatibility.json` is the authoritative contract for declared and verified Windows and PowerShell support. Its current technical targets include Windows 10 Home or Pro x64 using the exact release/build pairs from version 1809 through 22H2, the listed Windows 11 Home or Pro x64 releases, Windows PowerShell Desktop 5.1, and PowerShell Core 7.2.0 through 7.6.9. Keep backward compatibility as a development target: evaluate earlier PowerShell Core 7.x releases and earlier Windows client releases, including Windows 10, when the required APIs, runtimes, and installer features are available. Derive minimum versions and builds from actual code and platform requirements instead of requiring the newest PowerShell 7 release or Windows 11 by default. Keep technical compatibility targets separate from Microsoft servicing status and native runtime verification evidence. A target becomes supported only after its exact minimums are declared in `compatibility.json` and covered by boundary tests; test the lowest declared versions as well as current versions. Update `compatibility.json`, README, diagnostics, executable metadata, and boundary tests together when the declared matrix changes. Keep GUI capability gates explicit: Windows PowerShell Desktop 5.1 requires .NET Framework 4.7.2 release 461808 or later; PowerShell Core GUI requires Windows Desktop runtime 10 and the required assemblies. Keep Windows-only GUI dependencies out of cross-platform CLI paths.
- Follow the top-level launchers' direct `-NoProfile -File` pattern. Do not add an execution-policy override or change a user's policy as part of a launch flow.
- Treat package installation or removal, elevation, scheduled updates, WinGet setup, downloaded helpers, and operating-system configuration as state-changing. Preserve source, digest, and signer validation for remote helpers and WinGet setup, and keep paths fail-closed when a required check or pin is missing.
- Preserve the CLI's `ShouldProcess` and `-WhatIf` behavior when changing operations that modify the system. Prefer the existing offline regression checks before any live package-manager or system operation.
- Do not run live install, uninstall, elevation, scheduled-task, bootstrap, or operating-system configuration workflows as routine code validation. Only perform those workflows when the task explicitly requires a live exercise.

## myTech.Today company profile

Use the `About myTech.Today` section in `README.md` as the canonical source for company services, service area, differentiators, and contact links. Keep maintained app About screens, user documentation, Augment guidance, and report company-profile cards aligned with that information. Preserve the supplied service claims and contact destinations; do not reintroduce older service-area or phone details from historical material.

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
