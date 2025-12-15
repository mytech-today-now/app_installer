<#
.SYNOPSIS
    Installs Hydrogen.
.DESCRIPTION
    Cross-platform installer for Hydrogen drum machine/sequencer.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman).
.NOTES
    File Name      : hydrogen.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Hydrogen"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Hydrogen.Hydrogen" `
        -BrewCask "hydrogen" `
        -AptPackage "hydrogen" `
        -DnfPackage "hydrogen" `
        -PacmanPackage "hydrogen"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
