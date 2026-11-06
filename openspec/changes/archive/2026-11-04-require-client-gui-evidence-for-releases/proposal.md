# Proposal

## Why

The release workflow currently accepts Server build and engine results without requiring supported Windows client GUI evidence. A release can therefore proceed while the checked-in client checklist still says NOT RUN.

## What Changes

- Require the release path to validate complete Windows 11 client GUI evidence for Desktop 5.1 and Core 7.6.9 against the exact tagged source revision.
- Keep the Server build and engine results separate from client GUI proof.
- Provide an append-only manual evidence record and focused offline fixture coverage for missing, invalid, stale, failed, and expired evidence.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- versioned-unsigned-releases: Require successful supported-client GUI capability and isolated startup evidence before publication.

## Impact

Updates the versioned release workflow and its static contract tests, adds an evidence validation module and fixture test, updates the client release checklist and machine-readable evidence template, and revises release documentation. No package, runtime provisioning, signing, or GUI application behavior changes.
