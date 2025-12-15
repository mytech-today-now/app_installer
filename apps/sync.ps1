<#
.SYNOPSIS
    Installs Sync.com. 
.DESCRIPTION
    Cross-platform installer for Sync.com cloud storage.
    Supports Windows (winget) and macOS (Homebrew).
.NOTES
    File Name      : sync.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Sync.com"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Sync.Sync" `
        -BrewCask "sync"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
