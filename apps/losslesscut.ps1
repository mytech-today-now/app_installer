<#
.SYNOPSIS
    Installs LosslessCut. 
.DESCRIPTION
    Cross-platform installer for LosslessCut.
    Supports Windows (winget), macOS (Homebrew), and Linux (snap).
.NOTES
    File Name      : losslesscut.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "LosslessCut"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "MoritzBunkus.LosslessCut" `
        -BrewCask "losslesscut" `
        -SnapPackage "losslesscut"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
