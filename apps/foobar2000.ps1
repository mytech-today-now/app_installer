<#
.SYNOPSIS
    Installs foobar2000.
.DESCRIPTION
    Cross-platform installer for foobar2000 audio player.
    Supports Windows (winget) and macOS (Homebrew).
.NOTES
    File Name      : foobar2000.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "foobar2000"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "PeterPawlowski.foobar2000" `
        -BrewCask "foobar2000"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
