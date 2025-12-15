<#
.SYNOPSIS
    Installs Celestia.
.DESCRIPTION
    Cross-platform installer for Celestia space simulation.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/pacman).
.NOTES
    File Name      : celestia.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Celestia"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "CelestiaProject.Celestia" `
        -BrewCask "celestia" `
        -AptPackage "celestia" `
        -PacmanPackage "celestia"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
