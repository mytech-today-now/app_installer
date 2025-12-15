<#
.SYNOPSIS
    Installs Grammarly.
.DESCRIPTION
    Cross-platform installer for Grammarly writing assistant.
    Supports Windows (winget) and macOS (Homebrew).
.NOTES
    File Name      : grammarly.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Grammarly"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Grammarly.Grammarly" `
        -BrewCask "grammarly-desktop"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
