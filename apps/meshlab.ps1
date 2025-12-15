<#
.SYNOPSIS
    Installs MeshLab.
.DESCRIPTION
    Cross-platform installer for MeshLab 3D mesh processing.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/snap).
.NOTES
    File Name      : meshlab.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "MeshLab"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "ISTI.MeshLab" `
        -BrewCask "meshlab" `
        -AptPackage "meshlab" `
        -SnapPackage "meshlab"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
