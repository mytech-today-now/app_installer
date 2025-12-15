<#
.SYNOPSIS
    Installs Kdenlive. 
.DESCRIPTION
    Cross-platform installer for Kdenlive.
    Supports Windows (winget), macOS (Homebrew), and Linux (apt/dnf/pacman/snap).
.NOTES
    File Name      : kdenlive.ps1
    Author         : myTech.Today
    Prerequisite   : PowerShell 5.1+ (Windows) or PowerShell 7+ (macOS/Linux)
#>

[CmdletBinding()]
param()

# Import platform detection module
. "$PSScriptRoot/../platform-detect.ps1"

$ErrorActionPreference = 'Stop'
$AppName = "Kdenlive"

try {
    Write-Host "Installing $AppName..." -ForegroundColor Cyan

    $result = Install-CrossPlatformApp -AppName $AppName `
        -WingetId "KDE.Kdenlive" `
        -BrewCask "kdenlive" `
        -AptPackage "kdenlive" `
        -DnfPackage "kdenlive" `
        -PacmanPackage "kdenlive" `
        -SnapPackage "kdenlive"

    exit $result
}
catch {
    Write-Host "[ERROR] Failed to install $AppName`: $_" -ForegroundColor Red
    exit 1
}
