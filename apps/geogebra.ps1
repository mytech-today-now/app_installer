<#
.SYNOPSIS
    Installs GeoGebra.
.DESCRIPTION
    Cross-platform installer for GeoGebra math software.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/snap).
.NOTES
    File Name      : geogebra.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "GeoGebra"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "GeoGebra.Classic" `
        -BrewCask "geogebra" `
        -AptPackage "geogebra" `
        -SnapPackage "geogebra"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
