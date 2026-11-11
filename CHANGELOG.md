# Changelog

All notable changes to the App Installer project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), with versions following [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Synchronized the myTech.Today services, Omaha and Lincoln service area, differentiators, and contact details across the README, GUI and CLI About content, user instructions, and maintainer guidance. Refreshed the approved digest for the updated bundled instructions.
- Declared exact Windows 10 compatibility pairs from version 1809 through 22H2 and PowerShell Core 7.2.0 through 7.6.9. The contract separates technical targets from vendor servicing, and records that native Windows 10 and PowerShell 7.2.0 runtime evidence was not run.
- Catalog entries for Belarc Advisor, O&O ShutUp10, and McAfee are unavailable while required source identities and trust pins are unset; selection and direct install paths stop before download or process launch.
- Verified helper downloads reject redirects or changed response sources before execution.
- Profile import logging normalizes Markdown delimiters and line breaks, bounds untrusted fields, and keeps legacy device and account identifiers out of diagnostics.
- With `-KeepBuildFilesOnFailure`, a failed IExpress run retains the exact invocation, SED digest, exit code, and captured output in its temporary build root while publishing no executable or provenance manifest.
- Versioned release publication now requires revision-bound Windows client GUI capability and isolated startup evidence for Desktop 5.1 and Core 7.6.9; Server CI remains separate.
- The Windows executable build is configured to generate an IExpress launcher from a pinned Microsoft tool and current source template, without a checked-in executable seed.
- The executable build toolchain now pins the supported .NET 10.0.14 runtime and its verified Microsoft-signed files.
- Profile exports now omit device and user identifiers by default; the CLI includes them only after the user confirms the diagnostic disclosure.

### Removed

- Removed the two release-ineligible legacy executables. Their historical hashes and provenance limits remain recorded, and their former paths stay blocked as build outputs.

### Added

- Added a root npm dependency manifest and lockfile for the Augment Extensions CLI used by maintainer guidance.
- Added offline fake transport, signature, and process coverage for a verified executable helper, including McAfee fail-closed behavior while its production trust identity remains unset.
- Added install ownership manifests and offline install, upgrade, repair, rollback, and retained-data uninstall coverage for the user-scoped EXE payload.
- Added an executable lifecycle management command with dry-run support and explicit keep-data and remove-owned-files options.
- Added protected semantic-version GitHub releases for the unsigned x64 EXE, with SHA-256, builder provenance, compatibility and payload metadata, and test evidence.
- Added fixture-driven release asset and publication checks for tag/version gates, unsigned output, duplicate releases, checksum accuracy, and draft-only failure handling.
- Added pinned Windows executable build tooling with versioned output, source and toolchain provenance, an explicit payload inventory, and clean-copy reproducibility checks.
- Added explicit identities and output guards for tracked legacy executables so the versioned release process cannot overwrite or publish them.
- Added opt-in monthly Windows update scheduling for explicitly selected winget package IDs, with task ownership checks, confirmation, and rollback when replacement fails.
- Added offline regression coverage for execution-policy handling, startup trust checks, package-manager arguments and results, monthly updates, and elevation handoff.
- Added offline fake-download and fake-process coverage for immutable remote helper verification, rejected content, forwarded arguments, policy-blocked launches, and native exit status.
- Added offline trust-boundary coverage for the legacy Windows 10 WinGet bootstrap helper, expected Microsoft package publishers, release digest checks, and explicit custom-script result reporting.
- Added the authoritative Windows and PowerShell compatibility contract, early host and runtime gates, compatibility boundary tests, and unsigned executable metadata tooling.
- Added shared Windows PowerShell engine discovery with timed child-process probes, fixed candidate rules, GUI capability checks, and offline fallback coverage.
- Added an opt-in PowerShell Core provisioning helper for supported Windows hosts, using the contract-pinned WinGet version and `ShouldProcess` confirmation.
- Added validated GUI install-queue persistence and recovery for review before an explicit resume.
- Updated the CLI container and Windows compatibility, build, and release checks to use PowerShell Core 7.6.9; the container retains architecture-specific SHA-256 verification.
- Added a read-only compatibility-source review cadence check to the versioned release gate, with deterministic offline tests and a documented Windows client GUI evidence checklist.
- Added a per-engine CI regression inventory with explicit included, skipped, and unavailable outcomes for standalone checks.
- Added offline batch-wrapper coverage for PowerShell success and failure statuses, `WhatIf`, and opt-in console waiting.
- Added local release-protection and Windows client GUI evidence records; remote tag-policy status remains unverified and client GUI results remain not run.
- Expanded offline regression coverage for the compatibility boundaries, helper redirect rejection, unavailable app actions, profile log safety, and retained IExpress failure evidence.

### Changed

- WinGet installs and upgrades no longer accept source or package agreements automatically; interactive commands use WinGet's review prompt, while discovery and scheduled updates disable interactivity and fail closed on required terms.
- The GUI now verifies and sanitizes its bundled instructions before display, and opens only HTTPS or mailto links outside the embedded browser.
- McAfee removal now fails closed before download or product removal until an independently reviewed MCPR digest or signer pin is configured. When configured, MCPR runs only from a private staged path after verification, and its child exit code is reported.
- Defined the GUI version in VERSION as the executable, file-resource, artifact-name, and tag version while preserving the CLI's separate version.
- Self-install now preserves unowned files, user profiles, and inherited ACLs, detects changed owned files, and reports preserved code or retained rollback paths.
- Legacy migration preserves files absent from the incoming package, and uninstall fails closed when no valid ownership hash baseline exists.
- Top-level setup launchers, the monthly update task, and the verified O&O child runner use direct `-NoProfile -File` launches without a process-level policy override, while preserving child exit results. A detected O&O policy block returns failure and displays sanitized recovery guidance without changing policy.
- The Windows executable launches the shared runtime resolver, which prefers the contracted PowerShell Core version, falls back to Windows PowerShell before application work, and does not provision a runtime.
- GUI and CLI package-manager calls use validated executable paths and argument arrays, and report dependency or update outcomes without masking failures.
- Update discovery distinguishes confirmed updates from empty, incomplete, and failed results.
- The O&O ShutUp10 custom installer now fails closed until an immutable source and approved SHA-256 pin are configured.
- Hosts File Manager and Manage Restore Points now require an HTTPS full-commit source and an independently reviewed SHA-256 before download or execution; their production pins remain unset and their launches, shortcuts, and documented commands use direct `-NoProfile -File` runs without a process-level policy override.
- The public entry points now reject unsupported Windows and PowerShell combinations before setup or package operations. The legacy Windows 10 bootstrap helper remains covered offline but is unreachable through those entry points.
- Recovered GUI queues are validated against the current app manifest and shown for review; resuming still requires the existing Install Selected action and confirmation. Invalid saved state is left untouched.
- GUI and CLI custom app scripts run in isolated PowerShell processes and report unknown outcomes without marking apps installed.
- The Windows batch launcher reports nonzero PowerShell results without success output, preserves the result through parent batch calls, and waits only when `-KeepConsoleOpen` is supplied.
- Removed legacy prompt files from the tracked `ai_prompts/` directory and added ignore rules for local maintainer content.

### Fixed

- Removed the unconditional `--force` option from cross-platform WinGet installs; WinGet's default handling of non-security issues now applies to every mapped package.

- Corrected the Windows 11 26H2 Home and Pro end-of-updates date in `compatibility.json` to 2028-10-10.
- Preserved accurate winget update result states and process exit codes, including partial or unknown outcomes and log-write failures.
- Prevented normal CLI shutdown from implicitly creating an elevated monthly update task.
