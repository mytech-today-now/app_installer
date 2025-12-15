<#
.SYNOPSIS
    Installs REAPER.
.DESCRIPTION
    Cross-platform installer for REAPER digital audio workstation.
    Supports Windows (winget) and macOS (Homebrew).
.NOTES
    File Name      : reaper.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "REAPER"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Cockos.REAPER" `
        -BrewCask "reaper"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
