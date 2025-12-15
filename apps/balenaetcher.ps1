<#
.SYNOPSIS
    Installs balenaEtcher.
.DESCRIPTION
    Cross-platform installer for balenaEtcher USB image flasher.
    Supports Windows (winget), macOS (Homebrew), and Linux (snap).
.NOTES
    File Name      : balenaetcher.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "balenaEtcher"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Balena.Etcher" `
        -BrewCask "balenaetcher" `
        -SnapPackage "etcher"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}