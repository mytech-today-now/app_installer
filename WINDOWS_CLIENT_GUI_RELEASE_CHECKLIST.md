# Windows Client GUI Release Checklist

This checklist records supported Windows client GUI evidence separately from the standard Windows build. The `windows-2025` GitHub Actions label is Windows Server 2025. Its build and engine results are not Windows client GUI evidence.

As of 2026-11-04, GitHub's published hosted-image list has Windows Server x64 images and Windows 11 Arm64 images, but no Windows 11 x64 client image matching `compatibility.json`. Recheck the [published runner-image list](https://github.com/actions/runner-images#available-images) before choosing a hosted runner. Until a supported x64 client runner is available, use an already-provisioned supported client host and record the evidence below.

## Compatibility source review

Before a versioned release, confirm `compatibility.json.lastReviewed` is no more than 180 days old. Run `pwsh -NoProfile -File .\tools\Test-CompatibilityReview.ps1` for the local offline check; the release workflow applies `-RequireFresh` and blocks a stale review. Compare the current values with the official [Windows client lifecycle](https://learn.microsoft.com/en-us/windows/release-health/supported-versions-windows-client), [PowerShell support lifecycle](https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-support-lifecycle?view=powershell-7.6), and [pinned PowerShell release](https://github.com/PowerShell/PowerShell/releases/tag/v7.6.9). Update `lastReviewed` by hand after the review. The local test injects dates, makes no web requests, and never changes the contract. The current review was recorded on `2026-11-01`.

## Supported validation host

Keep the contract in `compatibility.json` unchanged:

- Windows 11 25H2 build 26200 or Windows 11 26H2 build 26300.
- Home or Pro edition, x64 operating system and PowerShell process.
- Windows PowerShell Desktop 5.1, with .NET Framework release 461808 or later for GUI use.
- PowerShell Core 7.6.9, with Windows Desktop runtime 10 and loadable `System.Windows.Forms`, `System.Drawing`, and `System.Web` assemblies for GUI use.
- An interactive desktop and an STA thread for the GUI startup check.

Do not install or provision a runtime or application as part of this check. Use only engines already present on the supported client. If a required engine is absent or has the wrong version, record that engine as `NOT RUN` and stop that engine's validation.

## Run the non-installing checks

Run both commands from an x64, interactive PowerShell session on the supported Windows client. Each command is read-only with respect to the host. The startup integration uses isolated temporary profiles and fake network and WinGet boundaries; it starts and closes the GUI without installing an application.

Windows PowerShell 5.1:

```powershell
powershell.exe -NoLogo -NoProfile -STA -File .\tests\test-compatibility-runtime-current-host.ps1
powershell.exe -NoLogo -NoProfile -STA -File .\tests\test-startup-entrypoints-offline.ps1
```

PowerShell Core 7.6.9: invoke the already-present x64 7.6.9 executable by its reviewed absolute path. Do not substitute a different `pwsh.exe` found on `PATH`.

```powershell
$pwsh769 = 'C:\path\to\approved\PowerShell\7.6.9\pwsh.exe'
& $pwsh769 -NoLogo -NoProfile -STA -File .\tests\test-compatibility-runtime-current-host.ps1
& $pwsh769 -NoLogo -NoProfile -STA -File .\tests\test-startup-entrypoints-offline.ps1
```

The tests verify the client host and exact engine before loading the GUI runtime. They report `[UNAVAILABLE]` and exit 77 for Server, an unsupported client, a mismatched engine, or a non-STA invocation. Exit 77 is `NOT RUN`, never a pass. A nonzero exit other than 77 is a failed check. Record each supported engine independently.

## Release evidence record

Fill this record for each release. Keep Server CI evidence and supported client evidence in separate rows. If no supported client check ran, retain `NOT RUN` for client GUI and engine capability results.

### Machine-readable release gate

The release workflow reads WINDOWS_CLIENT_GUI_RELEASE_EVIDENCE.json from the repository default branch. Append one record for the exact release source commit after running both client checks. Its sourceRevision must equal the commit that will receive the release tag. The evidence file is committed separately on the default branch, so recording test results does not change the tagged source commit. If the gate runs before the record is available, add the record to the default branch and rerun the failed release workflow.

Each engine row must include its UTC recordedAtUtc timestamp, evidenceLocation, Windows 11 release/build/edition/product type/installation type/architecture, exact engine identity/version/executable/process architecture, STA result, runtime name/family/version or .NET Framework release, loaded full identities for System.Windows.Forms, System.Drawing, and System.Web, capabilityResult PASS, startupMode Isolated, and isolatedStartupResult PASS. Record Home or Pro, x64 for both operating system and process, and only release/build pairs in compatibility.json whose servicing window is still open. For Core, identify Microsoft.WindowsDesktop.App version 10 and ensure the Forms and Drawing assembly major versions are 10. For Desktop 5.1, record .NET Framework release 461808 or later.

Keep the template rows as NOT RUN until those checks have completed on the supported client. The release gate rejects a missing row, placeholder, wrong host or engine, failed result, expired host release, or revision mismatch. It uses Windows Server 2025 only to validate the record. That Server job does not run client GUI checks and cannot satisfy either client row. Add later evidence as another record instead of changing a record for an earlier source revision.

### Server build and engine matrix

| Field | Recorded result |
| --- | --- |
| Workflow run URL and run ID | `NOT RUN` |
| Source revision | `NOT RUN` |
| Server OS, build, product type, architecture | `NOT RUN` |
| Windows PowerShell 5.1 build and offline-suite result | `NOT RUN` |
| PowerShell Core 7.6.9 build and offline-suite result | `NOT RUN` |

This section is for the Server build and its engine/offline checks only. A Server pass does not satisfy any client GUI row below.

### Supported Windows client GUI capability and startup

| Engine | OS edition / release / build | OS and process architecture | Engine version / executable | Runtime and required assemblies | GUI startup result | Evidence location |
| --- | --- | --- | --- | --- | --- | --- |
| Windows PowerShell Desktop | `NOT RUN` | `NOT RUN` | `NOT RUN` | `NOT RUN` | `NOT RUN` | `NOT RUN` |
| PowerShell Core | `NOT RUN` | `NOT RUN` | `NOT RUN` | `NOT RUN` | `NOT RUN` | `NOT RUN` |

### Engine capability details

| Engine | STA confirmed | Runtime version / .NET Framework release | `System.Windows.Forms` full version | `System.Drawing` full version | `System.Web` full version | Capability test result |
| --- | --- | --- | --- | --- | --- | --- |
| Windows PowerShell Desktop 5.1 | `NOT RUN` | `NOT RUN` | `NOT RUN` | `NOT RUN` | `NOT RUN` | `NOT RUN` |
| PowerShell Core 7.6.9 | `NOT RUN` | `NOT RUN` | `NOT RUN` | `NOT RUN` | `NOT RUN` | `NOT RUN` |

Record the output from `test-compatibility-runtime-current-host.ps1` for runtime and assembly details, and the output from `test-startup-entrypoints-offline.ps1` for the GUI startup result. Do not copy a Server result into a Windows client row.
