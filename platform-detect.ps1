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

#region Platform Detection Variables

# Detect platform - PowerShell 7+ has $IsWindows, $IsMacOS, $IsLinux
# PowerShell 5.1 (Windows only) does not have these
if ($null -eq $IsWindows) {
    # PowerShell 5.1 - must be Windows
    $script:Platform = "Windows"
}
elseif ($IsWindows) {
    $script:Platform = "Windows"
}
elseif ($IsMacOS) {
    $script:Platform = "macOS"
}
elseif ($IsLinux) {
    $script:Platform = "Linux"
}
else {
    # Fallback: check env var
    if ($env:OS -match 'Windows') {
        $script:Platform = "Windows"
    }
    else {
        $script:Platform = "Unknown"
    }
}

# Linux distribution detection
$script:LinuxDistro = $null
if ($script:Platform -eq "Linux") {
    # Check /etc/os-release first (most common)
    if (Test-Path "/etc/os-release") {
        $osRelease = Get-Content "/etc/os-release" -ErrorAction SilentlyContinue
        $idLine = $osRelease | Where-Object { $_ -match '^ID=' }
        if ($idLine) {
            $distroId = ($idLine -replace '^ID=', '').Trim('"').ToLower()
            $script:LinuxDistro = switch ($distroId) {
                'debian' { 'Debian' }
                'ubuntu' { 'Ubuntu' }
                'fedora' { 'Fedora' }
                'rhel' { 'RHEL' }
                'centos' { 'RHEL' }
                'arch' { 'Arch' }
                'manjaro' { 'Arch' }
                default { 'Unknown' }
            }
        }
    }
    # Fallback: check distro-specific files
    elseif (Test-Path "/etc/debian_version") {
        $script:LinuxDistro = "Debian"
    }
    elseif (Test-Path "/etc/redhat-release") {
        $script:LinuxDistro = "RHEL"
    }
    else {
        $script:LinuxDistro = "Unknown"
    }
}

#endregion

#region Package Manager Detection

$script:PackageManager = $null

switch ($script:Platform) {
    "Windows" {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $script:PackageManager = "winget"
        }
    }
    "macOS" {
        if (Get-Command brew -ErrorAction SilentlyContinue) {
            $script:PackageManager = "brew"
        }
    }
    "Linux" {
        # Check in priority order: apt, dnf, pacman, snap
        if (Get-Command apt -ErrorAction SilentlyContinue) {
            $script:PackageManager = "apt"
        }
        elseif (Get-Command dnf -ErrorAction SilentlyContinue) {
            $script:PackageManager = "dnf"
        }
        elseif (Get-Command pacman -ErrorAction SilentlyContinue) {
            $script:PackageManager = "pacman"
        }
        elseif (Get-Command snap -ErrorAction SilentlyContinue) {
            $script:PackageManager = "snap"
        }
    }
}

#endregion

#region Admin/Elevation Detection

$script:IsAdmin = $false

if ($script:Platform -eq "Windows") {
    # Windows: Check if running as Administrator
    $currentPrincipal = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    $script:IsAdmin = $currentPrincipal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}
else {
    # macOS/Linux: Check if running as root (UID 0)
    if ($null -ne $env:EUID) {
        $script:IsAdmin = ($env:EUID -eq "0")
    }
    elseif (Get-Command id -ErrorAction SilentlyContinue) {
        $uid = & id -u 2>$null
        $script:IsAdmin = ($uid -eq "0")
    }
}

#endregion

#region Helper Functions

function Test-Platform {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Windows", "macOS", "Linux", "All")]
        [string]$Required
    )

    if ($Required -eq "All") {
        return $true
    }
    return ($script:Platform -eq $Required)
}

function Assert-Platform {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Windows", "macOS", "Linux")]
        [string]$Required,

        [string]$AppName = "This application"
    )

    if ($script:Platform -ne $Required) {
        Write-Host "[INFO] $AppName is only available for $Required." -ForegroundColor Yellow
        exit 0
    }
}

function Get-PackageManagerCommand {
    [CmdletBinding()]
    param(
        [string]$WingetId,
        [string]$BrewCask,
        [string]$BrewFormula,
        [string]$AptPackage,
        [string]$DnfPackage,
        [string]$PacmanPackage,
        [string]$SnapPackage
    )

    $result = @{
        Command   = $null
        Available = $false
    }

    switch ($script:PackageManager) {
        "winget" {
            if ($WingetId) {
                $result.Command = "winget install --id $WingetId --silent --accept-source-agreements --accept-package-agreements"
                $result.Available = $true
            }
        }
        "brew" {
            if ($BrewCask) {
                $result.Command = "brew install --cask $BrewCask"
                $result.Available = $true
            }
            elseif ($BrewFormula) {
                $result.Command = "brew install $BrewFormula"
                $result.Available = $true
            }
        }
        "apt" {
            if ($AptPackage) {
                $result.Command = "sudo apt install -y $AptPackage"
                $result.Available = $true
            }
        }
        "dnf" {
            if ($DnfPackage) {
                $result.Command = "sudo dnf install -y $DnfPackage"
                $result.Available = $true
            }
        }
        "pacman" {
            if ($PacmanPackage) {
                $result.Command = "sudo pacman -S --noconfirm $PacmanPackage"
                $result.Available = $true
            }
        }
        "snap" {
            if ($SnapPackage) {
                $result.Command = "sudo snap install $SnapPackage"
                $result.Available = $true
            }
        }
    }

    if (-not $result.Available) {
        return $null
    }

    return $result
}

function Install-CrossPlatformApp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        [string]$WingetId,
        [string]$BrewCask,
        [string]$BrewFormula,
        [string]$AptPackage,
        [string]$DnfPackage,
        [string]$PacmanPackage,
        [string]$SnapPackage
    )

    # Check if any package manager is available
    if (-not $script:PackageManager) {
        Write-Host "[ERROR] No supported package manager found on this system." -ForegroundColor Red
        return 1
    }

    # Get the install command for current platform
    $pkgInfo = Get-PackageManagerCommand `
        -WingetId $WingetId `
        -BrewCask $BrewCask `
        -BrewFormula $BrewFormula `
        -AptPackage $AptPackage `
        -DnfPackage $DnfPackage `
        -PacmanPackage $PacmanPackage `
        -SnapPackage $SnapPackage

    if (-not $pkgInfo) {
        Write-Host "[INFO] $AppName is not available for $script:Platform via $script:PackageManager." -ForegroundColor Yellow
        return 0
    }

    Write-Host "[INFO] Installing $AppName via $script:PackageManager..." -ForegroundColor Cyan

    try {
        # Execute the install command
        if ($script:Platform -eq "Windows") {
            $output = Invoke-Expression $pkgInfo.Command 2>&1
        }
        else {
            # For macOS/Linux, use bash to run the command
            $output = & bash -c $pkgInfo.Command 2>&1
        }

        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] $AppName installed successfully!" -ForegroundColor Green
            return 0
        }
        else {
            Write-Host "[ERROR] Failed to install $AppName (exit code: $LASTEXITCODE)" -ForegroundColor Red
            if ($output) {
                Write-Host "       $output" -ForegroundColor Gray
            }
            return 1
        }
    }
    catch {
        Write-Host "[ERROR] Exception during installation: $_" -ForegroundColor Red
        return 1
    }
}

#endregion

#region Export Variables for Caller Scope

# When dot-sourced, also set variables in caller's scope for direct access
$Platform = $script:Platform
$LinuxDistro = $script:LinuxDistro
$PackageManager = $script:PackageManager
$IsAdmin = $script:IsAdmin

# Export summary when dot-sourced (for debugging)
Write-Verbose "Platform Detection Module Loaded:"
Write-Verbose "  Platform: $Platform"
Write-Verbose "  LinuxDistro: $LinuxDistro"
Write-Verbose "  PackageManager: $PackageManager"
Write-Verbose "  IsAdmin: $IsAdmin"

#endregion

