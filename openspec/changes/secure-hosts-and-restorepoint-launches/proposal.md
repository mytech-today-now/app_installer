# Proposal: Secure remote helper launches

Beads issue: `app_installer-u58`. OpenSpec change: `secure-hosts-and-restorepoint-launches`.

## Why

The hosts and restore-point app scripts fetch PowerShell from mutable URLs and launch it without checking that the bytes match a reviewed release. Their child commands, shortcuts, and usage examples also override execution policy. Restore-point setup can modify system restore settings immediately after the helper is downloaded.

## Trust policy decided before source lookup

No source lookup or helper download is approved for this change. The current branch URLs are mutable and this checkout contains no independently reviewed release digest or signer identity.

A helper may be requested and launched only when its release record contains both an HTTPS URL on `raw.githubusercontent.com` pinned to the expected repository, exact script path, and a full 40-hex commit, and an independently reviewed 64-hex SHA-256 digest. Validate the URL and both pins before network access. Hash the exact downloaded bytes before writing or execution, parse the verified file, and launch it as a file with `-NoProfile -File`. A missing, malformed, unavailable, or mismatched source or pin must stop before helper execution and before a fallback, restore-point change, or success claim. Production release pins remain unset until reviewed evidence exists.

## What changes

- Add a shared remote PowerShell trust gate with injectable download and process boundaries for offline tests.
- Route both app scripts through the gate and keep production source pins unset.
- Remove process-level execution-policy overrides from launches, shortcuts, and helper usage examples.
- Preserve the restore-point action names and values, host helper flags, user selection flow, and native child exit status when a reviewed release is configured.
- Explain that these two helpers are unavailable while their release pins are unset.

## Scope

The change covers `apps/hosts.ps1`, `apps/managerestorepoints.ps1`, their trust module, related launcher tests, README guidance, and the changelog. It does not review or fetch upstream helper content, enable either release, change application versions, or run a live hosts update or restore-point operation.
