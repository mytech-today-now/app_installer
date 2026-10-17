# Remote helper launch security

Beads issue: `app_installer-u58`. OpenSpec change: `secure-hosts-and-restorepoint-launches`.

## ADDED Requirements

### Requirement: Verify remote helper bytes before launch

The installer MUST make no request for a helper whose release URI or SHA-256 pin is missing or malformed. A configured URI MUST use HTTPS, the expected upstream repository and script path, and a full immutable commit identifier. The configured SHA-256 MUST be a full 64-hex digest independently reviewed for that commit. The installer MUST hash the exact downloaded bytes and MUST NOT execute bytes whose digest differs from the pin.

#### Scenario: Production release has no reviewed pins

- **WHEN** the hosts or restore-point helper is selected while its release record has no URI or digest
- **THEN** the request boundary is not called
- **AND** no helper, fallback, shortcut, configuration, or restore-point change is produced
- **AND** the caller reports that the helper is unavailable because its release is not verified

#### Scenario: Invalid source or pin is supplied

- **WHEN** a source is mutable, has the wrong repository or path, or a pin is malformed
- **THEN** the request boundary is not called
- **AND** the helper is not executed

#### Scenario: Bytes differ from the reviewed digest

- **WHEN** downloaded bytes do not match the reviewed SHA-256
- **THEN** the process boundary is not called
- **AND** a sentinel embedded in the rejected content does not execute
- **AND** the result reports verification failure rather than success

#### Scenario: Source is unavailable

- **WHEN** the configured immutable source cannot be downloaded
- **THEN** the process boundary is not called
- **AND** the result reports download failure without trying a mutable URL or local fallback

### Requirement: Preserve safe launch behavior and outcomes

Every production helper launch, shortcut, and documented command MUST use a direct `-NoProfile -File` launch without a process-level execution-policy override. When a reviewed release is configured, the caller MUST preserve the existing action names and arguments, shortcut names, consent flow, and child native exit code.

#### Scenario: Verified restore-point helper is launched

- **WHEN** a digest-matching restore-point helper is launched
- **THEN** the original `-Action` and `-ConfigPath` arguments reach the child unchanged
- **AND** the shortcut retains `-Action List`
- **AND** a nonzero child exit code is reported as failure

#### Scenario: Verified hosts helper is launched

- **WHEN** a digest-matching hosts helper is launched
- **THEN** its original action arguments reach the child unchanged
- **AND** the desktop shortcut and manual command use `-NoProfile -File`
- **AND** a nonzero child exit code is reported as failure

#### Scenario: Child launch has an unknown result

- **WHEN** the process boundary throws or does not return a native exit code
- **THEN** the caller reports a failed or unknown result
- **AND** it does not claim that the helper succeeded or silently retry
