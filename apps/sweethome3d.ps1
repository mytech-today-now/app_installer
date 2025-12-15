<#
.SYNOPSIS
    Installs Sweet Home 3D. 
.DESCRIPTION
    Cross-platform installer for Sweet Home 3D interior design software.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/snap).
.NOTES
    File Name      : sweethome3d.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Sweet Home 3D"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "eTeks.SweetHome3D" `
        -BrewCask "sweet-home3d" `
        -AptPackage "sweethome3d" `
        -SnapPackage "sweethome3d-homedesign"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
