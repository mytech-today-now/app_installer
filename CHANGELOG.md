# Changelog

All notable changes to the App Installer project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), with versions following [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added opt-in monthly Windows update scheduling for explicitly selected winget package IDs, with task ownership checks, confirmation, and rollback when replacement fails.
- Added offline regression coverage for execution-policy handling, startup trust checks, package-manager arguments and results, monthly updates, and elevation handoff.
- Added offline fake-download and fake-process coverage for immutable remote helper verification, rejected content, forwarded arguments, policy-blocked launches, and native exit status.
- Added offline coverage for the Windows 10 WinGet bootstrap, expected Microsoft package publishers, release digest checks, and explicit custom-script result reporting.

### Changed

- Top-level setup launchers, the monthly update task, and the verified O&O child runner use direct `-NoProfile -File` launches without a process-level policy override, while preserving child exit results.
- GUI and CLI package-manager calls use validated executable paths and argument arrays, and report dependency or update outcomes without masking failures.
- Update discovery distinguishes confirmed updates from empty, incomplete, and failed results.
- The O&O ShutUp10 custom installer now fails closed until an immutable source and approved SHA-256 pin are configured.
- Hosts File Manager and Manage Restore Points now require an HTTPS full-commit source and an independently reviewed SHA-256 before download or execution; their production pins remain unset and their launches, shortcuts, and documented commands use direct `-NoProfile -File` runs without a process-level policy override.
- Windows 10 WinGet setup is limited to supported x64 client systems and validates package signatures, expected identities and publishers, architectures, and the release bundle digest before package changes. Failures report whether changes started and whether temporary-file cleanup completed.
- GUI and CLI custom app scripts run in isolated PowerShell processes and report unknown outcomes without marking apps installed.
- Removed legacy prompt files from the tracked `ai_prompts/` directory and added ignore rules for local maintainer content.

### Fixed

- Preserved accurate winget update result states and process exit codes, including partial or unknown outcomes and log-write failures.
- Prevented normal CLI shutdown from implicitly creating an elevated monthly update task.
