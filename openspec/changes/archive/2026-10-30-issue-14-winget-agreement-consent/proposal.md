# Proposal

## Why

The GUI, CLI, app scripts, and monthly task currently pass WinGet's source and package agreement acceptance switches. Selecting an application only requests an install or update; it does not tell the user which third-party terms apply or record agreement-specific intent.

Source finding: Issue 14 / 20, "Package and source agreements are accepted silently across install and update paths."

## What Changes

- Remove unconditional agreement acceptance from all WinGet install, dependency, upgrade, discovery, and scheduled-update commands.
- Keep interactive install and upgrade commands on WinGet's native agreement review path and show a visible retry option when the GUI cannot present that prompt in its current host.
- Disable interactivity for discovery and scheduled updates. Required agreements become failed or incomplete outcomes, with agreement text excluded from file logs.
- Document that application selection is not agreement consent and that scheduled updates never accept terms.
- Add fake WinGet coverage for agreement-free success, package/source agreement requirements, decline, and unattended failure.

## Capabilities

### New Capabilities

- `winget-agreement-consent`: Explicit review behavior for WinGet terms across interactive and unattended paths.

### Modified Capabilities

None.

## Impact

Changes the shared WinGet argument builder, both entry points, app-specific WinGet scripts, and the monthly updater. It adds focused offline tests and documents the consent contract. No package manager, source, installer, scheduled task, or operating-system setting is exercised by validation.
