# Phase 1: Create Platform Detection Module

## Objective

Create a shared PowerShell module `app_installer/platform-detect.ps1` that provides cross-platform operating system detection and package manager abstraction for all app installer scripts.

## Requirements

### 1. Platform Detection Variables

The module must export the following script-scope variables after being dot-sourced:

```powershell
$script:Platform        # "Windows", "macOS", or "Linux"
$script:LinuxDistro     # "Debian", "Ubuntu", "Fedora", "RHEL", "Arch", "Unknown" (only set on Linux)
$script:PackageManager  # "winget", "brew", "apt", "dnf", "pacman", "snap", or $null
$script:IsAdmin         # $true if running with elevated privileges
```

### 2. Platform Detection Logic

Use PowerShell 7+ automatic variables with fallbacks for PowerShell 5.1:

```powershell
# PowerShell 7+ has $IsWindows, $IsMacOS, $IsLinux
# PowerShell 5.1 (Windows only) does not have these - use $env:OS
```

For Linux distribution detection, check these files in order:
- `/etc/os-release` (parse `ID=` line)
- `/etc/debian_version` (Debian/Ubuntu)
- `/etc/redhat-release` (RHEL/Fedora/CentOS)

### 3. Package Manager Detection

Detect available package managers in this priority order:

| Platform | Package Managers (in priority order) |
|----------|--------------------------------------|
| Windows  | winget |
| macOS    | brew (Homebrew) |
| Linux    | apt (Debian/Ubuntu), dnf (Fedora/RHEL), pacman (Arch), snap (fallback) |

Use `Get-Command` with `-ErrorAction SilentlyContinue` to check availability.

### 4. Helper Functions

Create these exported functions:

#### `Test-Platform`
```powershell
function Test-Platform {
    param([ValidateSet("Windows", "macOS", "Linux", "All")][string]$Required)
    # Returns $true if current platform matches, or if "All"
    # Returns $false otherwise
}
```

#### `Assert-Platform`
```powershell
function Assert-Platform {
    param(
        [ValidateSet("Windows", "macOS", "Linux")][string]$Required,
        [string]$AppName = "This application"
    )
    # If platform doesn't match, write friendly message and exit 0
    # Example: "[INFO] PowerToys is only available for Windows."
}
```

#### `Get-PackageManagerCommand`
```powershell
function Get-PackageManagerCommand {
    param(
        [string]$WingetId,      # e.g., "Google.Chrome"
        [string]$BrewCask,      # e.g., "google-chrome" (use --cask)
        [string]$BrewFormula,   # e.g., "git" (formula, not cask)
        [string]$AptPackage,    # e.g., "google-chrome-stable"
        [string]$DnfPackage,    # e.g., "google-chrome-stable"
        [string]$PacmanPackage, # e.g., "google-chrome" (AUR)
        [string]$SnapPackage    # e.g., "chromium"
    )
    # Returns hashtable: @{ Command = "full install command"; Available = $true/$false }
    # Returns $null if app not available on current platform
}
```

#### `Install-CrossPlatformApp`
```powershell
function Install-CrossPlatformApp {
    param(
        [Parameter(Mandatory)][string]$AppName,
        [string]$WingetId,
        [string]$BrewCask,
        [string]$BrewFormula,
        [string]$AptPackage,
        [string]$DnfPackage,
        [string]$PacmanPackage,
        [string]$SnapPackage
    )
    # Installs the app using the appropriate package manager
    # Returns exit code (0 = success, 1 = failure)
    # Writes progress and result messages using [OK], [INFO], [WARN], [ERROR] format
}
```

### 5. Admin/Elevation Detection

```powershell
# Windows: Check if running as Administrator
# macOS/Linux: Check if running as root (UID 0) or if sudo is available
```

### 6. Output Format

All output must use the myTech.Today standard format:
- `[OK]` for success (Green)
- `[INFO]` for informational messages (Cyan)
- `[WARN]` for warnings (Yellow)
- `[ERROR]` for errors (Red)

### 7. File Header

Use standard myTech.Today header:
```powershell
<#
.SYNOPSIS
    Cross-platform detection module for app installers.
.DESCRIPTION
    Provides platform detection, package manager abstraction, and helper
    functions for cross-platform PowerShell app installer scripts.
.NOTES
    File Name      : platform-detect.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>
```

## Testing

After creating the module, test it by:
1. Dot-sourcing it: `. ./platform-detect.ps1`
2. Checking `$Platform`, `$PackageManager`, `$IsAdmin`
3. Testing `Test-Platform -Required Windows`
4. Testing `Get-PackageManagerCommand -WingetId "Google.Chrome" -BrewCask "google-chrome"`

## Success Criteria

- [ ] Module loads without errors on PowerShell 5.1 (Windows) and PowerShell 7+ (all platforms)
- [ ] Platform detection works correctly
- [ ] Package manager detection works correctly
- [ ] Helper functions work as specified
- [ ] All output uses standard [OK]/[INFO]/[WARN]/[ERROR] format

