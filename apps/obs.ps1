<#
.SYNOPSIS
    Installs OBS Studio. 
.DESCRIPTION
    Cross-platform installer for OBS Studio.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : obs.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "OBS Studio"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "OBSProject.OBSStudio" `
        -BrewCask "obs" `
        -AptPackage "obs-studio" `
        -DnfPackage "obs-studio" `
        -PacmanPackage "obs-studio" `
        -SnapPackage "obs-studio"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
