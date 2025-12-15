<#
.SYNOPSIS
    Installs FreeCAD. 
.DESCRIPTION
    Cross-platform installer for FreeCAD 3D parametric modeler.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : freecad.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "FreeCAD"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "FreeCAD.FreeCAD" `
        -BrewCask "freecad" `
        -AptPackage "freecad" `
        -DnfPackage "freecad" `
        -PacmanPackage "freecad" `
        -SnapPackage "freecad"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
