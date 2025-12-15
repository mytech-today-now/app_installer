<#
.SYNOPSIS
    Installs BleachBit.
.DESCRIPTION
    Cross-platform installer for BleachBit system cleaner and privacy tool.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman).
.NOTES
    File Name      : bleachbit.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "BleachBit"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "BleachBit.BleachBit" `
        -BrewCask "bleachbit" `
        -AptPackage "bleachbit" `
        -DnfPackage "bleachbit" `
        -PacmanPackage "bleachbit"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
