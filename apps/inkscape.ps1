<#
.SYNOPSIS
    Installs Inkscape.
.DESCRIPTION
    Cross-platform installer for Inkscape.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : inkscape.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Inkscape"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Inkscape.Inkscape" `
        -BrewCask "inkscape" `
        -AptPackage "inkscape" `
        -DnfPackage "inkscape" `
        -PacmanPackage "inkscape" `
        -SnapPackage "inkscape"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
