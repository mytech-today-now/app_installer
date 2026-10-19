# Design

## Context

The GUI entry point has several compatibility boundaries: the supported Windows client, PowerShell engine and version, process architecture, apartment state, runtime, and Windows Forms assemblies. If one of the later checks fails after GUI helpers or types are referenced, startup can fail without offering the supported CLI recovery path.

## Goals and Non-Goals

Goals:

- Make one injectable capability decision cover all documented Windows GUI requirements.
- Run that decision before GUI helper loading or form construction.
- Reuse the same decision in runtime discovery so a candidate GUI host is not accepted on weaker criteria.
- Run the Windows CLI once when GUI capability is unavailable, preserving original arguments and the exact child exit code.
- Keep detection read-only and fail before installer actions when neither entry point is supported.

Non-goals:

- Installing or repairing .NET, Windows Desktop Runtime, PowerShell, or other prerequisites.
- Changing supported operating systems or the GUI layout.
- Changing package installation, elevation, or cross-platform CLI behavior.

## Decisions

1. `Test-InstallerGuiCapability` is the shared decision point. It returns a stable reason code, readable message, and recovery guidance. Its injectable inputs let offline tests cover failures without modifying the host.
2. Validate host release, engine, process architecture, STA, and the applicable framework/runtime version before loading GUI assemblies. Only then probe the required Forms, Drawing, and System.Web types.
3. For PowerShell Core, require the loaded Windows Forms and Drawing assemblies to match the documented Windows Desktop runtime major. Windows PowerShell uses the documented .NET Framework release floor.
4. Runtime discovery executes the shared decision in its candidate process and validates its structured result. The main entry point repeats the gate before GUI code is loaded, so the final process independently enforces the same contract.
5. On GUI failure, delegate once to the supported Windows CLI with the captured original arguments and propagate its exit code. Forced CLI skips GUI probing. A failed CLI preflight stops before helper imports and installer side effects.
6. Keep non-Windows CLI selection on the existing cross-platform compatibility path and do not apply the Windows GUI gate there.

## Risks and Trade-offs

- Assembly availability can differ between PowerShell engines and installed runtimes. A load failure intentionally produces a stable unsupported result and CLI recovery guidance.
- Repeating a read-only capability probe in runtime discovery and in the selected GUI process adds startup work, but it prevents the selector and application from disagreeing silently.
- The native Windows smoke exercises the current compatible host only. Injected tests cover unsupported conditions deterministically; they do not claim those other Windows configurations were run live.

## Migration Plan

No data migration is required. Update the compatibility manifest and README alongside the shared gate, runtime discovery, and entry point. Keep the new offline tests in the syntax-check list. Run the focused capability, discovery, startup-entrypoint, helper-trust, compatibility, and syntax checks. Record native GUI evidence only for the current host and close the linked Issue 5 work after all required checks pass.
