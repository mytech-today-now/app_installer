# Phase 2: Create Apps Manifest JSON

## Objective

Create `app_installer/apps-manifest.json` - a comprehensive JSON manifest that categorizes all 233 app installer scripts by platform support and provides package identifiers for each supported package manager.

## Prerequisites

- Phase 1 must be complete (`platform-detect.ps1` exists)
- Review all scripts in `app_installer/apps/` directory

## Manifest Structure

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "version": "1.0.0",
  "generated": "2025-12-15T00:00:00Z",
  "description": "Cross-platform app installer manifest for myTech.Today PowerShellScripts",
  "apps": [
    {
      "name": "chrome",
      "displayName": "Google Chrome",
      "description": "Fast, secure web browser by Google",
      "category": "Browsers",
      "platform": "All",
      "packages": {
        "winget": "Google.Chrome",
        "brewCask": "google-chrome",
        "apt": "google-chrome-stable",
        "dnf": "google-chrome-stable",
        "snap": "chromium"
      },
      "notes": "On Linux, apt/dnf require adding Google's repository first"
    }
  ]
}
```

## Field Definitions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Script filename without .ps1 extension (e.g., "chrome") |
| `displayName` | string | Yes | Human-readable app name (e.g., "Google Chrome") |
| `description` | string | Yes | Brief description (match existing script .SYNOPSIS) |
| `category` | string | Yes | One of the defined categories below |
| `platform` | string | Yes | "All", "Windows", "macOS", "Linux", or "Windows+macOS" etc. |
| `packages.winget` | string | No | Windows winget package ID |
| `packages.brewCask` | string | No | macOS Homebrew cask name (GUI apps) |
| `packages.brewFormula` | string | No | macOS/Linux Homebrew formula (CLI tools) |
| `packages.apt` | string | No | Debian/Ubuntu apt package name |
| `packages.dnf` | string | No | Fedora/RHEL dnf package name |
| `packages.pacman` | string | No | Arch Linux pacman/AUR package name |
| `packages.snap` | string | No | Snap package name (cross-distro fallback) |
| `notes` | string | No | Special installation notes or requirements |

## Categories

Organize apps into these categories:

1. **Browsers** - Web browsers (Chrome, Firefox, Brave, Edge, Opera, etc.)
2. **Development** - IDEs, editors, dev tools (VS Code, Git, Docker, Node.js, Python, etc.)
3. **Communication** - Chat, video, email (Discord, Slack, Zoom, Teams, Thunderbird, etc.)
4. **Creative-Graphics** - Image/vector editing (GIMP, Inkscape, Krita, Blender, etc.)
5. **Creative-Audio** - Audio production (Audacity, Ardour, LMMS, Reaper, etc.)
6. **Creative-Video** - Video editing (OBS, Kdenlive, Shotcut, DaVinci Resolve, etc.)
7. **Productivity** - Office, notes, organization (LibreOffice, Obsidian, Joplin, etc.)
8. **Security** - Antivirus, passwords, encryption (Bitwarden, KeePassXC, VeraCrypt, etc.)
9. **Utilities** - System tools, file managers (7zip, FileZilla, VLC, etc.)
10. **System-Windows** - Windows-specific system tools (PowerToys, Sysinternals, etc.)
11. **Gaming** - Game launchers, gaming tools (Steam, Discord, etc.)
12. **Finance** - Financial/budgeting apps (GnuCash, HomeBank, etc.)
13. **Networking** - Network tools (Wireshark, PuTTY, nmap, etc.)
14. **Backup** - Backup and sync (Duplicati, Syncthing, etc.)
15. **Virtualization** - VMs and containers (Docker, VirtualBox, Vagrant, etc.)

## Platform Classification Guidelines

### "All" (Cross-Platform)
Apps available on Windows, macOS, AND Linux with official packages:
- Most browsers (Chrome, Firefox, Brave, Edge, Opera, Vivaldi)
- Most dev tools (VS Code, Git, Docker, Node.js, Python, Go, Rust)
- Most creative tools (GIMP, Inkscape, Blender, Audacity, OBS, VLC)
- Most communication (Discord, Slack, Zoom, Signal, Telegram)

### "Windows" (Windows-Only)
Apps that ONLY exist for Windows or have no viable macOS/Linux alternative:
- Windows system tools: PowerToys, Sysinternals, WinDirStat, TreeSize
- Windows-specific: Notepad++, Paint.NET, ShareX, Rufus, AutoHotkey
- Hardware monitors: CPU-Z, GPU-Z, HWInfo, CoreTemp, MSI Afterburner
- Windows backup: Macrium, Veeam, EaseUS, Cobian Backup
- Windows antivirus: Most AV software (Avast, AVG, Avira, etc.)

### "Windows+macOS" 
Apps available on Windows and macOS but NOT Linux:
- Some games launchers: Battle.net, some proprietary apps

## Research Requirements

For each of the 233 apps, you must:

1. **Verify winget ID** - Check existing script or search `winget search <name>`
2. **Find Homebrew package** - Search https://formulae.brew.sh/ for cask or formula
3. **Find apt package** - Search https://packages.ubuntu.com/ or https://packages.debian.org/
4. **Find dnf package** - Search Fedora packages or use same name as apt
5. **Find snap package** - Search https://snapcraft.io/

If a package doesn't exist for a platform, omit that field (don't set to null or empty string).

## Output File Location

Save to: `app_installer/apps-manifest.json`

## Validation

After creating the manifest:
1. Validate JSON syntax (use `ConvertFrom-Json` in PowerShell)
2. Verify all 233 apps are included
3. Verify each app has at least one package manager entry
4. Verify platform field matches available packages

## Success Criteria

- [ ] JSON file is valid and parseable
- [ ] All 233 apps from `app_installer/apps/` are included
- [ ] Each app has correct platform classification
- [ ] Cross-platform apps have package IDs for winget, brew, and at least apt
- [ ] Windows-only apps have platform set to "Windows" with only winget ID
- [ ] Categories are consistently applied

