# Tasks

## 1. Wrapper behavior

- [x] 1.1 Keep immediate child-status capture and exact return, then report nonzero outcomes with the generic failure wording and code; verify fake child statuses 0, 1, and 23 through CMD and a parent batch file.
- [x] 1.2 Make console waiting opt-in through `-KeepConsoleOpen`, consume the switch in the shared launcher, and document it; verify unattended calls return and the opt-in call waits for input.
- [x] 1.3 Register the focused status test in the CI inventory and update documented counts; verify `tests/test-ci-regression-inventory.ps1` passes.

## 2. Verification

- [x] 2.1 Run the focused regression under Windows PowerShell 5.1 and PowerShell 7, run the repository syntax check, validate this OpenSpec change, and verify `git diff --check`.

## Validation record

- `pwsh -NoProfile -File .\tests\test-install-bat-status.ps1`: PASS, 38 assertions on Windows build 26300.
- `powershell.exe -NoProfile -File .\tests\test-install-bat-status.ps1`: PASS, 38 assertions on Windows build 26300.
- `pwsh -NoProfile -File .\tests\test-install-bat-elevation.ps1`: PASS, 44 assertions, including the pre-existing user-modified test changes.
- `pwsh -NoProfile -File .\tests\test-ci-regression-inventory.ps1`: PASS, 384 assertions; 37 scripts and documented engine counts match.
- `pwsh -NoProfile -File .\other_files\test-syntax.ps1`: PASS, 354 PowerShell files parse under Core 7.6.9.
- `powershell.exe -NoProfile -File .\other_files\test-syntax.ps1`: PASS, 354 PowerShell files parse under Desktop 5.1.26100.9818.
- `openspec validate issue-17-install-bat-exit-status --strict`: PASS, change is valid.
- `git diff --check`: PASS; Git reported LF-to-CRLF working-copy warnings for tracked files.
- No real installer, package manager, elevation, bootstrap, scheduled task, or operating-system action was run.

## Workflow follow-up

- Archive the validated change and verify the archived record and main capability spec.
