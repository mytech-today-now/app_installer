<#
.SYNOPSIS
    Installs Wings 3D.
.DESCRIPTION
    Cross-platform installer for Wings 3D modeling software.
    Supports Windows (winget) and macOS (Homebrew).
.NOTES
    File Name      : wings3d.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Wings 3D"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Wings3D.Wings3D" `
        -BrewCask "wings3d"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
