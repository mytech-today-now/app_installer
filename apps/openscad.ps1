<#
.SYNOPSIS
    Installs OpenSCAD. 
.DESCRIPTION
    Cross-platform installer for OpenSCAD programmable CAD modeler.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : openscad.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "OpenSCAD"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "OpenSCAD.OpenSCAD" `
        -BrewCask "openscad" `
        -AptPackage "openscad" `
        -DnfPackage "openscad" `
        -PacmanPackage "openscad" `
        -SnapPackage "openscad"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
