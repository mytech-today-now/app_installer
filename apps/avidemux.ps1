<#
.SYNOPSIS
    Installs Avidemux.
.DESCRIPTION
    Cross-platform installer for Avidemux video editor.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/pacman).
.NOTES
    File Name      : avidemux.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Avidemux"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Avidemux.Avidemux" `
        -BrewCask "avidemux" `
        -AptPackage "avidemux" `
        -PacmanPackage "avidemux-qt"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
