<#
.SYNOPSIS
    Installs Lightworks.
.DESCRIPTION
    Cross-platform installer for Lightworks.
    Supports Windows (winget) and macOS (Homebrew).
.NOTES
    File Name      : lightworks.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Lightworks"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "LWKS.Lightworks" `
        -BrewCask "lightworks"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
