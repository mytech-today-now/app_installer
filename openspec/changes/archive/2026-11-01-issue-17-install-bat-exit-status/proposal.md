# Proposal

## Why

The source finding for Issue 17 is partially stale: `install.bat` already captures and returns the PowerShell child status, and only prints `Setup complete.` after exit code 0. The wrapper still waits unconditionally after success, and its preflight `WhatIf` path currently prints completion before checking the child result, so callers can block and failure output can imply completion.

Report reference: `ai-prompts/pre-mortem-2026-10-31-09-44-52.html#issue-17`.

## What Changes

- Preserve immediate PowerShell exit-code capture and exact `exit /b` propagation.
- Use the supplied generic failure wording and show the returned code without printing full-success output for nonzero results, including `WhatIf`.
- Make the final keypress wait opt-in through `-KeepConsoleOpen` and document the switch.
- Add isolated fake-child checks for exit codes 0, 1, and 23 through CMD and a parent batch file, plus pause and output assertions.

## Capabilities

### New Capabilities

- `windows-installer-wrapper`: Truthful Windows batch launcher outcomes and opt-in console waiting.

### Modified Capabilities

None.

## Impact

Changes `install.bat`, the shared `tools/Start-Installer.ps1` parameter contract, README launcher guidance, and focused offline regression inventory and tests. No real installer, package provider, elevation, bootstrap, task, or operating-system action is part of validation.
