<#
.SYNOPSIS
    Installs Steam.
.DESCRIPTION
    Cross-platform installer for Steam gaming platform.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/pacman).
.NOTES
    File Name      : steam.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Steam"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Valve.Steam" `
        -BrewCask "steam" `
        -AptPackage "steam" `
        -PacmanPackage "steam"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
