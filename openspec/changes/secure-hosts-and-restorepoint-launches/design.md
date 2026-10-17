# Design: Secure remote helper launches

Beads issue: `app_installer-u58`. OpenSpec change: `secure-hosts-and-restorepoint-launches`.

## Trust boundary

Use one module for the two explicitly allowed upstream repository and script-path pairs. Production release records contain no URL or digest until a reviewer has approved an immutable commit and an independent digest. The trust function validates release configuration before calling its download boundary, retrieves bytes, computes SHA-256 over those exact bytes, writes only matching bytes to a unique protected temporary file, parses that file, and then calls a process boundary.

The process boundary starts the current PowerShell executable with `-NoProfile -File`, the verified temporary script path, and the original script arguments. It does not pass an execution-policy option. The result carries download, verification, execution, and native exit status fields so callers can distinguish rejection, failure, and success.

## Caller behavior

Both app wrappers check the trust result before creating persistent helper files, config, logs, or shortcuts. While their production pin is absent they report that the helper is not configured and return failure without a request or fallback. With a reviewed pin, the existing install locations and shortcut names remain. The restore-point shortcut keeps `-Action List`; initial configuration keeps `-Action Configure -ConfigPath <path>`; user examples keep `List`, `Configure`, `Create`, and `Monitor`, including the description argument. Hosts keeps its existing helper action and supported `-Force` and `-BackupOnly` examples.

All resulting direct launches use `-NoProfile -File`. Nonzero child exit codes remain failures and are reported as such. A launch exception or unknown child result is never reported as success.

## Offline proof

Tests inject byte-array download functions and fake process executors. They verify no download on missing or malformed configuration, no execution on mutable URI or digest mismatch, no execution after an unavailable source, exact argument delivery, native exit-code propagation, and no rejected-content sentinel. Wrapper checks also establish that the production pin records are empty and that shortcuts and documented commands contain no process-level policy override. The test does not contact upstream, invoke a package manager, or alter restore-point state.

## Limitations

Until an immutable source and independently reviewed digest are supplied, these helpers remain unavailable. This change does not verify the live upstream release, a created Windows shortcut, local administrator policy, or live hosts and restore-point behavior.
