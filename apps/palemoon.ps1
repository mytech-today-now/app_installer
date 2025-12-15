<#
.SYNOPSIS
    Installs Pale Moon browser. 
.DESCRIPTION
    Installer for Pale Moon browser.
    Windows-only: Pale Moon is not available on macOS or Linux.
.NOTES
    File Name      : palemoon.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Pale Moon"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    # Windows-only application
    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "MoonchildProductions.PaleMoon"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}

