# Phase 5: Testing and Validation

## Objective

Validate all refactored app installer scripts work correctly on Windows, and document testing requirements for macOS and Linux platforms.

## Prerequisites

- Phase 1-4 complete
- All 233 scripts have been processed (either refactored for cross-platform or guarded for Windows-only)

## Testing Scope

| Category | Count | Test Approach |
|----------|-------|---------------|
| Cross-platform scripts | ~100 | Full testing on Windows, documented tests for macOS/Linux |
| Windows-only scripts | ~130 | Platform guard verification + Windows installation test |

## Test Plan

### 1. Syntax Validation (All 233 Scripts)

Run syntax check on every script to catch any parsing errors:

```powershell
$errors = @()
Get-ChildItem "app_installer/apps/*.ps1" | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    $parseErrors = $null
    [System.Management.Automation.PSParser]::Tokenize($content, [ref]$parseErrors) | Out-Null
    if ($parseErrors) {
        $errors += @{ Script = $_.Name; Errors = $parseErrors }
    }
}
if ($errors.Count -eq 0) {
    Write-Host "[OK] All 233 scripts pass syntax validation" -ForegroundColor Green
} else {
    $errors | ForEach-Object { Write-Host "[ERROR] $($_.Script): $($_.Errors)" -ForegroundColor Red }
}
```

### 2. Platform Detection Module Test

Verify `platform-detect.ps1` works correctly:

```powershell
# Test on Windows
. "./app_installer/platform-detect.ps1"

# Verify variables
Write-Host "Platform: $Platform"           # Should be "Windows"
Write-Host "PackageManager: $PackageManager" # Should be "winget"
Write-Host "IsAdmin: $IsAdmin"             # Should be $true or $false

# Verify functions
Test-Platform -Required Windows  # Should return $true
Test-Platform -Required macOS    # Should return $false
Test-Platform -Required Linux    # Should return $false
Test-Platform -Required All      # Should return $true

# Verify package manager command generation
$cmd = Get-PackageManagerCommand -WingetId "Google.Chrome" -BrewCask "google-chrome" -AptPackage "google-chrome-stable"
Write-Host "Install command: $($cmd.Command)"
Write-Host "Available: $($cmd.Available)"
```

### 3. Windows-Only Guard Verification

Verify all Windows-only scripts have the platform guard:

```powershell
$manifest = Get-Content "app_installer/apps-manifest.json" | ConvertFrom-Json
$windowsOnly = $manifest.apps | Where-Object { $_.platform -eq "Windows" }
$missing = @()

foreach ($app in $windowsOnly) {
    $content = Get-Content "app_installer/apps/$($app.name).ps1" -Raw
    if ($content -notmatch "only available for Windows") {
        $missing += $app.name
    }
}

if ($missing.Count -eq 0) {
    Write-Host "[OK] All Windows-only scripts have platform guard" -ForegroundColor Green
} else {
    Write-Host "[WARN] Missing guard in: $($missing -join ', ')" -ForegroundColor Yellow
}
```

### 4. Cross-Platform Script Verification

Verify all cross-platform scripts import the platform detection module:

```powershell
$manifest = Get-Content "app_installer/apps-manifest.json" | ConvertFrom-Json
$crossPlatform = $manifest.apps | Where-Object { $_.platform -eq "All" }
$missing = @()

foreach ($app in $crossPlatform) {
    $content = Get-Content "app_installer/apps/$($app.name).ps1" -Raw
    if ($content -notmatch "platform-detect\.ps1") {
        $missing += $app.name
    }
}

if ($missing.Count -eq 0) {
    Write-Host "[OK] All cross-platform scripts import platform-detect.ps1" -ForegroundColor Green
} else {
    Write-Host "[WARN] Missing import in: $($missing -join ', ')" -ForegroundColor Yellow
}
```

### 5. Windows Installation Tests (Sample)

Test a representative sample of scripts on Windows:

**Development Tools:**
```powershell
.\app_installer\apps\git.ps1
.\app_installer\apps\vscode.ps1
.\app_installer\apps\nodejs.ps1
.\app_installer\apps\python.ps1
```

**Browsers:**
```powershell
.\app_installer\apps\chrome.ps1
.\app_installer\apps\firefox.ps1
.\app_installer\apps\brave.ps1
```

**Utilities:**
```powershell
.\app_installer\apps\7zip.ps1
.\app_installer\apps\vlc.ps1
```

### 6. macOS/Linux Testing Documentation

Create a testing guide for other platforms since we can't test directly:

**File:** `app_installer/CROSS_PLATFORM_TESTING.md`

```markdown
# Cross-Platform Testing Guide

## macOS Testing Requirements
- macOS 12+ (Monterey or newer)
- Homebrew installed: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
- PowerShell 7+ installed: `brew install powershell`

## Linux Testing Requirements
- Ubuntu 22.04 LTS or Debian 12 (apt)
- Fedora 39+ (dnf)
- Arch Linux (pacman)
- PowerShell 7+ installed

## Test Scripts
Run these commands to test cross-platform functionality:

### macOS
pwsh -File app_installer/apps/git.ps1
pwsh -File app_installer/apps/chrome.ps1
pwsh -File app_installer/apps/vscode.ps1

### Linux (Ubuntu/Debian)
pwsh -File app_installer/apps/git.ps1
pwsh -File app_installer/apps/firefox.ps1
pwsh -File app_installer/apps/vlc.ps1
```

## Validation Checklist

### Syntax & Structure
- [ ] All 233 scripts pass PowerShell syntax validation
- [ ] `platform-detect.ps1` loads without errors
- [ ] `apps-manifest.json` is valid JSON with all 233 entries

### Windows-Only Scripts (~130)
- [ ] All have platform guard code
- [ ] All exit gracefully with `[INFO]` message on non-Windows
- [ ] Sample tested on Windows (at least 10 scripts)

### Cross-Platform Scripts (~100)
- [ ] All import `platform-detect.ps1`
- [ ] All use `Install-CrossPlatformApp` function
- [ ] Sample tested on Windows (at least 20 scripts)
- [ ] Testing documentation created for macOS/Linux

### Integration
- [ ] `install-gui.ps1` works with refactored scripts
- [ ] Profile import/export still works
- [ ] No regressions in existing functionality

## Success Criteria

- [ ] Zero syntax errors across all 233 scripts
- [ ] All platform guards verified
- [ ] All cross-platform imports verified
- [ ] Windows installation tests pass
- [ ] Testing documentation complete
- [ ] Changes committed and pushed to repository

