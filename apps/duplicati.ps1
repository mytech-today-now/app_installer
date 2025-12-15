<#
.SYNOPSIS
    Installs Duplicati.
.DESCRIPTION
    Cross-platform installer for Duplicati backup software.
    Supports Windows (winget) and macOS (Homebrew).
.NOTES
    File Name      : duplicati.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Duplicati"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Duplicati.Duplicati" `
        -BrewCask "duplicati"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
