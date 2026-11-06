# Tasks

## 1. Evidence contract and validation

- [x] 1.1 Add the machine-readable NOT RUN template and validator for supported host, engine, runtime, assembly, result, timestamp, location, and revision fields; verify complete, missing, wrong-host, wrong-engine, stale-revision, failed, and expired fixtures with test-windows-client-gui-release-evidence.ps1.
- [x] 1.2 Add the fixture test to the per-engine CI inventory and verify its documented counts with test-ci-regression-inventory.ps1.

## 2. Release gate and operator guidance

- [x] 2.1 Add the metadata-only release job, read the evidence record from the default branch, and require its exact tagged SHA before publication; verify dependencies with test-github-actions-workflow.ps1.
- [x] 2.2 Document the append-only manual evidence process and retain NOT RUN while client checks are absent; verify the checklist and README describe the Server/client boundary.

## 3. Focused validation

- [x] 3.1 Run test-compatibility-contract.ps1 and test-github-actions-workflow.ps1 under PowerShell Core 7.6.9 and record exit codes.
- [x] 3.2 Run test-windows-client-gui-release-evidence.ps1 and test-ci-regression-inventory.ps1 under Windows PowerShell Desktop 5.1 and PowerShell Core 7.6.9; both invocations must pass.
- [x] 3.3 Run and report the client capability and isolated startup checks only on a supported Windows 11 Home or Pro x64 host with each exact engine. Desktop 5.1 capability passed but isolated GUI startup hung beyond 120 seconds on two attempts; Core 7.6.9 capability and isolated startup passed. Keep the committed evidence rows NOT RUN until both engines have complete, source-bound results.

## Workflow follow-up

- [x] Archive this change after the focused checks pass and verify the versioned-unsigned-releases spec contains the updated requirement.
