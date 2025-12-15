<#
.SYNOPSIS
    Installs Eclipse IDE. 
.DESCRIPTION
    Cross-platform installer for Eclipse IDE.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/snap).
.NOTES
    File Name      : eclipse.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Eclipse IDE"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "EclipseAdoptium.Temurin.17.JRE" `
        -BrewCask "eclipse-ide" `
        -AptPackage "eclipse" `
        -SnapPackage "eclipse"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}

