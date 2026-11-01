# Tasks

## 1. Explicit interactive agreement handling

- [x] 1.1 Remove unconditional source/package agreement acceptance from shared, entry-point, and app-specific WinGet install and upgrade commands.
- [x] 1.2 Stream interactive agreement review output to the current UI, exclude it from file logs, stop agreement-specific automatic retries, and provide a visible GUI retry path.
- [x] 1.3 Document that app selection is not consent and describe the interactive review behavior.

## 2. Fail-closed unattended behavior

- [x] 2.1 Disable prompts in discovery and scheduled update commands without accepting terms.
- [x] 2.2 Report package/source agreement failures as failed or incomplete scheduled outcomes without retaining agreement text.

## 3. Regression evidence

- [x] 3.1 Add fake output cases for no agreement, accepted fake result, new package agreement, new source agreement, and decline; assert no retry or mutation after decline.
- [x] 3.2 Run the package-manager security, monthly update result/scheduling, CLI WhatIf, and syntax checks using offline boundaries.
- [x] 3.3 Validate the OpenSpec change and record exact executed results.

## Validation record

- `pwsh -NoProfile -File .\other_files\test-syntax.ps1`: PASS; 349 discovered PowerShell files parse under Core 7.6.9.
- `powershell.exe -NoProfile -File .\other_files\test-syntax.ps1`: PASS; 349 discovered PowerShell files parse under Windows PowerShell 5.1.26100.9818.
- `test-package-manager-command-security.ps1`: PASS; 775 assertions under Windows PowerShell 5.1 and 776 under Core 7.6.9.
- `test-monthly-update-results.ps1`: PASS; 61 assertions under Windows PowerShell 5.1 and Core 7.6.9.
- `test-monthly-update-scheduling.ps1`: PASS; 78 assertions under Windows PowerShell 5.1. An earlier Core 7.6.9 attempt failed its status fallback assertion; Core 7.6.9 is outside the exact 7.6.7 product pin.
- `test-cli-whatif.ps1`: PASS; 22 assertions under Windows PowerShell 5.1. Core 7.6.9 was rejected by the repository's exact Core 7.6.7 compatibility pin.
- `test-package-dependency-outcomes.ps1`: PASS; 112 assertions under Windows PowerShell 5.1.
- `test-update-argv-security.ps1`: PASS; 251 assertions under Windows PowerShell 5.1 and Core 7.6.9.
- `test-update-scan-status.ps1`: PASS; 198 assertions under Windows PowerShell 5.1. The isolated CLI function fixture imports the new agreement review helper.
- `openspec validate issue-14-winget-agreement-consent`: PASS; valid with no warnings.
- `git diff --check`: PASS; no whitespace errors. Git reported existing LF-to-CRLF working-copy warnings.
- No live WinGet, scheduler, install, elevation, or operating-system operation was run.

## Workflow follow-up

- Archive this OpenSpec change only after focused offline validation succeeds. Do not run live WinGet, install, scheduler, elevation, signing, deployment, or release actions.
