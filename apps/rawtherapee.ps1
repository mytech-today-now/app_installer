<#
.SYNOPSIS
    Installs RawTherapee.
.DESCRIPTION
    Cross-platform installer for RawTherapee.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : rawtherapee.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "RawTherapee"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "RawTherapee.RawTherapee" `
        -BrewCask "rawtherapee" `
        -AptPackage "rawtherapee" `
        -DnfPackage "rawtherapee" `
        -PacmanPackage "rawtherapee" `
        -SnapPackage "rawtherapee"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
