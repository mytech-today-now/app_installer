# Changelog

All notable changes to the App Installer project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), with versions following [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added opt-in monthly Windows update scheduling for explicitly selected winget package IDs, with task ownership checks, confirmation, and rollback when replacement fails.
- Added offline regression coverage for execution-policy handling, startup trust checks, package-manager arguments and results, monthly updates, and elevation handoff.
- Added offline fake-download and fake-process coverage for immutable remote helper verification, rejected content, forwarded arguments, policy-blocked launches, and native exit status.
- Added offline trust-boundary coverage for the legacy Windows 10 WinGet bootstrap helper, expected Microsoft package publishers, release digest checks, and explicit custom-script result reporting.
- Added the authoritative Windows and PowerShell compatibility contract, early host and runtime gates, compatibility boundary tests, and unsigned executable metadata tooling.
- Added shared Windows PowerShell engine discovery with timed child-process probes, fixed candidate rules, GUI capability checks, and offline fallback coverage.
- Added an opt-in PowerShell Core provisioning helper for supported Windows hosts, using the contract-pinned WinGet version and `ShouldProcess` confirmation.
- Added validated GUI install-queue persistence and recovery for review before an explicit resume.
- Updated the CLI container to use PowerShell 7.6.7 release assets with architecture-specific SHA-256 verification.

### Changed

- Top-level setup launchers, the monthly update task, and the verified O&O child runner use direct `-NoProfile -File` launches without a process-level policy override, while preserving child exit results. A detected O&O policy block returns failure and displays sanitized recovery guidance without changing policy.
- The Windows executable launches the shared runtime resolver, which prefers the contracted PowerShell Core version, falls back to Windows PowerShell before application work, and does not provision a runtime.
- GUI and CLI package-manager calls use validated executable paths and argument arrays, and report dependency or update outcomes without masking failures.
- Update discovery distinguishes confirmed updates from empty, incomplete, and failed results.
- The O&O ShutUp10 custom installer now fails closed until an immutable source and approved SHA-256 pin are configured.
- Hosts File Manager and Manage Restore Points now require an HTTPS full-commit source and an independently reviewed SHA-256 before download or execution; their production pins remain unset and their launches, shortcuts, and documented commands use direct `-NoProfile -File` runs without a process-level policy override.
- The public entry points now reject unsupported Windows and PowerShell combinations before setup or package operations. The legacy Windows 10 bootstrap helper remains covered offline but is unreachable through those entry points.
- Recovered GUI queues are validated against the current app manifest and shown for review; resuming still requires the existing Install Selected action and confirmation. Invalid saved state is left untouched.
- GUI and CLI custom app scripts run in isolated PowerShell processes and report unknown outcomes without marking apps installed.
- Removed legacy prompt files from the tracked `ai_prompts/` directory and added ignore rules for local maintainer content.

### Fixed

- Corrected the Windows 11 26H2 Home and Pro end-of-updates date in `compatibility.json` to 2028-10-10.
- Preserved accurate winget update result states and process exit codes, including partial or unknown outcomes and log-write failures.
- Prevented normal CLI shutdown from implicitly creating an elevated monthly update task.
