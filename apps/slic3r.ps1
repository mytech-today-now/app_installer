<#
.SYNOPSIS
    Installs Slic3r. 
.DESCRIPTION
    Cross-platform installer for Slic3r 3D printing slicer.
    Supports Windows (winget) and macOS (Homebrew).
.NOTES
    File Name      : slic3r.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Slic3r"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Slic3r.Slic3r" `
        -BrewCask "slic3r"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
