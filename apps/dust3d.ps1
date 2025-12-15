<#
.SYNOPSIS
    Installs Dust3D. 
.DESCRIPTION
    Cross-platform installer for Dust3D 3D modeling software.
    Supports Windows (winget), macOS (Homebrew), and Linux (snap).
.NOTES
    File Name      : dust3d.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Dust3D"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Dust3D.Dust3D" `
        -BrewCask "dust3d" `
        -SnapPackage "dust3d"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
