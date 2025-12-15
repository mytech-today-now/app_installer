<#
.SYNOPSIS
    Installs Audacity audio editor.
.DESCRIPTION
    Cross-platform installer for Audacity.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : audacity.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Audacity"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "Audacity.Audacity" `
        -BrewCask "audacity" `
        -AptPackage "audacity" `
        -DnfPackage "audacity" `
        -PacmanPackage "audacity" `
        -SnapPackage "audacity"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
