# Spec Delta

## Purpose

Defines how the Windows batch installer wrapper reports PowerShell outcomes and controls console waiting for interactive and parent-process callers.

## ADDED Requirements

### Requirement: Report PowerShell outcomes truthfully

After a PowerShell stage starts, the wrapper MUST return its exact exit code, report full setup success only for exit code zero, and identify a nonzero status without disclosing temporary diagnostic paths.

#### Scenario: PowerShell succeeds

- **WHEN** the PowerShell stage returns exit code 0
- **THEN** the wrapper returns 0 and reports setup completion

#### Scenario: PowerShell fails

- **WHEN** the PowerShell stage returns a nonzero exit code
- **THEN** the wrapper returns that exact code, reports the failure status and code, and does not report setup completion

#### Scenario: WhatIf preflight fails

- **WHEN** a WhatIf preflight returns a nonzero exit code
- **THEN** the wrapper returns that exact code and does not report WhatIf completion

### Requirement: Console waiting is opt-in

The wrapper MUST return without waiting for keyboard input unless the caller explicitly supplies `-KeepConsoleOpen`.

#### Scenario: Unattended caller omits the switch

- **WHEN** the wrapper is invoked from CMD or a parent batch file without `-KeepConsoleOpen`
- **THEN** it returns the PowerShell result without waiting for keyboard input

#### Scenario: Caller requests a visible result

- **WHEN** the caller supplies `-KeepConsoleOpen` and the PowerShell stage returns
- **THEN** the wrapper displays the result and waits for a keypress before returning the same exit code
