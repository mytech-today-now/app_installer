<#
.SYNOPSIS
    Installs FreeFileSync. 
.DESCRIPTION
    Cross-platform installer for FreeFileSync file synchronization.
    Supports Windows (winget) and macOS (Homebrew).
.NOTES
    File Name      : freefilesync.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "FreeFileSync"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "FreeFileSync.FreeFileSync" `
        -BrewCask "freefilesync"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
