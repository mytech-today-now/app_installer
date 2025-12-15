<#
.SYNOPSIS
    Installs Stellarium.
.DESCRIPTION
    Cross-platform installer for Stellarium planetarium software.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : stellarium.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Stellarium"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Stellarium.Stellarium" `
        -BrewCask "stellarium" `
        -AptPackage "stellarium" `
        -DnfPackage "stellarium" `
        -PacmanPackage "stellarium" `
        -SnapPackage "stellarium-daily"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
