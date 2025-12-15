# Phase 4: Refactor Cross-Platform Scripts

## Objective

Refactor approximately 100 cross-platform app installer scripts to support installation on Windows, macOS, and Linux using appropriate package managers for each platform.

## Prerequisites

- Phase 1 complete: `platform-detect.ps1` module exists and tested
- Phase 2 complete: `apps-manifest.json` contains package IDs for each platform
- Phase 3 complete: Windows-only scripts already have guards (skip those)

## Processing Priority

Refactor scripts in this priority order to deliver value incrementally:

### Batch 1: Development Tools (Highest Priority) ~20 scripts
Most commonly needed by developers setting up new machines:
- git, vscode, docker, nodejs, python, golang, rust, java, openjdk17, openjdk21
- cmake, php, vim, sublimetext, intellij, pycharm, netbeans, eclipse
- postman, insomnia, dbeaver, azuredatastudio, mongodbcompass

### Batch 2: Browsers ~12 scripts
Universal need across all platforms:
- chrome, firefox, brave, edge, opera, vivaldi, chromium
- librewolf, waterfox, torbrowser, palemoon, midori

### Batch 3: Communication ~12 scripts
Essential for remote work:
- discord, slack, zoom, teams, signal, telegram, whatsapp
- skype, element, mattermost, rocketchat, jitsimeet

### Batch 4: Creative Tools - Graphics & Video ~20 scripts
- gimp, inkscape, krita, blender, darktable, rawtherapee, digikam
- obs, kdenlive, shotcut, openshot, handbrake, vlc, ffmpeg
- davinciresolve, lightworks, olivevideoeditor, opentoonz, losslesscut

### Batch 5: Creative Tools - Audio ~10 scripts
- audacity, tenacity, ardour, lmms, musescore, hydrogen, mixxx
- reaper, ocenaudio

### Batch 6: Productivity & Office ~15 scripts
- libreoffice, openoffice, obsidian, joplin, simplenote, notion
- calibre, scribus, focuswriter, typora, zotero, xmind
- todoist, toggltrack, clockify, clickup, trello

### Batch 7: Security & Privacy ~10 scripts
- bitwarden, keepassxc, keepass, veracrypt, protonpass, nordpass
- bleachbit, torbrowser

### Batch 8: Utilities & System Tools ~15 scripts
- 7zip, filezilla, wireshark, nmap, putty, syncthing, duplicati
- balenaetcher, ventoy, virtualbox, vagrant, multipass
- mediainfo, mkvtoolnix, streamlink

### Batch 9: Remaining Cross-Platform Apps ~remaining
- All other apps classified as "All" or multi-platform in manifest

## Script Template

Each cross-platform script should follow this structure:

```powershell
<#
.SYNOPSIS
    Installs [App Name].
.DESCRIPTION
    Cross-platform installer for [App Name].
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : [appname].ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "[Display Name]"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "[Winget.PackageId]" `
        -BrewCask "[brew-cask-name]" `
        -AptPackage "[apt-package]" `
        -DnfPackage "[dnf-package]" `
        -PacmanPackage "[pacman-package]" `
        -SnapPackage "[snap-package]"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName: $_" -ForegroundColor Red
    exit 1
}
```

## Implementation Details

### 1. Import Platform Detection

Each script must dot-source the platform detection module:
```powershell
. "$PSScriptRoot/../platform-detect.ps1"
```

This provides access to `Install-CrossPlatformApp` and platform variables.

### 2. Use Manifest Data

Read package IDs from `apps-manifest.json` for each app:
```powershell
$manifest = Get-Content "$PSScriptRoot/../apps-manifest.json" | ConvertFrom-Json
$app = $manifest.apps | Where-Object { $_.name -eq "chrome" }
# Use $app.packages.winget, $app.packages.brewCask, etc.
```

Or hardcode the values in each script (simpler, more maintainable).

### 3. Handle Missing Packages

If an app doesn't have a package for the current platform:
```powershell
Write-Host "[INFO] $AppName is not available via $PackageManager on $Platform." -ForegroundColor Yellow
Write-Host "[INFO] Please install manually from: https://example.com/download" -ForegroundColor Yellow
exit 0
```

### 4. Special Cases

Some apps require extra steps:

**Google Chrome on Linux (apt):**
```powershell
# Requires adding Google's signing key and repository
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
sudo sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list'
sudo apt update
sudo apt install -y google-chrome-stable
```

**VS Code on Linux (apt):**
```powershell
# Requires adding Microsoft's repository
# Similar process to Chrome
```

Document these special cases in the script with comments.

## Validation Per Script

After refactoring each script:

1. **Syntax validation:**
   ```powershell
   [System.Management.Automation.PSParser]::Tokenize((Get-Content "apps/chrome.ps1" -Raw), [ref]$null)
   ```

2. **Module import test:**
   ```powershell
   . "./apps/chrome.ps1" -WhatIf  # If supported
   ```

3. **Windows test:** Run the script and verify installation

## Progress Tracking

Update the manifest with refactoring status:
```json
{
  "name": "chrome",
  "refactored": true,
  "refactoredDate": "2025-12-15",
  ...
}
```

## Success Criteria

- [ ] All ~100 cross-platform scripts use `Install-CrossPlatformApp`
- [ ] All scripts import `platform-detect.ps1`
- [ ] All scripts pass syntax validation
- [ ] All scripts work on Windows (tested)
- [ ] All scripts have correct package IDs from manifest
- [ ] Special installation cases are documented
- [ ] Batch 1 (Dev Tools) completed and committed before moving to Batch 2

