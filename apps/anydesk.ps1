<#
.SYNOPSIS
    Installs AnyDesk.
.DESCRIPTION
    Cross-platform installer for AnyDesk remote desktop software.
    Supports Windows (winget) and macOS (Homebrew).
    Note: Linux requires adding AnyDesk repository manually.
.NOTES
    File Name      : anydesk.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "AnyDesk"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "AnyDeskSoftwareGmbH.AnyDesk" `
        -BrewCask "anydesk"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
