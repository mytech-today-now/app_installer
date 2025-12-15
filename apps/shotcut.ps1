<#
.SYNOPSIS
    Installs Shotcut.
.DESCRIPTION
    Cross-platform installer for Shotcut.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : shotcut.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Shotcut"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Meltytech.Shotcut" `
        -BrewCask "shotcut" `
        -AptPackage "shotcut" `
        -DnfPackage "shotcut" `
        -PacmanPackage "shotcut" `
        -SnapPackage "shotcut"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
