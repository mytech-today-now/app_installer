# Phase 3: Add Windows-Only Guards to Scripts

## Objective

Add platform guard code to all Windows-only app installer scripts so they exit gracefully with a friendly message when run on macOS or Linux, rather than failing with confusing winget errors.

## Prerequisites

- Phase 1 complete: `platform-detect.ps1` exists
- Phase 2 complete: `apps-manifest.json` exists with platform classifications

## Scope

This phase targets approximately 130 scripts classified as `"platform": "Windows"` in the manifest. These are apps that only exist for Windows or have no viable cross-platform installation method.

## Implementation Steps

### Step 1: Read the Manifest

Load `app_installer/apps-manifest.json` and filter for Windows-only apps:

```powershell
$manifest = Get-Content "app_installer/apps-manifest.json" | ConvertFrom-Json
$windowsOnlyApps = $manifest.apps | Where-Object { $_.platform -eq "Windows" }
```

### Step 2: Define the Guard Code

Insert this code block immediately after the `param()` statement and before `$ErrorActionPreference`:

```powershell
# Platform check - this application is Windows-only
if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host "[INFO] $AppDisplayName is only available for Windows." -ForegroundColor Yellow
    exit 0
}
```

Where `$AppDisplayName` is replaced with the actual display name from the manifest (e.g., "PowerToys", "Notepad++").

### Step 3: Update Each Script

For each Windows-only script:

1. Read the existing script content
2. Find the location after `param()` 
3. Insert the platform guard code
4. Update the `.DESCRIPTION` in the header to mention Windows-only
5. Save the modified script

### Example Transformation

**Before:**
```powershell
<#
.SYNOPSIS
    Installs PowerToys.
.DESCRIPTION
    This script installs PowerToys using winget package manager.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Installing PowerToys..." -ForegroundColor Cyan
```

**After:**
```powershell
<#
.SYNOPSIS
    Installs PowerToys.
.DESCRIPTION
    This script installs PowerToys using winget package manager.
    Windows-only: PowerToys is not available on macOS or Linux.
#>

[CmdletBinding()]
param()

# Platform check - this application is Windows-only
if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host "[INFO] PowerToys is only available for Windows." -ForegroundColor Yellow
    exit 0
}

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Installing PowerToys..." -ForegroundColor Cyan
```

## Windows-Only Apps List

The following apps should be classified as Windows-only (use manifest as source of truth):

### System Tools & Utilities
- autohotkey, bulkrename, ccleaner, coretemp, cpuz, crystaldiskinfo, crystaldiskmark
- everything, gpuz, greenshot, hwinfo, hwmonitor, imageglass, lightshot
- netlimiter, netsetman, networx, notepadplusplus, openhardwaremonitor
- paintdotnet, pdf24, powertoys, rainmeter, recuva, revouninstaller
- screentogif, sharex, shutup10, speccy, sumatrapdf, sysinternals
- systeminformer, tcpview, treesizefree, windirstat, windowsterminal

### Backup & Recovery
- cobianbackup, easeus, macrium, veeam

### Antivirus & Security (Windows versions only)
- avast, avg, avira, kaspersky, malwarebytes, sophos

### Windows-Specific
- chromeremote (has Chrome extension but installer is Windows)
- dotnet6, dotnet8 (SDK - cross-platform but winget installer is Windows)
- edge (Windows built-in, different install on other platforms)
- fiddlerclassic, glasswire, msiafterburner, onedrive
- rufus, vcredist, voicemeeterbanana, winscp

### Gaming Launchers (Windows-primary)
- battlenet, eaapp, epicgames, goggalaxy, ubisoftconnect

### Discontinued/Deprecated
- atom (discontinued), brackets (discontinued), celtx (web-only now)

## Batch Processing Script

Create a helper script to automate this process:

```powershell
# Process all Windows-only scripts
$manifest = Get-Content "apps-manifest.json" | ConvertFrom-Json
$windowsOnly = $manifest.apps | Where-Object { $_.platform -eq "Windows" }

foreach ($app in $windowsOnly) {
    $scriptPath = "apps/$($app.name).ps1"
    if (Test-Path $scriptPath) {
        # Read, modify, write
        # ... implementation ...
        Write-Host "[OK] Updated $($app.name).ps1" -ForegroundColor Green
    }
}
```

## Validation

After processing:

1. **Syntax check** all modified scripts:
   ```powershell
   Get-ChildItem "apps/*.ps1" | ForEach-Object {
       $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $_ -Raw), [ref]$null)
   }
   ```

2. **Verify guard presence** - check that each Windows-only script contains the platform check

3. **Test on Windows** - run a few scripts to ensure they still work correctly

## Success Criteria

- [ ] All ~130 Windows-only scripts have platform guard code
- [ ] All modified scripts pass syntax validation
- [ ] Scripts exit gracefully with `[INFO]` message on non-Windows
- [ ] Scripts continue to work correctly on Windows
- [ ] `.DESCRIPTION` updated to mention Windows-only status

