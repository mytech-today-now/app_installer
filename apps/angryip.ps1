<#
.SYNOPSIS
    Installs Angry IP Scanner.
.DESCRIPTION
    Cross-platform installer for Angry IP Scanner network scanner.
    Supports Windows (winget) and macOS (Homebrew).
.NOTES
    File Name      : angryip.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Angry IP Scanner"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "angryziber.AngryIPScanner" `
        -BrewCask "angry-ip-scanner"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
