# Design

## Context

`install.bat` invokes `tools/Start-Installer.ps1` through the selected PowerShell engine. It already saves `%ERRORLEVEL%` on the next line and returns the captured value after classifying whether the launcher started. The regular success path always calls `pause`, and the `WhatIf` branch prints its completion message before checking its saved result.

## Goals / Non-Goals

**Goals:**

- Keep the exact PowerShell process status available through `cmd.exe` and parent batch callers.
- Keep failure status wording generic and include the numeric code without exposing temporary diagnostic paths.
- Return unattended calls without waiting; retain an explicit switch for users who want the console to remain visible.

**Non-Goals:**

- Change runtime selection, fallback classification, installer actions, `ShouldProcess`, or the existing `WhatIf` plan.
- Run the real installer or any package, elevation, task, or operating-system workflow.

## Decisions

- Keep the immediate `set "BOOTSTRAP_RC=%ERRORLEVEL%"` after each child invocation and use that variable for every return. This preserves the child status before labels, calls, or output can change `ERRORLEVEL`.
- Emit the report's exact failure sentence followed by a separate exit-code line. This gives users and parent automation a stable result without echoing temporary file paths.
- Use `-KeepConsoleOpen` as an explicit wrapper switch. `install.bat` recognizes it, while `Start-Installer.ps1` consumes it as a launcher parameter so it is not forwarded to the application. An environment-only flag would be harder to set in a shortcut, and automatic console detection would make unattended behavior ambiguous.
- Print `WhatIf completed` only after a zero child result. A nonzero result follows the same failure wording and exact return path as a normal launch.

## Risks / Trade-offs

- A double-clicked batch window closes after the result unless the shortcut supplies `-KeepConsoleOpen`. The README documents the opt-in switch, and both success and a returned child failure pause when it is selected.
- The batch scanner follows the existing argument-token handling used for `-WhatIf`; it does not redesign general command-line argument parsing.

## Rollback

Revert the `install.bat`, `tools/Start-Installer.ps1`, README, inventory, and focused-test changes together. Remove the unarchived OpenSpec change and close or supersede its Beads record if rollback is required. No persistent installer or host state is created by the change or its tests.

## Open Questions

None.
