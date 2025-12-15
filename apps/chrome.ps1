<#
.SYNOPSIS
    Installs Google Chrome browser.
.DESCRIPTION
    Cross-platform installer for Google Chrome.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf).
.NOTES
    File Name      : chrome.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Google Chrome"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Google.Chrome" `
        -BrewCask "google-chrome" `
        -AptPackage "google-chrome-stable" `
        -DnfPackage "google-chrome-stable"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}

