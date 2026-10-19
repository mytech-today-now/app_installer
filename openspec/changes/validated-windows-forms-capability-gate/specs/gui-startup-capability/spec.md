# Spec Delta

## Purpose

Ensures the installer starts its Windows Forms interface only on a host that can run the documented GUI and provides a safe CLI recovery path when GUI capability is unavailable.

## ADDED Requirements

### Requirement: Validate GUI capability before GUI startup

The installer MUST validate the supported Windows release, PowerShell engine and version, x64 process architecture, STA thread, required runtime, and required GUI assemblies before loading GUI helpers or constructing forms. A failed check MUST include a stable reason code and readable recovery guidance.

#### Scenario: All GUI capabilities are available

- **WHEN** each documented Windows GUI capability passes
- **THEN** the installer MAY load GUI helpers and construct the existing interface

#### Scenario: A GUI capability is unavailable

- **WHEN** any documented GUI capability fails
- **THEN** the installer MUST NOT load GUI helpers or construct forms
- **AND** it MUST report the reason and recovery guidance

### Requirement: Fall back to the Windows CLI once

When GUI capability fails and the documented Windows CLI is supported, the installer MUST start the CLI once with the original CLI arguments and return the CLI process exit code.

#### Scenario: Windows Forms runtime is unavailable

- **WHEN** the Windows host supports the CLI but cannot load a required GUI assembly
- **THEN** the installer MUST invoke the CLI with the original arguments
- **AND** it MUST return the CLI process exit code without repeating the installer workflow

#### Scenario: CLI mode is forced

- **WHEN** the caller selects forced CLI mode
- **THEN** the installer MUST invoke the supported CLI without loading GUI assemblies or constructing a form

### Requirement: Stop safely when no supported entry point is available

If neither the GUI nor the Windows CLI meets its compatibility contract, the installer MUST explain the failed capability and recovery path, then stop before helper loading, form construction, downloads, package-manager calls, elevation, or persistent changes.

#### Scenario: Unsupported Windows host

- **WHEN** the operating system, release, edition, architecture, or PowerShell engine is outside the support contract
- **THEN** startup MUST stop before installer actions
- **AND** no runtime or prerequisite MUST be installed as part of detection

### Requirement: Preserve cross-platform CLI behavior

The GUI entry point MUST continue to delegate non-Windows execution to the existing cross-platform CLI behavior without applying Windows GUI capability rules to that CLI.

#### Scenario: Non-Windows invocation

- **WHEN** the entry point runs on macOS or Linux
- **THEN** it MUST use the existing cross-platform CLI compatibility and package-manager behavior
