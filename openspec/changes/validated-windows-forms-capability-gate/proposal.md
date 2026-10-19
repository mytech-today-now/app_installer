# Proposal

## Why

GUI startup currently depends on separate host, engine, framework, assembly, and STA checks. A GUI host can pass an earlier check and still fail later while loading a required assembly, before it can reach a reliable CLI recovery path.

Source finding: `ai-prompts/pre-mortem-2026-10-17-12-01-24.html#issue-05`.

## What Changes

- Provide one GUI capability decision with stable reason codes and recovery guidance for the supported Windows release, PowerShell engine, x64 process, STA thread, runtime, and required assemblies.
- Start the supported Windows CLI once with the original CLI arguments and return its process exit code when GUI capability is unavailable.
- Keep runtime detection non-provisioning and preserve the existing GUI and CLI workflows.
- Add injected offline regression checks and run native GUI startup only on a compatible Windows host.

## Capabilities

### New Capabilities

- `gui-startup-capability`: Validate GUI host capability before GUI helpers or forms are loaded, with a safe CLI fallback.

### Modified Capabilities

None.

## Impact

Updates `app-installer.ps1`, the compatibility and runtime discovery modules, `compatibility.json`, README guidance, and focused PowerShell regression tests. No new dependencies, provisioning actions, package operations, or changes to the GUI layout are introduced.
