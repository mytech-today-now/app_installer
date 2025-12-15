<#
.SYNOPSIS
    Installs bibisco. 
.DESCRIPTION
    Cross-platform installer for bibisco novel writing software.
    Supports Windows (winget) and macOS (Homebrew).
.NOTES
    File Name      : bibisco.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "bibisco"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "bibisco.bibisco" `
        -BrewCask "bibisco"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
