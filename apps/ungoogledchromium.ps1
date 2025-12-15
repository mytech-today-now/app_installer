<#
.SYNOPSIS
    Installs Ungoogled Chromium.  
.DESCRIPTION
    Cross-platform installer for Ungoogled Chromium privacy-focused browser.
    Supports Windows (winget) and macOS (Homebrew).
.NOTES
    File Name      : ungoogledchromium.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Ungoogled Chromium"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "AdrianGabrielK.UngoogledChromium" `
        -BrewCask "eloston-chromium"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
