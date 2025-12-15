<#
.SYNOPSIS
    Installs Kaspersky Security Cloud. 
.DESCRIPTION
    Cross-platform installer for Kaspersky Security Cloud antivirus.
    Supports Windows (winget) and macOS (Homebrew).
.NOTES
    File Name      : kaspersky.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Kaspersky Security Cloud"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Kaspersky.KasperskySecurityCloud" `
        -BrewCask "kaspersky-security-cloud"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
