<#
.SYNOPSIS
    Installs GIMP image editor.
.DESCRIPTION
    Cross-platform installer for GIMP.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : gimp.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "GIMP"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "GIMP.GIMP" `
        -BrewCask "gimp" `
        -AptPackage "gimp" `
        -DnfPackage "gimp" `
        -PacmanPackage "gimp" `
        -SnapPackage "gimp"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
