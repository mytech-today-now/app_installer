<#
.SYNOPSIS
    Installs Mixxx. 
.DESCRIPTION
    Cross-platform installer for Mixxx DJ software.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman).
.NOTES
    File Name      : mixxx.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Mixxx"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Mixxx.Mixxx" `
        -BrewCask "mixxx" `
        -AptPackage "mixxx" `
        -DnfPackage "mixxx" `
        -PacmanPackage "mixxx"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
